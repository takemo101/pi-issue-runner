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
    --pi-args ARGS  piに渡す追加の引数
    -h, --help      このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") 42 --no-attach
    $(basename "$0") 42 --branch custom-feature
    $(basename "$0") 42 --base develop
EOF
}

main() {
    local issue_number=""
    local custom_branch=""
    local base_branch="HEAD"
    local no_attach=false
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

    # Worktree作成
    echo ""
    echo "=== Creating Worktree ==="
    local worktree_path
    worktree_path="$(create_worktree "$branch_name" "$base_branch")"
    local full_worktree_path
    full_worktree_path="$(cd "$worktree_path" && pwd)"

    # セッション名生成
    local session_name
    session_name="$(generate_session_name "$issue_number")"

    # piコマンド構築
    local pi_command
    pi_command="$(get_config pi_command)"
    local pi_args
    pi_args="$(get_config pi_args)"
    
    # Issue番号をプロンプトとして渡す
    # 形式: pi [options] --auto "issue_number"
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
