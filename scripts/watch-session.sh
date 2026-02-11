#!/usr/bin/env bash
# ============================================================================
# watch-session.sh - Monitor session output and execute actions on markers
#
# Monitors tmux session output and automatically runs cleanup.sh when
# a completion marker is detected. Shows notifications and opens Terminal.app
# when an error marker is detected.
#
# Usage: ./scripts/watch-session.sh <session-name> [options]
#
# Arguments:
#   session-name    tmux session name to watch
#
# Options:
#   --marker <text>       Custom completion marker (default: ###TASK_COMPLETE_<issue>###)
#   --interval <sec>      Check interval in seconds (default: 2)
#   --cleanup-args        Additional arguments to pass to cleanup.sh
#   --no-auto-attach      Don't auto-open Terminal on error detection
#   -h, --help            Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/watch-session.sh pi-issue-42
#   ./scripts/watch-session.sh pi-issue-42 --interval 5
# ============================================================================

set -euo pipefail

# SCRIPT_DIRを保存（sourceで上書きされるため）
WATCHER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$WATCHER_SCRIPT_DIR/../lib/config.sh"
source "$WATCHER_SCRIPT_DIR/../lib/log.sh"
source "$WATCHER_SCRIPT_DIR/../lib/status.sh"
source "$WATCHER_SCRIPT_DIR/../lib/multiplexer.sh"
source "$WATCHER_SCRIPT_DIR/../lib/notify.sh"
source "$WATCHER_SCRIPT_DIR/../lib/worktree.sh"
source "$WATCHER_SCRIPT_DIR/../lib/hooks.sh"
source "$WATCHER_SCRIPT_DIR/../lib/cleanup-orphans.sh"
source "$WATCHER_SCRIPT_DIR/../lib/marker.sh"
source "$WATCHER_SCRIPT_DIR/../lib/tracker.sh"
source "$WATCHER_SCRIPT_DIR/../lib/workflow.sh"
source "$WATCHER_SCRIPT_DIR/../lib/step-runner.sh"

# Source watcher submodules
source "$WATCHER_SCRIPT_DIR/../lib/watcher/markers.sh"
source "$WATCHER_SCRIPT_DIR/../lib/watcher/phase.sh"
source "$WATCHER_SCRIPT_DIR/../lib/watcher/cleanup.sh"
source "$WATCHER_SCRIPT_DIR/../lib/watcher/output.sh"

# ============================================================================
# Global variables for marker detection
# These are managed by the marker detection functions
# ============================================================================

# Alternative markers for AI typo handling
declare -g ALT_COMPLETE_MARKER=""
declare -g ALT_ERROR_MARKER=""
declare -g PHASE_COMPLETE_MARKER=""

# ============================================================================
# Usage and Argument Parsing
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name> [options]

Arguments:
    session-name    監視するtmuxセッション名

Options:
    --marker <text>       完了マーカー（デフォルト: ###TASK_COMPLETE_<issue>###）
    --interval <sec>      監視間隔（デフォルト: 2秒）
    --cleanup-args        cleanup.shに渡す追加引数
    --no-auto-attach      エラー検知時にTerminalを自動で開かない
    -h, --help            このヘルプを表示

Description:
    tmuxセッションの出力を監視し、完了マーカーを検出したら
    自動的にcleanup.shを実行します。
    
    エラーマーカー（###TASK_ERROR_<issue>###）を検出した場合は
    macOS通知を表示し、自動的にTerminal.appでセッションにアタッチします。
EOF
}

# Parse command line arguments for watch-session
parse_watch_arguments() {
    local -n _session_name_ref=$1
    local -n _marker_ref=$2
    local -n _interval_ref=$3
    local -n _cleanup_args_ref=$4
    local -n _auto_attach_ref=$5
    shift 5
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --marker)
                _marker_ref="$2"
                shift 2
                ;;
            --interval)
                _interval_ref="$2"
                shift 2
                ;;
            --cleanup-args)
                _cleanup_args_ref="$2"
                shift 2
                ;;
            --no-auto-attach)
                _auto_attach_ref=false
                shift
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
                if [[ -z "$_session_name_ref" ]]; then
                    _session_name_ref="$1"
                fi
                shift
                ;;
        esac
    done
}

# ============================================================================
# Environment Setup
# ============================================================================

# Setup watch environment and validate session
setup_watch_environment() {
    local session_name="$1"
    local marker_var=$2
    local -n marker_ref=$marker_var
    local error_marker_var=$3
    local -n error_marker_ref=$error_marker_var
    local issue_number_var=$4
    local -n issue_number_ref=$issue_number_var
    
    if [[ -z "$session_name" ]]; then
        log_error "Session name is required"
        usage >&2
        exit 1
    fi

    # セッション存在確認
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        exit 1
    fi

    # Issue番号を抽出してマーカーを生成
    issue_number_ref=$(mux_extract_issue_number "$session_name")
    
    if [[ -z "$issue_number_ref" ]]; then
        log_error "Could not extract issue number from session name: $session_name"
        exit 1
    fi
    
    if [[ -z "$marker_ref" ]]; then
        marker_ref="###TASK_COMPLETE_${issue_number_ref}###"
    fi
    
    # エラーマーカーを生成
    # shellcheck disable=SC2034  # Used via nameref
    error_marker_ref="###TASK_ERROR_${issue_number_ref}###"
    
    # AIが語順を間違えるケースに対応する代替マーカーをグローバルに設定
    # e.g., ###COMPLETE_TASK_1123### (TASK_COMPLETE の逆)
    # e.g., ###ERROR_TASK_1123### (TASK_ERROR の逆)
    ALT_COMPLETE_MARKER="###COMPLETE_TASK_${issue_number_ref}###"
    ALT_ERROR_MARKER="###ERROR_TASK_${issue_number_ref}###"

    # 中間マーカー（run: ステップ対応）
    PHASE_COMPLETE_MARKER="###PHASE_COMPLETE_${issue_number_ref}###"
}

# ============================================================================
# Error Handling
# ============================================================================

# エラーハンドリング関数
# Usage: handle_error <session_name> <issue_number> <error_message> <auto_attach> <cleanup_args>
handle_error() {
    local session_name="$1"
    local issue_number="$2"
    local error_message="$3"
    local auto_attach="$4"
    local cleanup_args="${5:-}"
    
    log_warn "Session error detected: $session_name (Issue #$issue_number)"
    log_warn "Error: $error_message"
    
    # worktreeパスとブランチ名を取得
    local worktree_path=""
    local branch_name=""
    worktree_path="$(find_worktree_by_issue "$issue_number" 2>/dev/null)" || worktree_path=""
    if [[ -n "$worktree_path" ]]; then
        branch_name="$(get_worktree_branch "$worktree_path" 2>/dev/null)" || branch_name=""
    fi
    
    # ステータスを保存
    save_status "$issue_number" "error" "$session_name" "$error_message" 2>/dev/null || true
    
    # トラッカーに記録
    record_tracker_entry "$issue_number" "error" "${error_message:0:100}" 2>/dev/null || true
    
    # on_error hookを実行（hook未設定時はデフォルト動作）
    run_hook "on_error" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "$error_message" "1" "" 2>/dev/null || true
    
    # auto_attachが有効な場合はTerminalを開く
    if [[ "$auto_attach" == "true" ]] && is_macos; then
        open_terminal_and_attach "$session_name" 2>/dev/null || true
    fi
}

# ============================================================================
# Monitoring Loop
# ============================================================================

# Main monitoring loop - detect markers and handle completion/errors
# Usage: run_watch_loop <session_name> <issue_number> <marker> <error_marker> <interval> <auto_attach> <cleanup_args> <baseline_output> <output_log>
run_watch_loop() {
    local session_name="$1"
    local issue_number="$2"
    local marker="$3"
    local error_marker="$4"
    local interval="$5"
    local auto_attach="$6"
    local cleanup_args="$7"
    local baseline_output="$8"
    local output_log="${9:-}"

    if [[ -n "$output_log" ]]; then
        log_info "Starting marker detection (pipe-pane mode: $output_log)..."
    else
        log_info "Starting marker detection (capture-pane fallback)..."
    fi

    # マーカー検出済みの累積カウント（ベースラインのカウントを初期値として設定）
    local cumulative_complete_count=0
    local cumulative_error_count=0
    cumulative_complete_count=$(count_any_markers_outside_codeblock "$baseline_output" "$marker" "$ALT_COMPLETE_MARKER")
    # shellcheck disable=SC2034  # Used via nameref in _check_pipe_pane_markers
    cumulative_error_count=$(count_any_markers_outside_codeblock "$baseline_output" "$error_marker" "$ALT_ERROR_MARKER")

    # PHASE_COMPLETE マーカーの累積カウント（run: ステップ対応）
    local _cpp_cumulative_phase=0

    # pipe-pane ログのバイトオフセット（差分スキャン用）
    local _pipe_pane_last_offset=0
    if [[ -n "$output_log" && -f "$output_log" ]]; then
        _pipe_pane_last_offset=$(wc -c < "$output_log" 2>/dev/null) || _pipe_pane_last_offset=0
    fi

    # シグナルファイルのパス（ターミナルスクレイピングより信頼性が高い）
    local status_dir
    status_dir="$(get_status_dir)"
    local signal_complete="${status_dir}/signal-complete-${issue_number}"
    local signal_error="${status_dir}/signal-error-${issue_number}"

    # Phase tracking variables
    local _current_phase_index=0
    local _step_groups_data=""
    local _phase_retry_count=0
    local _max_step_retries=10

    local loop_count=0
    local check_result=0
    while true; do
        ((loop_count++)) || true

        if ! mux_session_exists "$session_name"; then
            log_info "Session ended: $session_name"
            break
        fi

        # === Phase 1: シグナルファイルチェック（最優先） ===
        check_result=0
        local signal_result
        signal_result=$(_check_signal_files "$signal_complete" "$signal_error" \
            "$session_name" "$issue_number" "$auto_attach" "$cleanup_args")
        check_result=$?
        
        if [[ $check_result -eq 0 ]]; then
            # Complete signal
            local complete_result=0
            handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" "$WATCHER_SCRIPT_DIR" || complete_result=$?
            if [[ $complete_result -eq 0 ]]; then
                log_info "Cleanup completed successfully (signal file)"
                exit 0
            elif [[ $complete_result -eq 2 ]]; then
                log_warn "PR merge timeout. Continuing to monitor session..."
                sleep "$interval"
                continue
            else
                log_error "Cleanup failed"
                exit 1
            fi
        elif [[ $check_result -eq 1 ]]; then
            # Error signal
            local error_msg="${signal_result#ERROR_SIGNAL:}"
            handle_error "$session_name" "$issue_number" "$error_msg" "$auto_attach" "$cleanup_args"
            log_warn "Error notification sent. Session is still running for manual intervention."
            sleep "$interval"
            continue
        fi
        # check_result == 255: no signal, continue to phase 2

        # === Phase 2: テキストマーカー検出（フォールバック・後方互換） ===
        check_result=0
        local marker_result=""
        if [[ -n "$output_log" && -f "$output_log" ]]; then
            marker_result=$(_check_pipe_pane_markers "$output_log" "$marker" "$error_marker" \
                "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" \
                cumulative_complete_count cumulative_error_count \
                "$ALT_COMPLETE_MARKER" "$ALT_ERROR_MARKER" "$PHASE_COMPLETE_MARKER" \
                _cpp_cumulative_phase _pipe_pane_last_offset)
            check_result=$?

            if [[ $check_result -eq 255 ]]; then
                check_result=0
                # capture-pane fallback: pipe-pane がフラッシュしない場合の補完
                marker_result=$(_check_capture_pane_fallback "$session_name" "$marker" \
                    "$issue_number" "$auto_attach" "$cleanup_args" \
                    "$loop_count" 0 "$cumulative_complete_count" \
                    "$ALT_COMPLETE_MARKER" "$PHASE_COMPLETE_MARKER")
                check_result=$?
            fi
        else
            marker_result=$(_check_capture_pane_markers "$session_name" "$marker" "$error_marker" \
                "$issue_number" "$auto_attach" "$cleanup_args" \
                cumulative_complete_count cumulative_error_count \
                "$ALT_COMPLETE_MARKER" "$ALT_ERROR_MARKER")
            check_result=$?
        fi

        # Process marker detection results
        if [[ $check_result -eq 0 ]]; then
            if [[ "$marker_result" == PHASE_MARKER* ]]; then
                # Phase complete marker detected
                local phase_result=0
                handle_phase_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" \
                    _current_phase_index _step_groups_data _phase_retry_count $_max_step_retries \
                    "$ALT_COMPLETE_MARKER" "$ALT_ERROR_MARKER" "$PHASE_COMPLETE_MARKER" || phase_result=$?

                if [[ $phase_result -eq 0 ]]; then
                    # All phases complete → handle as COMPLETE
                    local complete_result=0
                    handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" "$WATCHER_SCRIPT_DIR" || complete_result=$?
                    if [[ $complete_result -eq 0 ]]; then
                        log_info "Cleanup completed successfully (phase-complete)"
                        exit 0
                    elif [[ $complete_result -eq 2 ]]; then
                        log_warn "PR merge timeout. Continuing to monitor session..."
                        sleep "$interval"
                        continue
                    else
                        log_error "Cleanup failed"
                        exit 1
                    fi
                elif [[ $phase_result -eq 2 ]]; then
                    # non-AI steps failed or next AI group → continue monitoring
                    sleep "$interval"
                    continue
                else
                    # Error
                    exit 1
                fi
            else
                # Complete marker detected
                local complete_result=0
                handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" "$WATCHER_SCRIPT_DIR" || complete_result=$?
                if [[ $complete_result -eq 0 ]]; then
                    log_info "Cleanup completed successfully (pipe-pane)"
                    exit 0
                elif [[ $complete_result -eq 2 ]]; then
                    log_warn "PR merge timeout. Continuing to monitor session..."
                    sleep "$interval"
                    continue
                else
                    log_error "Cleanup failed"
                    exit 1
                fi
            fi
        elif [[ $check_result -eq 1 ]]; then
            # Error marker detected
            local error_msg="${marker_result#ERROR_MARKER:}"
            handle_error "$session_name" "$issue_number" "$error_msg" "$auto_attach" "$cleanup_args"
            log_warn "Error notification sent. Session is still running for manual intervention."
        fi
        # check_result 2=PR merge timeout, 3=capture failed → retry after sleep
        
        sleep "$interval"
    done

    # セッションが予期せず消滅した場合（マーカー/シグナルなしで終了）
    log_warn "Session disappeared without completion/error signal: $session_name"
    save_status "$issue_number" "error" "$session_name" "Session disappeared unexpectedly (no completion marker detected)"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local session_name=""
    local marker=""
    local interval=2
    local cleanup_args=""
    local auto_attach=true

    # Parse command line arguments
    parse_watch_arguments session_name marker interval cleanup_args auto_attach "$@"

    # Setup environment and validate
    local issue_number error_marker
    setup_watch_environment "$session_name" marker error_marker issue_number

    log_info "Watching session: $session_name"
    log_info "Completion marker: $marker"
    log_info "Alt completion marker: $ALT_COMPLETE_MARKER"
    log_info "Error marker: $error_marker"
    log_info "Alt error marker: $ALT_ERROR_MARKER"
    log_info "Check interval: ${interval}s"
    log_info "Auto-attach on error: $auto_attach"

    # 初期ステータスを保存
    save_status "$issue_number" "running" "$session_name"

    # ベースラインキャプチャ
    local baseline_output
    baseline_output=$(capture_baseline "$session_name")

    # 初期マーカーチェック（高速完了タスク対応）
    local init_result=0
    local init_marker_result=""
    init_marker_result=$(check_initial_markers "$session_name" "$issue_number" "$marker" "$error_marker" \
        "$auto_attach" "$cleanup_args" "$baseline_output" "$ALT_COMPLETE_MARKER" "$ALT_ERROR_MARKER" 2>/dev/null) || init_result=$?

    if [[ $init_result -eq 0 ]]; then
        if [[ "$init_marker_result" == "COMPLETE_SIGNAL" ]]; then
            # Complete signal file found
            local complete_result=0
            handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" "$WATCHER_SCRIPT_DIR" || complete_result=$?
            if [[ $complete_result -eq 0 ]]; then
                log_info "Cleanup completed successfully"
                exit 0
            elif [[ $complete_result -eq 2 ]]; then
                log_warn "PR merge timeout at startup. Continuing to monitor..."
            else
                exit 1
            fi
        elif [[ "$init_marker_result" == "COMPLETE_MARKER" ]]; then
            # Complete marker found in baseline
            local complete_result=0
            handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" "$WATCHER_SCRIPT_DIR" || complete_result=$?
            if [[ $complete_result -eq 0 ]]; then
                log_info "Cleanup completed successfully"
                exit 0
            elif [[ $complete_result -eq 2 ]]; then
                log_warn "PR merge timeout at startup. Continuing to monitor..."
            else
                exit 1
            fi
        fi
    elif [[ $init_result -eq 1 ]] && [[ "$init_marker_result" == ERROR_SIGNAL* ]]; then
        # Error signal found
        local error_msg="${init_marker_result#ERROR_SIGNAL:}"
        handle_error "$session_name" "$issue_number" "$error_msg" "$auto_attach" "$cleanup_args"
        log_warn "Error notification sent. Session is still running for manual intervention."
    fi
    # init_result == 1 (no marker): continue to monitoring loop

    # pipe-paneで全出力をファイルに記録（スクロールアウト対策）
    # tmuxの場合のみ使用。Zellijやpipe-pane非対応環境ではcapture-paneにフォールバック
    local output_log=""
    output_log=$(setup_output_logging "$session_name" "$issue_number")

    # output_log のクリーンアップ用trap（pipe-pane停止 + ログファイル削除）
    # shellcheck disable=SC2064
    trap "stop_output_logging '$session_name' '$output_log'; cleanup_output_log '$output_log'" EXIT

    # 監視ループ
    run_watch_loop "$session_name" "$issue_number" "$marker" "$error_marker" "$interval" "$auto_attach" "$cleanup_args" "$baseline_output" "$output_log"
}

# Only run main if script is executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
