#!/usr/bin/env bash
# step-runner.sh - run: ステップの実行エンジン
#
# 提供関数:
#   - run_command_step: run: ステップ（外部コマンド）を実行
#   - save_run_output: run: ステップの出力をファイルに保存
#   - sanitize_filename: ステップ名をファイル名安全な形式に変換
#   - expand_step_variables: テンプレート変数を展開

set -euo pipefail

# ソースガード
if [[ -n "${_STEP_RUNNER_SH_SOURCED:-}" ]]; then
    return 0
fi
_STEP_RUNNER_SH_SOURCED="true"

_STEP_RUNNER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_STEP_RUNNER_LIB_DIR/compat.sh"
source "$_STEP_RUNNER_LIB_DIR/log.sh"
source "$_STEP_RUNNER_LIB_DIR/marker.sh"
source "$_STEP_RUNNER_LIB_DIR/yaml.sh"
source "$_STEP_RUNNER_LIB_DIR/workflow-loader.sh"

# ===================
# テンプレート変数展開
# ===================

# run: コマンド内のテンプレート変数を展開
# Usage: expand_step_variables <command_string> [issue_number] [pr_number] [branch_name] [worktree_path]
expand_step_variables() {
    local cmd="$1"
    local issue_number="${2:-${PI_ISSUE_NUMBER:-}}"
    local pr_number="${3:-${PI_PR_NUMBER:-}}"
    local branch_name="${4:-${PI_BRANCH_NAME:-}}"
    local worktree_path="${5:-${PI_WORKTREE_PATH:-}}"

    local result="$cmd"
    result="${result//\$\{issue_number\}/$issue_number}"
    result="${result//\$\{pr_number\}/$pr_number}"
    result="${result//\$\{branch_name\}/$branch_name}"
    result="${result//\$\{worktree_path\}/$worktree_path}"
    echo "$result"
}

# ===================
# run: 出力ファイル保存
# ===================

# run: 出力の最大保存サイズ（バイト）
_RUN_OUTPUT_MAX_SIZE="${PI_RUN_OUTPUT_MAX_SIZE:-102400}"  # 100KB

# ステップ名をファイル名安全な形式に変換
# Usage: sanitize_filename <description>
# Output: sanitized filename string (without extension)
sanitize_filename() {
    local name="$1"
    # 空白・スラッシュをハイフンに、ファイル名に使えない文字（:*?"<>|）を除去、連続ハイフンを1つに
    printf '%s' "$name" | tr ' /' '--' | sed 's/[:*?"<>|]//g; s/--*/-/g; s/^-//; s/-$//'
}

# run: ステップの出力をファイルに保存
# Usage: save_run_output <worktree_path> <description> <command> <exit_code> <output>
# Output: 保存先ファイルパス（worktree からの相対パス）を stdout に出力
save_run_output() {
    local worktree_path="$1"
    local description="$2"
    local command="$3"
    local exit_code="$4"
    local output="$5"

    local output_dir="$worktree_path/.pi/run-outputs"
    mkdir -p "$output_dir"

    local filename
    if [[ -n "$description" ]]; then
        filename="$(sanitize_filename "$description").log"
    else
        filename="step-$(date +%s).log"
    fi

    local output_file="$output_dir/$filename"
    local relative_path=".pi/run-outputs/$filename"

    # ヘッダ + 出力を書き込み
    {
        printf '# Step: %s\n' "$description"
        printf '# Command: %s\n' "$command"
        printf '# Exit Code: %d\n' "$exit_code"
        printf '# Timestamp: %s\n' "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
        printf '# ---\n'
        printf '%s\n' "$output"
    } > "$output_file"

    # サイズ制限（末尾を保持）
    local file_size
    file_size=$(wc -c < "$output_file" | tr -d ' ')
    if [[ "$file_size" -gt "$_RUN_OUTPUT_MAX_SIZE" ]]; then
        local tmp_file
        tmp_file="$(mktemp "${TMPDIR:-/tmp}/pi-run-output-XXXXXX")"
        printf '# [truncated: first %d bytes omitted]\n' "$(( file_size - _RUN_OUTPUT_MAX_SIZE ))"  > "$tmp_file"
        tail -c "$_RUN_OUTPUT_MAX_SIZE" "$output_file" >> "$tmp_file"
        mv "$tmp_file" "$output_file"
    fi

    log_debug "run: output saved to $relative_path (${file_size} bytes)"
    printf '%s' "$relative_path"
}

# ===================
# run: ステップ実行
# ===================

# 外部コマンドを worktree 内で実行し、出力をファイルに保存
# Usage: run_command_step <command> <timeout> <worktree_path> [issue_number] [pr_number] [branch_name] [description]
# Returns: 0=成功, 1=失敗, 124=タイムアウト
# Output: コマンドの stdout/stderr を stdout に出力
# Side effect: 出力を .pi/run-outputs/<description>.log に保存
#   保存先パスは PI_LAST_RUN_OUTPUT_PATH に設定される
run_command_step() {
    local command="$1"
    local timeout="${2:-900}"
    local worktree_path="${3:-.}"
    local issue_number="${4:-${PI_ISSUE_NUMBER:-}}"
    local pr_number="${5:-${PI_PR_NUMBER:-}}"
    local branch_name="${6:-${PI_BRANCH_NAME:-}}"
    local description="${7:-$command}"

    # テンプレート変数を展開
    local expanded_cmd
    expanded_cmd=$(expand_step_variables "$command" "$issue_number" "$pr_number" "$branch_name" "$worktree_path")

    log_info "run: $expanded_cmd (timeout: ${timeout}s)"

    # worktree 内で実行
    local output=""
    local exit_code=0
    output=$(
        cd "$worktree_path" 2>/dev/null || true
        safe_timeout "$timeout" env \
            PI_ISSUE_NUMBER="$issue_number" \
            PI_PR_NUMBER="$pr_number" \
            PI_BRANCH_NAME="$branch_name" \
            PI_WORKTREE_PATH="$worktree_path" \
            bash -c "$expanded_cmd" 2>&1
    ) || exit_code=$?

    # 出力を表示
    if [[ -n "$output" ]]; then
        echo "$output"
    fi

    # 出力をファイルに保存
    PI_LAST_RUN_OUTPUT_PATH="$(save_run_output "$worktree_path" "$description" "$expanded_cmd" "$exit_code" "$output")"
    export PI_LAST_RUN_OUTPUT_PATH

    if [[ $exit_code -eq 124 ]]; then
        log_warn "run: timed out after ${timeout}s: $command"
    elif [[ $exit_code -ne 0 ]]; then
        log_warn "run: failed (exit $exit_code): $command"
    else
        log_info "run: passed"
    fi

    return $exit_code
}


