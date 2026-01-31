#!/usr/bin/env bash
# run.sh - GitHub Issueからworktreeを作成してpiを起動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# usage関数を先に定義（依存関係なしでヘルプを表示するため）
usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number> [options]

Arguments:
    issue-number    GitHub Issue番号

Options:
    -b, --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH       ベースブランチ（デフォルト: HEAD）
    -w, --workflow NAME ワークフロー名（デフォルト: default）
                        利用可能: default, simple
    --no-attach         セッション作成後にアタッチしない
    --no-cleanup        pi終了後の自動クリーンアップを無効化
    --reattach          既存セッションがあればアタッチ
    --force             既存セッション/worktreeを削除して再作成
    --pi-args ARGS      piに渡す追加の引数
    --list-workflows    利用可能なワークフロー一覧を表示
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") 42 -w simple
    $(basename "$0") 42 --no-attach
    $(basename "$0") 42 --no-cleanup
    $(basename "$0") 42 --reattach
    $(basename "$0") 42 --force
    $(basename "$0") 42 -b custom-feature
    $(basename "$0") 42 --base develop
EOF
}

# ヘルプと--list-workflowsを先に処理（依存関係チェック前）
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --list-workflows)
            # workflow.sh をロードして一覧表示（依存関係チェック不要）
            source "$SCRIPT_DIR/../lib/config.sh"
            source "$SCRIPT_DIR/../lib/log.sh"
            source "$SCRIPT_DIR/../lib/workflow.sh"
            log_info "Available workflows:"
            list_available_workflows
            exit 0
            ;;
    esac
done

source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/workflow.sh"
source "$SCRIPT_DIR/../lib/hooks.sh"

# 依存関係チェック
check_dependencies || exit 1

# エラー時のクリーンアップを設定
setup_cleanup_trap cleanup_worktree_on_error

main() {
    local issue_number=""
    local custom_branch=""
    local base_branch="HEAD"
    local workflow_name="default"
    local no_attach=false
    local reattach=false
    local force=false
    local extra_pi_args=""
    local cleanup_mode="auto"  # デフォルト: 自動クリーンアップ
    local list_workflows=false

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
            --workflow|-w)
                workflow_name="$2"
                shift 2
                ;;
            --list-workflows)
                list_workflows=true
                shift
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
            --no-cleanup)
                cleanup_mode="none"
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
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$issue_number" ]]; then
                    issue_number="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # --list-workflowsオプションの処理
    if [[ "$list_workflows" == "true" ]]; then
        log_info "Available workflows:"
        list_available_workflows
        exit 0
    fi

    if [[ -z "$issue_number" ]]; then
        log_error "Issue number is required"
        usage >&2
        exit 1
    fi

    # 設定読み込み
    load_config

    # セッション名を早期に生成（既存チェック用）
    local session_name
    session_name="$(generate_session_name "$issue_number")"

    # 既存セッションのチェック
    if session_exists "$session_name"; then
        if [[ "$reattach" == "true" ]]; then
            log_info "Attaching to existing session: $session_name"
            attach_session "$session_name"
            exit 0
        elif [[ "$force" == "true" ]]; then
            log_info "Removing existing session: $session_name"
            kill_session "$session_name" || true
        else
            log_error "Session '$session_name' already exists."
            log_info "Options:"
            log_info "  --reattach  Attach to existing session"
            log_info "  --force     Remove and recreate session"
            exit 1
        fi
    fi

    # 並列実行数の制限チェック（--forceの場合はスキップ）
    if [[ "$force" != "true" ]]; then
        if ! check_concurrent_limit; then
            exit 1
        fi
    fi

    # Issue情報取得
    log_info "Fetching Issue #$issue_number..."
    local issue_title
    issue_title="$(get_issue_title "$issue_number")"
    log_info "Title: $issue_title"
    
    local issue_body
    issue_body="$(get_issue_body "$issue_number" 2>/dev/null)" || issue_body=""
    # サニタイズ処理を適用（セキュリティ対策）
    issue_body="$(sanitize_issue_body "$issue_body")"

    # ブランチ名決定
    local branch_name
    if [[ -n "$custom_branch" ]]; then
        branch_name="$custom_branch"
    else
        branch_name="$(issue_to_branch_name "$issue_number")"
    fi
    log_info "Branch: feature/$branch_name"

    # 既存Worktreeのチェック
    local existing_worktree
    if existing_worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
        if [[ "$force" == "true" ]]; then
            log_info "Removing existing worktree: $existing_worktree"
            remove_worktree "$existing_worktree" true || true
        else
            log_error "Worktree already exists: $existing_worktree"
            log_info "Options:"
            log_info "  --force     Remove and recreate worktree"
            exit 1
        fi
    fi

    # Worktree作成
    log_info "=== Creating Worktree ==="
    local worktree_path
    worktree_path="$(create_worktree "$branch_name" "$base_branch")"
    local full_worktree_path
    full_worktree_path="$(cd "$worktree_path" && pwd)"
    
    # エラー時クリーンアップ用にworktreeを登録
    register_worktree_for_cleanup "$full_worktree_path"

    # piコマンド構築
    local pi_command
    pi_command="$(get_config pi_command)"
    local pi_args
    pi_args="$(get_config pi_args)"
    
    # ワークフローからプロンプトファイルを生成
    local prompt_file="$full_worktree_path/.pi-prompt.md"
    log_info "Workflow: $workflow_name"
    write_workflow_prompt "$prompt_file" "$workflow_name" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$full_worktree_path"
    
    # piにプロンプトファイルを渡す（@でファイル参照）
    local full_command="$pi_command $pi_args $extra_pi_args @\"$prompt_file\""

    # tmuxセッション作成
    log_info "=== Starting Pi Session ==="
    create_session "$session_name" "$full_worktree_path" "$full_command"
    
    # セッション作成成功 - クリーンアップ対象から除外
    unregister_worktree_for_cleanup
    
    # on_start hookを実行
    run_hook "on_start" "$issue_number" "$session_name" "feature/$branch_name" "$full_worktree_path" "" "0" "$issue_title"

    # 自動クリーンアップが有効な場合、監視プロセスを起動
    if [[ "$cleanup_mode" != "none" ]]; then
        log_info "Starting completion watcher..."
        local watcher_log="/tmp/pi-watcher-${session_name}.log"
        local watcher_script
        watcher_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watch-session.sh"
        nohup "$watcher_script" "$session_name" \
            > "$watcher_log" 2>&1 &
        local watcher_pid=$!
        disown "$watcher_pid" 2>/dev/null || true
        log_debug "Watcher PID: $watcher_pid, Log: $watcher_log"
    fi

    log_info "=== Summary ==="
    log_info "Issue:     #$issue_number - $issue_title"
    log_info "Worktree:  $worktree_path"
    log_info "Branch:    feature/$branch_name"
    log_info "Session:   $session_name"
    if [[ "$cleanup_mode" == "none" ]]; then
        log_info "Cleanup:   disabled (--no-cleanup)"
    else
        log_info "Cleanup:   auto (on completion marker)"
    fi

    # アタッチ
    if [[ "$no_attach" == "false" ]]; then
        local start_in_session
        start_in_session="$(get_config tmux_start_in_session)"
        if [[ "$start_in_session" == "true" ]]; then
            log_info "Attaching to session..."
            attach_session "$session_name"
        fi
    else
        log_info "Session started in background."
        log_info "Attach with: $(basename "$0")/../attach.sh $session_name"
    fi
}

main "$@"
