#!/usr/bin/env bash
# run.sh - GitHub Issueからworktreeを作成してpiを起動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number> [options]

Arguments:
    issue-number    GitHub Issue番号

Options:
    --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH   ベースブランチ（デフォルト: HEAD）
    --no-attach     セッション作成後にアタッチしない
    --reattach      既存セッションがあればアタッチ
    --force         既存セッション/worktreeを削除して再作成
    --pi-args ARGS  piに渡す追加の引数
    -h, --help      このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") 42 --no-attach
    $(basename "$0") 42 --reattach
    $(basename "$0") 42 --force
    $(basename "$0") 42 --branch custom-feature
    $(basename "$0") 42 --base develop
EOF
}

main() {
    local issue_number=""
    local custom_branch=""
    local base_branch="HEAD"
    local no_attach=false
    local reattach=false
    local force=false
    local extra_pi_args=""

    # 引数のパース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue|-i)
                issue_number="$2"
                shift 2
                ;;
            --branch|-b)
                custom_branch="$2"
                shift 2
                ;;
            --base)
                base_branch="$2"
                shift 2
                ;;
            --no-attach)
                no_attach=true
                shift
                ;;
            --reattach)
                reattach=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --pi-args)
                extra_pi_args="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$issue_number" ]]; then
                    issue_number="$1"
                else
                    echo "Error: Unexpected argument: $1" >&2
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_number" ]]; then
        echo "Error: Issue number is required" >&2
        usage >&2
        exit 1
    fi

    # 設定読み込み
    load_config

    # セッション名生成（早期に必要）
    local session_name
    session_name="$(generate_session_name "$issue_number")"

    # 既存セッションのチェック
    if session_exists "$session_name"; then
        if [[ "$reattach" == "true" ]]; then
            echo "Attaching to existing session: $session_name"
            attach_session "$session_name"
            exit 0
        elif [[ "$force" == "true" ]]; then
            echo "Removing existing session: $session_name"
            kill_session "$session_name" || true
        else
            echo "Error: Session '$session_name' already exists." >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --reattach  Attach to existing session" >&2
            echo "  --force     Remove and recreate session" >&2
            exit 1
        fi
    fi

    # Issue情報取得
    echo "Fetching Issue #$issue_number..."
    local issue_title
    issue_title="$(get_issue_title "$issue_number")"
    echo "Title: $issue_title"

    # ブランチ名決定
    local branch_name
    if [[ -n "$custom_branch" ]]; then
        branch_name="$custom_branch"
    else
        branch_name="$(issue_to_branch_name "$issue_number")"
    fi
    echo "Branch: feature/$branch_name"

    # 既存Worktreeのチェック
    local worktree_path
    local existing_worktree
    if existing_worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
        if [[ "$force" == "true" ]]; then
            echo "Removing existing worktree: $existing_worktree"
            remove_worktree "$existing_worktree" true || true
        else
            echo "Error: Worktree already exists: $existing_worktree" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --force     Remove and recreate worktree" >&2
            exit 1
        fi
    fi

    # Worktree作成
    echo ""
    echo "=== Creating Worktree ==="
    worktree_path="$(create_worktree "$branch_name" "$base_branch")"
    local full_worktree_path
    full_worktree_path="$(cd "$worktree_path" && pwd)"

    # piコマンド構築
    local pi_command
    pi_command="$(get_config pi_command)"
    local pi_args
    pi_args="$(get_config pi_args)"
    
    # Issue番号をpiに渡す
    local full_command="$pi_command $pi_args $extra_pi_args --auto \"$issue_number\""

    # tmuxセッション作成
    echo ""
    echo "=== Starting Pi Session ==="
    create_session "$session_name" "$full_worktree_path" "$full_command"

    echo ""
    echo "=== Summary ==="
    echo "Issue:     #$issue_number - $issue_title"
    echo "Worktree:  $worktree_path"
    echo "Branch:    feature/$branch_name"
    echo "Session:   $session_name"
    echo ""

    # アタッチ
    if [[ "$no_attach" == "false" ]]; then
        local start_in_session
        start_in_session="$(get_config tmux_start_in_session)"
        if [[ "$start_in_session" == "true" ]]; then
            echo "Attaching to session..."
            attach_session "$session_name"
        fi
    else
        echo "Session started in background."
        echo "Attach with: $(basename "$0")/../attach.sh $session_name"
    fi
}

main "$@"
