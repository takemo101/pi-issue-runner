#!/usr/bin/env bash
# post-session.sh - piセッション終了後の処理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number> [options]

Arguments:
    issue-number    GitHub Issue番号

Options:
    --auto          確認なしで自動クリーンアップ
    --worktree PATH worktreeパス
    --session NAME  セッション名
    -h, --help      このヘルプを表示

This script is typically called automatically after a pi session ends.
EOF
}

# ユーザーに確認プロンプトを表示
prompt_cleanup() {
    local issue_number="$1"
    local session_name="$2"
    local worktree_path="$3"
    
    echo ""
    echo "==================================="
    echo "タスクが完了しました。"
    echo "Issue: #$issue_number"
    echo "Session: $session_name"
    echo "Worktree: $worktree_path"
    echo "==================================="
    echo ""
    
    # ユーザー入力を待つ
    local response
    read -r -p "クリーンアップしますか？ [Y/n]: " response
    
    # デフォルトはYes
    case "$response" in
        [nN]|[nN][oO])
            echo ""
            echo "クリーンアップをスキップしました。"
            echo "手動でクリーンアップする場合: $SCRIPT_DIR/cleanup.sh $issue_number"
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# クリーンアップを実行
do_cleanup() {
    local issue_number="$1"
    local session_name="$2"
    local worktree_path="$3"
    
    log_info "クリーンアップを実行中..."
    
    # Worktree削除
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        log_info "Removing worktree: $worktree_path"
        git worktree remove --force "$worktree_path" 2>/dev/null || {
            log_warn "Failed to remove worktree automatically. Manual cleanup may be required."
        }
    fi
    
    # セッション削除（自分自身のセッションを終了）
    if [[ -n "$session_name" ]] && session_exists "$session_name"; then
        log_info "Killing session: $session_name"
        # セッション終了は最後に行う（自分自身が動作中なので）
        tmux kill-session -t "$session_name" 2>/dev/null || true
    fi
    
    log_info "クリーンアップ完了"
}

main() {
    local issue_number=""
    local auto_cleanup=false
    local worktree_path=""
    local session_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto)
                auto_cleanup=true
                shift
                ;;
            --worktree)
                worktree_path="$2"
                shift 2
                ;;
            --session)
                session_name="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$issue_number" ]]; then
                    issue_number="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_number" ]]; then
        log_error "Issue number is required"
        usage >&2
        exit 1
    fi

    load_config

    # セッション名が指定されていない場合は生成
    if [[ -z "$session_name" ]]; then
        session_name="$(generate_session_name "$issue_number")"
    fi

    # worktreeパスが指定されていない場合は検索
    if [[ -z "$worktree_path" ]]; then
        worktree_path="$(find_worktree_by_issue "$issue_number" 2>/dev/null)" || worktree_path=""
    fi

    if [[ "$auto_cleanup" == "true" ]]; then
        # 自動クリーンアップモード
        log_info "Auto-cleanup mode: cleaning up Issue #$issue_number"
        do_cleanup "$issue_number" "$session_name" "$worktree_path"
    else
        # プロンプト表示モード
        if prompt_cleanup "$issue_number" "$session_name" "$worktree_path"; then
            do_cleanup "$issue_number" "$session_name" "$worktree_path"
        fi
    fi
}

main "$@"
