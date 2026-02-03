#!/usr/bin/env bash
# ci-fix-helper.sh - CI修正ヘルパースクリプト
#
# このスクリプトは lib/ci-fix.sh とその依存ライブラリをラップし、
# エージェントテンプレートやワークフローから簡単に呼び出せるようにします。
#
# Usage:
#   ./scripts/ci-fix-helper.sh detect <pr_number>
#     CI失敗タイプを検出して出力
#
#   ./scripts/ci-fix-helper.sh fix <failure_type> [worktree_path]
#     指定された失敗タイプの自動修正を試行
#
#   ./scripts/ci-fix-helper.sh handle <issue_number> <pr_number> [worktree_path]
#     CI失敗の完全な処理フロー（検出→修正→プッシュ）
#
#   ./scripts/ci-fix-helper.sh validate [worktree_path]
#     ローカル検証を実行
#
# Exit codes:
#   0 - 成功
#   1 - 失敗
#   2 - 自動修正不可（AI修正が必要）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ライブラリをロード
source "$PROJECT_ROOT/lib/log.sh"
source "$PROJECT_ROOT/lib/ci-fix.sh"

# ===================
# ヘルプ表示
# ===================

show_usage() {
    cat << 'EOF'
Usage: ci-fix-helper.sh <command> [arguments]

Commands:
  detect <pr_number>
    CI失敗タイプを検出して出力
    Returns: failure_type (lint|format|test|build|unknown)

  fix <failure_type> [worktree_path]
    指定された失敗タイプの自動修正を試行
    Returns: 0=成功, 1=失敗, 2=AI修正が必要

  handle <issue_number> <pr_number> [worktree_path]
    CI失敗の完全な処理フロー
    - 失敗検出
    - 自動修正試行
    - 変更のコミット＆プッシュ
    Returns: 0=修正成功, 1=エスカレーション必要

  validate [worktree_path]
    ローカル検証を実行（clippy + test）
    Returns: 0=成功, 1=失敗

  escalate <pr_number> <failure_log>
    PRをDraft化してエスカレーション
    Returns: 0=成功, 1=失敗

Examples:
  # CI失敗タイプを検出
  ./scripts/ci-fix-helper.sh detect 123

  # フォーマット修正を試行
  ./scripts/ci-fix-helper.sh fix format /path/to/worktree

  # 完全な処理フロー
  ./scripts/ci-fix-helper.sh handle 42 123 /path/to/worktree

  # ローカル検証
  ./scripts/ci-fix-helper.sh validate /path/to/worktree

EOF
}

# ===================
# サブコマンド: detect
# ===================

cmd_detect() {
    local pr_number="${1:-}"
    
    if [[ -z "$pr_number" ]]; then
        log_error "PR number is required"
        echo "Usage: ci-fix-helper.sh detect <pr_number>"
        exit 1
    fi
    
    log_info "Detecting CI failure type for PR #$pr_number"
    
    # 失敗ログを取得
    local failure_log
    failure_log=$(get_failed_ci_logs "$pr_number" || echo "")
    
    if [[ -z "$failure_log" ]]; then
        log_warn "Could not retrieve failure logs"
        echo "unknown"
        exit 1
    fi
    
    # 失敗タイプを分類
    local failure_type
    failure_type=$(classify_ci_failure "$failure_log")
    
    echo "$failure_type"
    exit 0
}

# ===================
# サブコマンド: fix
# ===================

cmd_fix() {
    local failure_type="${1:-}"
    local worktree_path="${2:-.}"
    
    if [[ -z "$failure_type" ]]; then
        log_error "Failure type is required"
        echo "Usage: ci-fix-helper.sh fix <failure_type> [worktree_path]"
        exit 1
    fi
    
    log_info "Attempting auto-fix for: $failure_type at $worktree_path"
    
    # 自動修正を試行
    try_auto_fix "$failure_type" "$worktree_path"
    exit $?
}

# ===================
# サブコマンド: handle
# ===================

cmd_handle() {
    local issue_number="${1:-}"
    local pr_number="${2:-}"
    local worktree_path="${3:-.}"
    
    if [[ -z "$issue_number" ]] || [[ -z "$pr_number" ]]; then
        log_error "Issue number and PR number are required"
        echo "Usage: ci-fix-helper.sh handle <issue_number> <pr_number> [worktree_path]"
        exit 1
    fi
    
    log_info "Handling CI failure for Issue #$issue_number, PR #$pr_number"
    
    # CI失敗処理（lib/ci-fix.shの関数を使用）
    handle_ci_failure "$issue_number" "$pr_number" "$worktree_path"
    local result=$?
    
    case $result in
        0)
            log_info "CI fix applied successfully"
            
            # 変更をコミット＆プッシュ
            (
                cd "$worktree_path" || exit 1
                
                if git diff --quiet && git diff --cached --quiet; then
                    log_warn "No changes to commit"
                else
                    git add -A
                    git commit -m "fix: CI修正 - 自動修正適用

Refs #$issue_number"
                    git push
                    log_info "Changes committed and pushed"
                fi
            )
            exit 0
            ;;
        1)
            log_warn "CI fix failed or requires manual intervention"
            exit 1
            ;;
        2)
            log_error "Fatal error during CI fix"
            exit 2
            ;;
        *)
            log_error "Unexpected result: $result"
            exit 2
            ;;
    esac
}

# ===================
# サブコマンド: validate
# ===================

cmd_validate() {
    local worktree_path="${1:-.}"
    
    log_info "Running local validation at $worktree_path"
    
    # ローカル検証を実行（lib/ci-fix.shの関数を使用）
    run_local_validation "$worktree_path"
    exit $?
}

# ===================
# サブコマンド: escalate
# ===================

cmd_escalate() {
    local pr_number="${1:-}"
    local failure_log="${2:-}"
    
    if [[ -z "$pr_number" ]]; then
        log_error "PR number is required"
        echo "Usage: ci-fix-helper.sh escalate <pr_number> <failure_log>"
        exit 1
    fi
    
    log_info "Escalating PR #$pr_number to manual handling"
    
    # エスカレーション処理（lib/ci-fix.shの関数を使用）
    escalate_to_manual "$pr_number" "$failure_log"
    exit $?
}

# ===================
# メイン処理
# ===================

main() {
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi
    
    shift
    
    case "$command" in
        detect)
            cmd_detect "$@"
            ;;
        fix)
            cmd_fix "$@"
            ;;
        handle)
            cmd_handle "$@"
            ;;
        validate)
            cmd_validate "$@"
            ;;
        escalate)
            cmd_escalate "$@"
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
