#!/usr/bin/env bash
# ci-fix.sh - CI失敗検出・自動修正機能
#
# このライブラリはCI失敗を検出して自動修正を試行します。
# 対応する失敗タイプ:
#   - Lint/Clippy: cargo clippy --fix
#   - Format: cargo fmt
#   - Test失敗: AI解析による修正
#   - ビルドエラー: AI解析による修正
#
# 【重要】使用状況について:
#   このファイルは他のスクリプトから直接 source されるのではなく、
#   scripts/ci-fix-helper.sh というラッパースクリプトを介して使用されます。
#   これは意図的な設計で、ライブラリ層とCLIインターフェース層を分離しています。
#
# 使用フロー:
#   agents/ci-fix.md (エージェントテンプレート)
#     → scripts/ci-fix-helper.sh (CLIラッパー)
#       → lib/ci-fix.sh (このライブラリ)
#
# 直接使用する場合:
#   source lib/ci-fix.sh
#   handle_ci_failure 42 123 /path/to/worktree
#
# 依存モジュール:
#   - lib/log.sh: ログ出力
#   - lib/github.sh: GitHub CLI操作
#   - lib/ci-monitor.sh: CI状態監視
#   - lib/ci-classifier.sh: 失敗タイプ分類
#   - lib/ci-retry.sh: リトライ管理
#
# 関連ファイル:
#   - scripts/ci-fix-helper.sh: このライブラリのCLIラッパー
#   - agents/ci-fix.md: ci-fixエージェントテンプレート
#   - workflows/ci-fix.yaml: ci-fixワークフロー定義

set -euo pipefail

__CI_FIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__CI_FIX_LIB_DIR/log.sh"
source "$__CI_FIX_LIB_DIR/github.sh"
source "$__CI_FIX_LIB_DIR/ci-monitor.sh"
source "$__CI_FIX_LIB_DIR/ci-classifier.sh"
source "$__CI_FIX_LIB_DIR/ci-retry.sh"

# ===================
# プロジェクトタイプ検出
# ===================

# プロジェクトタイプを検出
# Usage: detect_project_type [path]
# Returns: rust|node|python|bash-bats|unknown
detect_project_type() {
    local path="${1:-.}"
    
    if [[ -f "$path/Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "$path/package.json" ]]; then
        echo "node"
    elif [[ -f "$path/pyproject.toml" ]] || [[ -f "$path/setup.py" ]]; then
        echo "python"
    elif [[ -f "$path/test/test_helper.bash" ]] && [[ -d "$path/test" ]]; then
        # Batsテストを使用しているプロジェクト
        echo "bash-bats"
    else
        echo "unknown"
    fi
}

# プロジェクトタイプ別のlint修正コマンドを取得
# Usage: get_lint_fix_command <project_type>
get_lint_fix_command() {
    local project_type="$1"
    
    case "$project_type" in
        rust)
            echo "cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features"
            ;;
        node)
            echo "npm run lint:fix || npx eslint --fix . || true"
            ;;
        python)
            echo "pylint --fix . || flake8 --fix . || true"
            ;;
        bash-bats)
            echo "shellcheck -x scripts/*.sh lib/*.sh 2>&1 || true"
            ;;
        *)
            return 1
            ;;
    esac
}

# プロジェクトタイプ別のformat修正コマンドを取得
# Usage: get_format_fix_command <project_type>
get_format_fix_command() {
    local project_type="$1"
    
    case "$project_type" in
        rust)
            echo "cargo fmt --all"
            ;;
        node)
            echo "npm run format || npx prettier --write . || true"
            ;;
        python)
            echo "black . || autopep8 --in-place --recursive . || true"
            ;;
        bash-bats)
            # Bashは通常フォーマッタを使わないが、shfmtがあれば使用
            echo "shfmt -w -i 4 scripts/*.sh lib/*.sh 2>&1 || true"
            ;;
        *)
            return 1
            ;;
    esac
}

# プロジェクトタイプ別の検証コマンドを取得
# Usage: get_validation_command <project_type>
get_validation_command() {
    local project_type="$1"
    
    case "$project_type" in
        rust)
            echo "cargo clippy --all-targets --all-features -- -D warnings && cargo test --lib"
            ;;
        node)
            echo "npm run lint && npm test"
            ;;
        python)
            echo "pylint . && pytest"
            ;;
        bash-bats)
            echo "shellcheck -x scripts/*.sh lib/*.sh && bats test/**/*.bats"
            ;;
        *)
            return 1
            ;;
    esac
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

# Lint修正を試行（プロジェクト非依存）
# Usage: try_fix_lint [worktree_path]
try_fix_lint() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix lint issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    if [[ "$project_type" == "unknown" ]]; then
        log_warn "Unknown project type. Cannot auto-fix lint issues."
        return 2
    fi
    
    # lint修正コマンドを取得
    local fix_command
    if ! fix_command=$(get_lint_fix_command "$project_type"); then
        log_warn "No lint fix command available for project type: $project_type"
        return 2
    fi
    
    log_info "Detected project type: $project_type"
    log_info "Running: $fix_command"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        if eval "$fix_command" 2>&1; then
            log_info "Lint fix applied successfully"
            return 0
        else
            log_error "Lint fix failed"
            return 1
        fi
    )
}

# フォーマット修正を試行（プロジェクト非依存）
# Usage: try_fix_format [worktree_path]
try_fix_format() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix format issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    if [[ "$project_type" == "unknown" ]]; then
        log_warn "Unknown project type. Cannot auto-fix format issues."
        return 2
    fi
    
    # format修正コマンドを取得
    local fix_command
    if ! fix_command=$(get_format_fix_command "$project_type"); then
        log_warn "No format fix command available for project type: $project_type"
        return 2
    fi
    
    log_info "Detected project type: $project_type"
    log_info "Running: $fix_command"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        if eval "$fix_command" 2>&1; then
            log_info "Format fix applied successfully"
            return 0
        else
            log_error "Format fix failed"
            return 1
        fi
    )
}

# ローカル検証を実行（プロジェクト非依存）
# Usage: run_local_validation [worktree_path]
# Returns: 0=検証成功, 1=検証失敗
run_local_validation() {
    local worktree_path="${1:-.}"
    
    log_info "Running local validation..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    if [[ "$project_type" == "unknown" ]]; then
        log_warn "Unknown project type. Skipping local validation."
        return 0
    fi
    
    # 検証コマンドを取得
    local validation_command
    if ! validation_command=$(get_validation_command "$project_type"); then
        log_warn "No validation command available for project type: $project_type"
        return 0
    fi
    
    log_info "Detected project type: $project_type"
    log_info "Running: $validation_command"
    
    (
        cd "$worktree_path" || return 1
        
        if eval "$validation_command" 2>&1; then
            log_info "Local validation passed"
            return 0
        else
            log_error "Local validation failed"
            return 1
        fi
    )
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
