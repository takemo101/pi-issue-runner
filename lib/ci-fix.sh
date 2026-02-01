#!/usr/bin/env bash
# ci-fix.sh - CI失敗検出・自動修正機能
#
# このライブラリはCI失敗を検出して自動修正を試行します。
# 対応する失敗タイプ:
#   - Lint/Clippy: cargo clippy --fix
#   - Format: cargo fmt
#   - Test失敗: AI解析による修正
#   - ビルドエラー: AI解析による修正

set -euo pipefail

_CI_FIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CI_FIX_LIB_DIR/log.sh"
source "$_CI_FIX_LIB_DIR/github.sh"

# ===================
# 定数定義
# ===================

# CIポーリング設定
CI_POLL_INTERVAL=30      # ポーリング間隔（秒）
CI_TIMEOUT=600           # タイムアウト（10分 = 600秒）
MAX_RETRY_COUNT=3        # 最大リトライ回数

# 失敗タイプ定義
FAILURE_TYPE_LINT="lint"
FAILURE_TYPE_FORMAT="format"
FAILURE_TYPE_TEST="test"
FAILURE_TYPE_BUILD="build"
FAILURE_TYPE_UNKNOWN="unknown"

# ===================
# CI状態監視
# ===================

# CI完了を待機（ポーリング）
# Usage: wait_for_ci_completion <pr_number> [timeout_seconds]
# Returns: 0=成功, 1=失敗, 2=タイムアウト
wait_for_ci_completion() {
    local pr_number="$1"
    local timeout="${2:-$CI_TIMEOUT}"
    local elapsed=0
    
    log_info "Waiting for CI completion (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(get_pr_checks_status "$pr_number" 2>/dev/null || echo "pending")
        
        case "$status" in
            "success")
                log_info "CI completed successfully"
                return 0
                ;;
            "failure")
                log_warn "CI failed"
                return 1
                ;;
            *)
                log_debug "CI status: $status (elapsed: ${elapsed}s)"
                ;;
        esac
        
        sleep "$CI_POLL_INTERVAL"
        elapsed=$((elapsed + CI_POLL_INTERVAL))
    done
    
    log_error "CI wait timed out after ${timeout}s"
    return 2
}

# PRのCIチェック状態を取得
# Usage: get_pr_checks_status <pr_number>
# Returns: success | failure | pending | unknown
get_pr_checks_status() {
    local pr_number="$1"
    
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI not found"
        echo "unknown"
        return 1
    fi
    
    # PRのチェック状態を取得
    local checks_json
    checks_json=$(gh pr checks "$pr_number" --json state,conclusion 2>/dev/null || echo "[]")
    
    # チェックがない場合は成功とみなす
    if [[ -z "$checks_json" || "$checks_json" == "[]" ]]; then
        echo "success"
        return 0
    fi
    
    # jqで解析
    if command -v jq &> /dev/null; then
        # 失敗があるかチェック
        if echo "$checks_json" | jq -e 'any(.[]; .state == "FAILURE" or .conclusion == "failure")' > /dev/null 2>&1; then
            echo "failure"
            return 0
        fi
        
        # 進行中があるかチェック
        if echo "$checks_json" | jq -e 'any(.[]; .state == "PENDING" or .state == "QUEUED")' > /dev/null 2>&1; then
            echo "pending"
            return 0
        fi
        
        # 全て成功
        if echo "$checks_json" | jq -e 'all(.[]; .state == "SUCCESS" or .conclusion == "success")' > /dev/null 2>&1; then
            echo "success"
            return 0
        fi
    fi
    
    echo "unknown"
    return 0
}

# ===================
# 失敗ログ取得・分析
# ===================

# 失敗したCIのログを取得
# Usage: get_failed_ci_logs <pr_number>
get_failed_ci_logs() {
    local pr_number="$1"
    
    log_info "Fetching failed CI logs for PR #$pr_number"
    
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI not found"
        return 1
    fi
    
    # 最新の失敗したワークフロー実行を取得
    local run_id
    run_id=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
    
    if [[ -z "$run_id" ]]; then
        log_warn "No failed runs found"
        return 1
    fi
    
    # 失敗したジョブのログを取得
    gh run view "$run_id" --log-failed 2>/dev/null || echo ""
}

# CI失敗タイプを分類
# Usage: classify_ci_failure <log_content>
# Returns: lint | format | test | build | unknown
classify_ci_failure() {
    local log_content="$1"
    
    # フォーマットエラーをチェック（最も具体的なので先に）
    if echo "$log_content" | grep -qE '(Diff in|would have been reformatted|fmt check failed)'; then
        echo "$FAILURE_TYPE_FORMAT"
        return 0
    fi
    
    # Lint/Clippyエラーをチェック
    if echo "$log_content" | grep -qE '(warning:|clippy::|error: could not compile.*clippy)'; then
        echo "$FAILURE_TYPE_LINT"
        return 0
    fi
    
    # テスト失敗をチェック
    if echo "$log_content" | grep -qE '(FAILED|test result: FAILED|failures:)'; then
        echo "$FAILURE_TYPE_TEST"
        return 0
    fi
    
    # ビルドエラーをチェック
    if echo "$log_content" | grep -qE '(error\[E|cannot find|unresolved import|expected.*found)'; then
        echo "$FAILURE_TYPE_BUILD"
        return 0
    fi
    
    echo "$FAILURE_TYPE_UNKNOWN"
}

# ===================
# 自動修正実行
# ===================

# 自動修正を試行
# Usage: try_auto_fix <failure_type> [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_auto_fix() {
    local failure_type="$1"
    local worktree_path="${2:-.}"
    
    log_info "Attempting auto-fix for: $failure_type"
    
    case "$failure_type" in
        "$FAILURE_TYPE_LINT")
            try_fix_lint "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_FORMAT")
            try_fix_format "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_TEST")
            # テスト失敗はAI修正が必要
            log_info "Test failures require AI-based fixing"
            return 2
            ;;
        "$FAILURE_TYPE_BUILD")
            # ビルドエラーはAI修正が必要
            log_info "Build errors require AI-based fixing"
            return 2
            ;;
        *)
            log_warn "Unknown failure type: $failure_type"
            return 2
            ;;
    esac
}

# Lint/Clippy修正を試行
# Usage: try_fix_lint [worktree_path]
try_fix_lint() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix lint/clippy issues..."
    
    # cargoがインストールされているか確認
    if ! command -v cargo &> /dev/null; then
        log_error "cargo not found. Cannot auto-fix lint issues."
        return 1
    fi
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        # clippy --fix を実行
        if cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features 2>&1; then
            log_info "Clippy fix applied successfully"
            return 0
        else
            log_error "Clippy fix failed"
            return 1
        fi
    )
}

# フォーマット修正を試行
# Usage: try_fix_format [worktree_path]
try_fix_format() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix format issues..."
    
    # cargoがインストールされているか確認
    if ! command -v cargo &> /dev/null; then
        log_error "cargo not found. Cannot auto-fix format issues."
        return 1
    fi
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        # fmt を実行
        if cargo fmt --all 2>&1; then
            log_info "Format fix applied successfully"
            return 0
        else
            log_error "Format fix failed"
            return 1
        fi
    )
}

# ローカル検証を実行
# Usage: run_local_validation [worktree_path]
# Returns: 0=検証成功, 1=検証失敗
run_local_validation() {
    local worktree_path="${1:-.}"
    
    log_info "Running local validation..."
    
    if ! command -v cargo &> /dev/null; then
        log_warn "cargo not found. Skipping local validation."
        return 0
    fi
    
    (
        cd "$worktree_path" || return 1
        
        # clippyチェック
        log_info "Running cargo clippy..."
        if ! cargo clippy --all-targets --all-features -- -D warnings 2>&1; then
            log_error "Clippy check failed"
            return 1
        fi
        
        # テスト実行（簡易版）
        log_info "Running cargo test..."
        if ! cargo test --lib 2>&1; then
            log_error "Test failed"
            return 1
        fi
        
        log_info "Local validation passed"
        return 0
    )
}

# ===================
# リトライ管理
# ===================

# リトライ状態ファイルのパスを取得
# Usage: get_retry_state_file <issue_number>
get_retry_state_file() {
    local issue_number="$1"
    local state_dir="${PI_RUNNER_STATE_DIR:-/tmp/pi-runner-state}"
    mkdir -p "$state_dir"
    echo "$state_dir/ci-retry-$issue_number"
}

# リトライ回数を取得
# Usage: get_retry_count <issue_number>
get_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# リトライ回数をインクリメント
# Usage: increment_retry_count <issue_number>
increment_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    local count
    count=$(get_retry_count "$issue_number")
    
    echo $((count + 1)) > "$state_file"
}

# リトライ回数をリセット
# Usage: reset_retry_count <issue_number>
reset_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    
    rm -f "$state_file"
}

# リトライを続行すべきか判定
# Usage: should_continue_retry <issue_number>
# Returns: 0=続行可能, 1=最大回数に達した
should_continue_retry() {
    local issue_number="$1"
    local count
    count=$(get_retry_count "$issue_number")
    
    if [[ $count -lt $MAX_RETRY_COUNT ]]; then
        log_info "Retry attempt $((count + 1))/$MAX_RETRY_COUNT"
        return 0
    else
        log_warn "Maximum retry count ($MAX_RETRY_COUNT) reached"
        return 1
    fi
}

# ===================
# エスカレーション処理
# ===================

# PRをDraft化して手動対応にエスカレート
# Usage: escalate_to_manual <pr_number> <failure_log>
escalate_to_manual() {
    local pr_number="$1"
    local failure_log="${2:-}"
    
    log_warn "Escalating to manual handling for PR #$pr_number"
    
    # PRをDraft化
    mark_pr_as_draft "$pr_number"
    
    # 失敗ログをコメント追加（要約版）
    local comment="## 🤖 CI自動修正: エスカレーション\n\n"
    comment+="CI失敗の自動修正が困難なため、手動対応が必要です。\n\n"
    comment+="### 失敗サマリー\n"
    comment+="\`\`\`\n"
    # ログの先頭500文字のみ追加
    comment+="$(echo "$failure_log" | head -c 500)"
    comment+="\n\`\`\`\n\n"
    comment+="### 対応が必要な項目\n"
    comment+="- [ ] 失敗ログの確認\n"
    comment+="- [ ] 問題の修正\n"
    comment+="- [ ] CIの再実行\n"
    
    add_pr_comment "$pr_number" "$comment"
    
    return 0
}

# PRをDraft化
# Usage: mark_pr_as_draft <pr_number>
mark_pr_as_draft() {
    local pr_number="$1"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot mark PR as draft."
        return 1
    fi
    
    log_info "Marking PR #$pr_number as draft"
    
    # PRをDraft化（gh CLIのバージョンによって方法が異なる）
    if gh pr ready "$pr_number" --undo 2>/dev/null; then
        log_info "PR marked as draft"
        return 0
    else
        # 代替方法: PRを編集してDraftに
        log_warn "Could not mark PR as draft (may require different gh CLI version)"
        return 1
    fi
}

# PRにコメント追加
# Usage: add_pr_comment <pr_number> <comment>
add_pr_comment() {
    local pr_number="$1"
    local comment="$2"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot add comment."
        return 1
    fi
    
    log_info "Adding comment to PR #$pr_number"
    
    if echo "$comment" | gh pr comment "$pr_number" -F - 2>/dev/null; then
        log_info "Comment added successfully"
        return 0
    else
        log_warn "Failed to add comment"
        return 1
    fi
}

# ===================
# メイン処理
# ===================

# CI失敗を検出して自動修正を試行
# Usage: handle_ci_failure <issue_number> <pr_number> [worktree_path]
# Returns: 0=修正成功・マージ可能, 1=修正失敗・エスカレーション必要, 2=致命的エラー
handle_ci_failure() {
    local issue_number="$1"
    local pr_number="$2"
    local worktree_path="${3:-.}"
    
    log_info "Handling CI failure for Issue #$issue_number, PR #$pr_number"
    
    # リトライ回数チェック
    if ! should_continue_retry "$issue_number"; then
        log_warn "Maximum retries reached. Escalating..."
        escalate_to_manual "$pr_number" "Maximum retry count exceeded"
        return 1
    fi
    
    # リトライ回数をインクリメント
    increment_retry_count "$issue_number"
    
    # 失敗ログを取得
    local failure_log
    failure_log=$(get_failed_ci_logs "$pr_number" || echo "")
    
    if [[ -z "$failure_log" ]]; then
        log_warn "Could not retrieve failure logs"
        escalate_to_manual "$pr_number" "Failed to retrieve CI logs"
        return 1
    fi
    
    # 失敗タイプを分類
    local failure_type
    failure_type=$(classify_ci_failure "$failure_log")
    log_info "Detected failure type: $failure_type"
    
    # 自動修正を試行
    local fix_result
    try_auto_fix "$failure_type" "$worktree_path"
    fix_result=$?
    
    case $fix_result in
        0)
            # 自動修正成功
            log_info "Auto-fix applied successfully"
            
            # ローカル検証
            if run_local_validation "$worktree_path"; then
                return 0
            else
                log_warn "Local validation failed after auto-fix"
                return 1
            fi
            ;;
        2)
            # AI修正が必要
            log_info "Auto-fix not available for this failure type. Requires AI fixing."
            return 1
            ;;
        *)
            # 修正失敗
            log_error "Auto-fix failed"
            return 1
            ;;
    esac
}
