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
#   -i, --issue NUMBER  Issue number (alternative to positional argument)
#   -b, --branch NAME   Custom branch name (default: issue-<num>-<title>)
#   --base BRANCH       Base branch (default: HEAD)
#   -w, --workflow NAME Workflow name (default: default)
#   --no-attach         Don't attach to session after creation
#   --no-cleanup        Disable auto-cleanup after agent exits
#   --reattach          Attach to existing session if available
#   --force             Remove and recreate existing session/worktree
#   --agent-args ARGS   Additional arguments for the agent
#   --pi-args ARGS      Alias for --agent-args (backward compatibility)
#   -l, --label LABEL   Session label (identification tag)
#   --list-workflows    List available workflows
#   --ignore-blockers   Skip dependency check and force execution
#   --show-config       Show current configuration (debug)
#   --list-agents       List available agent presets
#   --show-agent-config Show agent configuration (debug)
#   -v, --verbose       Enable verbose/debug logging
#   --quiet             Show only error messages
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
    -i, --issue NUMBER  Issue番号（位置引数の代替）
    -b, --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH       ベースブランチ（デフォルト: HEAD）
    -w, --workflow NAME ワークフロー名（デフォルト: default）
                        ビルトイン: default, simple, thorough, ci-fix, auto
    -l, --label LABEL   セッションラベル（識別用タグ）
    --no-attach         セッション作成後にアタッチしない
    --no-cleanup        エージェント終了後の自動クリーンアップを無効化
    --no-gates          ゲート（品質チェック）を無効化（非推奨: --skip-run を使用）
    --skip-run          run: ステップをスキップ
    --reattach          既存セッションがあればアタッチ
    --force             既存セッション/worktreeを削除して再作成
    --agent-args ARGS   エージェントに渡す追加の引数
    --pi-args ARGS      --agent-args のエイリアス（後方互換性）
    --list-workflows    利用可能なワークフロー一覧を表示
    --ignore-blockers   依存関係チェックをスキップして強制実行
    --show-config       現在の設定を表示（デバッグ用）
    --list-agents       利用可能なエージェントプリセット一覧を表示
    --show-agent-config エージェント設定を表示（デバッグ用）
    -v, --verbose       詳細ログを表示
    --quiet             エラーのみ表示
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") --issue 42
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

# コアライブラリの読み込み
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/cleanup-trap.sh"
source "$SCRIPT_DIR/../lib/workflow.sh"
source "$SCRIPT_DIR/../lib/hooks.sh"
source "$SCRIPT_DIR/../lib/agent.sh"
source "$SCRIPT_DIR/../lib/daemon.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/tracker.sh"

# run.sh 専用ライブラリの読み込み
source "$SCRIPT_DIR/../lib/run/args.sh"
source "$SCRIPT_DIR/../lib/run/worktree.sh"
source "$SCRIPT_DIR/../lib/run/session.sh"

# ============================================================================
# Subfunction: fetch_issue_data
# Purpose: Fetch Issue information and check dependencies
# Arguments: $1=issue_number, $2=ignore_blockers
# Output: Sets global variables with _ISSUE_ prefix
# ============================================================================
fetch_issue_data() {
    local issue_number="$1"
    local ignore_blockers="$2"

    log_info "Fetching Issue #$issue_number..."
    local issue_title
    issue_title="$(get_issue_title "$issue_number")"
    log_info "Title: $issue_title"

    local issue_body
    issue_body="$(get_issue_body "$issue_number" 2>/dev/null)" || issue_body=""
    issue_body="$(sanitize_issue_body "$issue_body")"

    # 依存関係チェック
    if [[ "$ignore_blockers" != "true" ]]; then
        local open_blockers
        if ! open_blockers=$(check_issue_blocked "$issue_number"); then
            log_error "Issue #$issue_number is blocked by the following issues:"
            echo "$open_blockers" | jq -r '.[] | "  - #\(.number): \(.title) (\(.state))"' >&2
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

    # Set global variables (no escaping needed - direct assignment is safe)
    _ISSUE_title="$issue_title"
    _ISSUE_body="$issue_body"
    _ISSUE_comments="$issue_comments"
}

# ============================================================================
# Subfunction: setup_completion_watcher
# Purpose: Start completion watcher process
# Arguments: $1=cleanup_mode, $2=session_name, $3=issue_number
# ============================================================================
setup_completion_watcher() {
    local cleanup_mode="$1"
    local session_name="$2"
    local issue_number="$3"

    if [[ "$cleanup_mode" != "none" ]]; then
        log_info "Starting completion watcher..."
        local watcher_log="${TMPDIR:-/tmp}/pi-watcher-${session_name}.log"
        local watcher_script
        watcher_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watch-session.sh"

        # Build watcher arguments
        local watcher_args=("$session_name")

        # Check auto_attach config setting
        local auto_attach_setting
        auto_attach_setting="$(get_config watcher_auto_attach)"
        if [[ "$auto_attach_setting" == "false" ]]; then
            watcher_args+=("--no-auto-attach")
        fi

        # Issue #553: daemonize関数を使用してプロセスグループを分離
        local watcher_pid
        watcher_pid=$(daemonize "$watcher_log" "$watcher_script" "${watcher_args[@]}")

        # Issue #693: Save watcher PID for restart functionality
        save_watcher_pid "$issue_number" "$watcher_pid"

        log_debug "Watcher PID: $watcher_pid, Log: $watcher_log"
    fi
}

# ============================================================================
# Subfunction: display_summary_and_attach
# Purpose: Display summary and optionally attach to session
# Arguments: Multiple (see function body)
# ============================================================================
display_summary_and_attach() {
    local issue_number="$1"
    local issue_title="$2"
    local worktree_path="$3"
    local branch_name="$4"
    local session_name="$5"
    local cleanup_mode="$6"
    local no_attach="$7"

    log_info "=== Summary ==="
    log_info "Issue:     #$issue_number - $issue_title"

    # Display agent info with workflow override indication
    local agent_info
    agent_info="$(get_agent_type) ($(get_agent_command))"
    if [[ -n "${AGENT_TYPE_OVERRIDE:-}" ]] || [[ -n "${AGENT_COMMAND_OVERRIDE:-}" ]]; then
        agent_info="$agent_info [workflow override]"
    fi
    log_info "Agent:     $agent_info"

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
        start_in_session="$(get_config multiplexer_start_in_session)"
        if [[ "$start_in_session" == "true" ]]; then
            log_info "Attaching to session..."
            mux_attach_session "$session_name"
        fi
    else
        log_info "Session started in background."
        log_info "Attach with: $(basename "$0")/../attach.sh $session_name"
    fi
}

# ============================================================================
# Main function
# Purpose: Orchestrate the workflow by calling subfunctions
# ============================================================================
main() {
    # Parse arguments (sets _PARSE_* global variables)
    parse_run_arguments "$@" || exit $?

    # Copy to local variables for clarity
    local issue_number="$_PARSE_issue_number"
    local custom_branch="$_PARSE_custom_branch"
    local base_branch="$_PARSE_base_branch"
    local workflow_name="$_PARSE_workflow_name"
    local no_attach="$_PARSE_no_attach"
    local reattach="$_PARSE_reattach"
    local force="$_PARSE_force"
    local extra_agent_args="$_PARSE_extra_agent_args"
    local cleanup_mode="$_PARSE_cleanup_mode"
    local list_workflows="$_PARSE_list_workflows"
    local ignore_blockers="$_PARSE_ignore_blockers"
    local session_label="$_PARSE_session_label"
    local no_gates="$_PARSE_no_gates"

    # Validate inputs
    validate_run_inputs "$issue_number" "$list_workflows"

    # Resolve base_branch with priority: --base option > config > HEAD default
    if [[ -z "$base_branch" ]]; then
        base_branch="$(get_config worktree_base_branch)"
        if [[ -z "$base_branch" ]]; then
            base_branch="HEAD"
        fi
    fi

    # Handle existing session (sets _SESSION_name)
    handle_existing_session "$issue_number" "$reattach" "$force" || exit $?
    local session_name="$_SESSION_name"

    # Fetch issue data (sets _ISSUE_* variables)
    fetch_issue_data "$issue_number" "$ignore_blockers" || exit $?
    local issue_title="$_ISSUE_title"
    local issue_body="$_ISSUE_body"
    local issue_comments="$_ISSUE_comments"

    # Auto workflow resolution (before worktree setup)
    if [[ "$workflow_name" == "auto" ]]; then
        log_info "Auto-selecting workflow..."
        workflow_name=$(resolve_auto_workflow_name "$issue_title" "$issue_body" ".")
        log_info "Selected workflow: $workflow_name"
    fi

    # Setup worktree (sets _WORKTREE_* variables)
    setup_worktree "$issue_number" "$custom_branch" "$base_branch" "$force" || exit $?
    local branch_name="$_WORKTREE_branch_name"
    local worktree_path="$_WORKTREE_path"
    local full_worktree_path="$_WORKTREE_full_path"

    # Start agent session
    start_agent_session "$session_name" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$full_worktree_path" "$workflow_name" "$issue_comments" "$extra_agent_args" "$session_label"

    # Setup completion watcher
    if [[ "$no_gates" == "true" ]]; then
        export PI_NO_GATES=1
        export PI_SKIP_RUN=1
    fi
    local skip_call="$_PARSE_skip_call"
    if [[ "$skip_call" == "true" ]]; then
        export PI_SKIP_CALL=1
    fi
    setup_completion_watcher "$cleanup_mode" "$session_name" "$issue_number"

    # Display summary and attach
    display_summary_and_attach "$issue_number" "$issue_title" "$worktree_path" "$branch_name" "$session_name" "$cleanup_mode" "$no_attach"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 設定ファイルの存在チェック（必須）
    require_config_file "pi-run" || exit 1

    # 依存関係チェック
    check_dependencies || exit 1

    # エラー時のクリーンアップを設定
    setup_cleanup_trap cleanup_worktree_on_error

    main "$@"
fi
