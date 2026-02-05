#!/usr/bin/env bash
# ============================================================================
# run.sh - Execute GitHub Issue in isolated worktree
#
# Creates a Git worktree from a GitHub Issue and launches a coding agent
# in a tmux session. Supports multiple agent types including pi,
# Claude Code, OpenCode, and custom agents.
#
# Usage: ./scripts/run.sh <issue-number> [options]
#
# Arguments:
#   issue-number    GitHub Issue number to process
#
# Options:
#   -b, --branch NAME   Custom branch name (default: issue-<num>-<title>)
#   --base BRANCH       Base branch (default: HEAD)
#   -w, --workflow NAME Workflow name (default: default)
#   --no-attach         Don't attach to session after creation
#   --no-cleanup        Disable auto-cleanup after agent exits
#   --reattach          Attach to existing session if available
#   --force             Remove and recreate existing session/worktree
#   --agent-args ARGS   Additional arguments for the agent
#   --pi-args ARGS      Alias for --agent-args (backward compatibility)
#   --list-workflows    List available workflows
#   --ignore-blockers   Skip dependency check and force execution
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success or attached to existing session
#   1 - General error or invalid arguments
#   2 - Issue blocked by dependencies
#
# Examples:
#   ./scripts/run.sh 42
#   ./scripts/run.sh 42 -w simple
#   ./scripts/run.sh 42 --no-attach
#   ./scripts/run.sh 42 --force
#   ./scripts/run.sh 42 -b custom-feature
# ============================================================================

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
    --no-cleanup        エージェント終了後の自動クリーンアップを無効化
    --reattach          既存セッションがあればアタッチ
    --force             既存セッション/worktreeを削除して再作成
    --agent-args ARGS   エージェントに渡す追加の引数
    --pi-args ARGS      --agent-args のエイリアス（後方互換性）
    --list-workflows    利用可能なワークフロー一覧を表示
    --ignore-blockers   依存関係チェックをスキップして強制実行
    --show-config       現在の設定を表示（デバッグ用）
    --list-agents       利用可能なエージェントプリセット一覧を表示
    --show-agent-config エージェント設定を表示（デバッグ用）
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

# ヘルプと情報表示オプションを先に処理（依存関係チェック前）
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
        --show-config)
            source "$SCRIPT_DIR/../lib/config.sh"
            source "$SCRIPT_DIR/../lib/log.sh"
            load_config
            show_config
            exit 0
            ;;
        --list-agents)
            source "$SCRIPT_DIR/../lib/config.sh"
            source "$SCRIPT_DIR/../lib/log.sh"
            source "$SCRIPT_DIR/../lib/agent.sh"
            list_agent_presets
            exit 0
            ;;
        --show-agent-config)
            source "$SCRIPT_DIR/../lib/config.sh"
            source "$SCRIPT_DIR/../lib/log.sh"
            source "$SCRIPT_DIR/../lib/agent.sh"
            load_config
            show_agent_config
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
source "$SCRIPT_DIR/../lib/agent.sh"
source "$SCRIPT_DIR/../lib/daemon.sh"

# 設定ファイルの存在チェック（必須）
require_config_file "pi-run" || exit 1

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
    local extra_agent_args=""
    local cleanup_mode="auto"  # デフォルト: 自動クリーンアップ
    local list_workflows=false
    local ignore_blockers=false

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
            --ignore-blockers)
                ignore_blockers=true
                shift
                ;;
            --agent-args|--pi-args)
                extra_agent_args="$2"
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

    # Issue番号が正の整数であることを検証
    if [[ ! "$issue_number" =~ ^[0-9]+$ ]]; then
        log_error "Issue number must be a positive integer: $issue_number"
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
    
    # 依存関係チェック
    if [[ "$ignore_blockers" != "true" ]]; then
        local open_blockers
        if ! open_blockers=$(check_issue_blocked "$issue_number"); then
            log_error "Issue #$issue_number is blocked by the following issues:"
            echo "$open_blockers" | jq -r '.[] | "  - #\(.number): \(.title) (\(.state))"'
            log_info "Complete the blocking issues first, or use --ignore-blockers to force execution."
            exit 2
        fi
    else
        log_warn "Ignoring blockers and proceeding with Issue #$issue_number"
    fi
    
    # コメント取得（設定に応じて）
    local issue_comments=""
    local include_comments
    include_comments="$(get_config github_include_comments)"
    if [[ "$include_comments" == "true" ]]; then
        local max_comments
        max_comments="$(get_config github_max_comments)"
        issue_comments="$(get_issue_comments "$issue_number" "$max_comments" 2>/dev/null)" || issue_comments=""
        if [[ -n "$issue_comments" ]]; then
            log_debug "Fetched comments for Issue #$issue_number"
        fi
    fi

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

    # ワークフローからプロンプトファイルを生成
    local prompt_file="$full_worktree_path/.pi-prompt.md"
    log_info "Workflow: $workflow_name"
    write_workflow_prompt "$prompt_file" "$workflow_name" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$full_worktree_path" "." "$issue_comments"
    
    # エージェントコマンド構築（agent.shを使用）
    local full_command
    full_command="$(build_agent_command "$prompt_file" "$extra_agent_args")"

    # tmuxセッション作成
    log_info "=== Starting Agent Session ==="
    log_info "Agent: $(get_agent_type)"
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
        
        # Issue #553: daemonize関数を使用してプロセスグループを分離
        # nohup + disown だけでは親プロセスグループ終了時に一緒に死ぬため、
        # daemonizeで新しいセッションを作成して完全に分離する
        local watcher_pid
        watcher_pid=$(daemonize "$watcher_log" "$watcher_script" "$session_name")
        
        # Issue #693: Save watcher PID for restart functionality
        save_watcher_pid "$issue_number" "$watcher_pid"
        
        log_debug "Watcher PID: $watcher_pid, Log: $watcher_log"
    fi

    log_info "=== Summary ==="
    log_info "Issue:     #$issue_number - $issue_title"
    log_info "Agent:     $(get_agent_type) ($(get_agent_command))"
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
