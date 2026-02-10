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
source "$WATCHER_SCRIPT_DIR/../lib/config.sh"
source "$WATCHER_SCRIPT_DIR/../lib/log.sh"
source "$WATCHER_SCRIPT_DIR/../lib/status.sh"
source "$WATCHER_SCRIPT_DIR/../lib/tmux.sh"
source "$WATCHER_SCRIPT_DIR/../lib/notify.sh"
source "$WATCHER_SCRIPT_DIR/../lib/worktree.sh"
source "$WATCHER_SCRIPT_DIR/../lib/hooks.sh"
source "$WATCHER_SCRIPT_DIR/../lib/cleanup-orphans.sh"
source "$WATCHER_SCRIPT_DIR/../lib/marker.sh"
source "$WATCHER_SCRIPT_DIR/../lib/tracker.sh"

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
    if ! session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        exit 1
    fi

    # Issue番号を抽出してマーカーを生成
    issue_number_ref=$(extract_issue_number "$session_name")
    
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
}

# Check PR merge status with retry logic
# Usage: check_pr_merge_status <session_name> <branch_name> <issue_number> [max_attempts] [retry_interval]
# Returns: 0 if PR is merged or closed, 1 if still open/not found after all retries, 2 if timed out
check_pr_merge_status() {
    local session_name="$1"
    local branch_name="$2"
    local issue_number="$3"
    local max_attempts="${4:-$(get_config watcher_pr_merge_max_attempts)}"        # Default from config
    local retry_interval="${5:-$(get_config watcher_pr_merge_retry_interval)}"     # Default from config
    
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local pr_number
        local pr_state
        pr_number=$(gh pr list --state all --head "$branch_name" --json number -q '.[0].number' 2>/dev/null) || pr_number=""
        
        if [[ -n "$pr_number" ]]; then
            pr_state=$(gh pr view "$pr_number" --json state -q '.state' 2>/dev/null) || pr_state=""
            
            if [[ "$pr_state" == "MERGED" ]]; then
                log_info "PR #$pr_number is MERGED - workflow completed successfully"
                return 0
            elif [[ "$pr_state" == "CLOSED" ]]; then
                log_info "PR #$pr_number is CLOSED - treating as completion"
                return 0
            elif [[ "$pr_state" == "OPEN" ]]; then
                if [[ $attempt -eq 1 ]]; then
                    log_warn "PR #$pr_number exists but is not merged yet"
                    log_warn "Completion marker detected but PR is still open - waiting for merge..."
                    log_warn "This may indicate the AI output the marker too early"
                    log_warn "PR #$pr_number is not merged yet - will retry"
                fi
                
                if [[ $attempt -lt $max_attempts ]]; then
                    log_info "PR merge check attempt $attempt/$max_attempts - retrying in ${retry_interval}s..."
                    sleep "$retry_interval"
                    attempt=$((attempt + 1))
                    continue
                else
                    log_error "PR #$pr_number is still not merged after $max_attempts attempts"
                    log_error "Timeout waiting for PR merge. Session will continue monitoring."
                    return 2  # Timeout
                fi
            else
                log_info "PR #$pr_number state: $pr_state - treating as completion"
                return 0
            fi
        else
            if [[ $attempt -eq 1 ]]; then
                log_warn "No PR found for Issue #$issue_number"
                log_warn "Completion marker detected but no PR was created - workflow may not have completed correctly"
            fi
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "PR creation check attempt $attempt/$max_attempts - retrying in ${retry_interval}s..."
                sleep "$retry_interval"
                attempt=$((attempt + 1))
                continue
            else
                log_error "No PR created for Issue #$issue_number after $max_attempts attempts"
                log_error "Timeout waiting for PR creation. Session will continue monitoring."
                notify_error "$session_name" "$issue_number" "No PR created for Issue #$issue_number after timeout"
                return 2  # Timeout
            fi
        fi
    done
    
    # Should not reach here, but return error code as fallback
    return 1
}

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

# Resolve worktree information for an issue
# Usage: _resolve_worktree_info <issue_number> <worktree_path_var> <branch_name_var>
# Sets: worktree_path_var and branch_name_var via nameref
_resolve_worktree_info() {
    local issue_number="$1"
    local -n worktree_path_ref="$2"
    local -n branch_name_ref="$3"
    
    worktree_path_ref=""
    branch_name_ref=""
    
    worktree_path_ref="$(find_worktree_by_issue "$issue_number" 2>/dev/null)" || worktree_path_ref=""
    if [[ -n "$worktree_path_ref" ]]; then
        # shellcheck disable=SC2034  # Used via nameref
        branch_name_ref="$(get_worktree_branch "$worktree_path_ref" 2>/dev/null)" || branch_name_ref=""
    fi
}

# Save completion status and handle plan file deletion
# Usage: _complete_status_and_plans <issue_number> <session_name>
_complete_status_and_plans() {
    local issue_number="$1"
    local session_name="$2"
    
    # ステータスを保存
    save_status "$issue_number" "complete" "$session_name" "" 2>/dev/null || true
    
    # 計画書を削除（ホスト環境で実行するため確実に反映される）
    local plans_dir
    plans_dir="$(get_config plans_dir)"
    local plan_file="${plans_dir}/issue-${issue_number}-plan.md"
    if [[ -f "$plan_file" ]]; then
        log_info "Deleting plan file: $plan_file"
        rm -f "$plan_file"
        
        # git でコミット（失敗しても継続）
        if git rev-parse --git-dir &>/dev/null; then
            git add "$plan_file" 2>/dev/null || true
            git commit -m "chore: remove plan for issue #${issue_number}" 2>/dev/null || true
            # NOTE: Do NOT auto-push - let the PR workflow handle that
        fi
    else
        log_debug "No plan file found at: $plan_file"
    fi
}

# Run completion hooks
# Usage: _run_completion_hooks <issue_number> <session_name> <branch_name> <worktree_path>
_run_completion_hooks() {
    local issue_number="$1"
    local session_name="$2"
    local branch_name="$3"
    local worktree_path="$4"
    
    # トラッカーに記録
    record_tracker_entry "$issue_number" "success" 2>/dev/null || true
    
    # on_success hookを実行（hook未設定時はデフォルト動作）
    run_hook "on_success" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "" "0" "" 2>/dev/null || true
}

# Run cleanup with retry logic
# Usage: _run_cleanup_with_retry <session_name> <cleanup_args>
# Returns: 0 on success, 1 on failure
_run_cleanup_with_retry() {
    local session_name="$1"
    local cleanup_args="${2:-}"
    
    log_info "Running cleanup..."
    
    # セッションが完全に終了し、プロセスが解放されるまで待機
    # Issue #585対策: worktree削除前に確実にセッションを終了させる
    local cleanup_delay
    cleanup_delay="$(get_config watcher_cleanup_delay)"
    log_info "Waiting for session termination (${cleanup_delay}s)..."
    sleep "$cleanup_delay"
    
    # cleanup実行（リトライ付き）
    local cleanup_success=false
    local cleanup_attempt=1
    local max_cleanup_attempts=2
    
    while [[ $cleanup_attempt -le $max_cleanup_attempts ]]; do
        log_info "Cleanup attempt $cleanup_attempt/$max_cleanup_attempts..."
        
        # 2回目以降は --force を追加（未コミットファイルがあっても削除）
        local force_flag=""
        if [[ $cleanup_attempt -gt 1 ]]; then
            log_info "Adding --force flag for retry attempt"
            force_flag="--force"
        fi
        
        # shellcheck disable=SC2086
        if "$WATCHER_SCRIPT_DIR/cleanup.sh" "$session_name" $cleanup_args $force_flag; then
            cleanup_success=true
            break
        else
            log_warn "Cleanup attempt $cleanup_attempt failed"
            if [[ $cleanup_attempt -lt $max_cleanup_attempts ]]; then
                local cleanup_retry_interval
                cleanup_retry_interval="$(get_config watcher_cleanup_retry_interval)"
                log_info "Retrying in ${cleanup_retry_interval} seconds..."
                sleep "$cleanup_retry_interval"
            fi
        fi
        cleanup_attempt=$((cleanup_attempt + 1))
    done
    
    if [[ "$cleanup_success" == "false" ]]; then
        log_error "Cleanup failed after $max_cleanup_attempts attempts"
        
        # orphaned worktreeとしてマーク
        log_warn "This worktree may need manual cleanup. You can run:"
        log_warn "  ./scripts/cleanup.sh --orphan-worktrees --force"
        return 1
    fi
    
    return 0
}

# Post-cleanup maintenance: orphan detection and plan rotation
# Usage: _post_cleanup_maintenance
_post_cleanup_maintenance() {
    # orphaned worktreeの検出と修復
    log_info "Checking for any orphaned worktrees with 'complete' status..."
    local orphaned_count
    orphaned_count=$(count_complete_with_existing_worktrees)
    
    if [[ "$orphaned_count" -gt 0 ]]; then
        log_info "Found $orphaned_count orphaned worktree(s) with 'complete' status. Cleaning up..."
        # shellcheck source=../lib/cleanup-orphans.sh
        cleanup_complete_with_worktrees "false" "false" || {
            log_warn "Some orphaned worktrees could not be cleaned up automatically"
        }
    else
        log_debug "No orphaned worktrees found"
    fi
    
    # 古い計画書をローテーション
    log_info "Rotating old plans..."
    "$WATCHER_SCRIPT_DIR/cleanup.sh" --rotate-plans 2>/dev/null || {
        log_warn "Plan rotation failed (non-critical)"
    }
}

# 完了ハンドリング関数
# Usage: handle_complete <session_name> <issue_number> <auto_attach> <cleanup_args>
# Returns: 0 on success, 1 on cleanup failure, 2 on PR merge timeout (continue monitoring)
handle_complete() {
    local session_name="$1"
    local issue_number="$2"
    local auto_attach="$3"
    local cleanup_args="${4:-}"
    
    log_info "Session completed: $session_name (Issue #$issue_number)"
    
    # 1. worktreeパスとブランチ名を取得
    local worktree_path branch_name
    _resolve_worktree_info "$issue_number" worktree_path branch_name
    
    # 2. ステータスと計画書の処理
    _complete_status_and_plans "$issue_number" "$session_name"
    
    # 3. Hook実行
    _run_completion_hooks "$issue_number" "$session_name" "$branch_name" "$worktree_path"
    
    # 4. PR確認（リトライロジック付き）
    local pr_check_result
    check_pr_merge_status "$session_name" "$branch_name" "$issue_number"
    pr_check_result=$?
    
    if [[ $pr_check_result -eq 2 ]]; then
        # Timeout: PR が見つからないまたはマージされないままタイムアウト
        log_warn "PR merge timeout. Will continue monitoring for manual completion."
        return 2
    elif [[ $pr_check_result -ne 0 ]]; then
        # その他のエラー
        log_error "PR check failed with unexpected error"
        return 1
    fi
    
    # 5. Cleanup実行
    if ! _run_cleanup_with_retry "$session_name" "$cleanup_args"; then
        return 1
    fi
    
    # 6. 事後処理
    _post_cleanup_maintenance
    
    log_info "Cleanup completed successfully"
    
    return 0
}

# Setup pipe-pane output logging for reliable marker detection
# Usage: setup_output_logging <session_name> <issue_number>
# Output: path to log file (empty if pipe-pane is not available)
setup_output_logging() {
    local session_name="$1"
    local issue_number="$2"
    
    # tmuxのpipe-paneが使えるか確認
    local mux_type
    mux_type="$(get_multiplexer_type 2>/dev/null)" || mux_type="tmux"
    
    if [[ "$mux_type" != "tmux" ]]; then
        log_info "pipe-pane not available for $mux_type, using capture-pane fallback"
        echo ""
        return
    fi
    
    # ログディレクトリ
    local status_dir
    status_dir="$(get_status_dir)"
    local log_file="${status_dir}/output-${issue_number}.log"
    
    # 既存のpipe-paneを閉じてから新規設定
    tmux pipe-pane -t "$session_name" "" 2>/dev/null || true
    
    # pipe-paneでセッション出力をファイルに追記
    # Note: ベースラインキャプチャ後に開始するため、初期出力は含まれない。
    #       初期マーカーチェックはベースラインキャプチャで対応済み。
    # ANSIエスケープシーケンスとCR(\r)を除去してからファイルに書き込む。
    # pipe-paneは生のターミナル出力（カラーコード等）を含むため、
    # 除去しないとマーカーの完全一致検出に失敗する（Issue #1210）。
    # perlを使用: macOS の sed は不正バイトシーケンスで "illegal byte sequence" エラーになる。
    # ターミナル出力にはUTF-8として不正なバイトが含まれることがあり、
    # sed (UTF-8モード) では処理できない。perlはバイナリセーフ。
    if tmux pipe-pane -t "$session_name" "perl -pe 's/\e\][^\a\e]*(?:\a|\e\\\\)//g; s/\e\[[0-9;?]*[a-zA-Z]//g; s/\r//g' >> '${log_file}'" 2>/dev/null; then
        log_info "Output logging started: $log_file"
        echo "$log_file"
    else
        log_warn "Failed to start pipe-pane, using capture-pane fallback"
        echo ""
    fi
}

# Stop pipe-pane output logging
# Usage: stop_output_logging <session_name> <output_log>
stop_output_logging() {
    local session_name="$1"
    local output_log="$2"
    
    if [[ -n "$output_log" ]]; then
        tmux pipe-pane -t "$session_name" "" 2>/dev/null || true
        log_debug "Output logging stopped"
    fi
}

# Clean up output log file
# Usage: cleanup_output_log <output_log>
cleanup_output_log() {
    local output_log="$1"
    
    if [[ -n "$output_log" && -f "$output_log" ]]; then
        rm -f "$output_log"
        log_debug "Output log cleaned up: $output_log"
    fi
}

# Capture baseline output and wait for initial prompt display
# Usage: capture_baseline <session_name>
# Output: baseline output text via stdout
capture_baseline() {
    local session_name="$1"

    # 初期遅延（プロンプト表示を待つ）
    local initial_delay
    initial_delay="$(get_config watcher_initial_delay)"
    log_info "Waiting for initial prompt display (${initial_delay}s)..."
    sleep "$initial_delay"

    # 初期出力をキャプチャ（ベースライン）
    get_session_output "$session_name" 1000 2>/dev/null || echo ""
}

# Check for markers already present at startup (fast-completing tasks)
# Usage: check_initial_markers <session_name> <issue_number> <marker> <error_marker> <auto_attach> <cleanup_args> <baseline_output>
# Returns: 0 if completion handled, 1 if should continue monitoring, 2 if cleanup failed
check_initial_markers() {
    local session_name="$1"
    local issue_number="$2"
    local marker="$3"
    local error_marker="$4"
    local auto_attach="$5"
    local cleanup_args="$6"
    local baseline_output="$7"

    # Issue #281: 初期化中（10秒待機中）にマーカーが出力された場合の検出
    # Issue #393, #648, #651: コードブロック内のマーカーを誤検出しないよう除外
    # 代替マーカーも検出（AIが語順を間違えるケースに対応）
    #
    # Note: ベースライン（capture-pane）ではエラーマーカーをチェックしない。
    # capture-pane出力にはテンプレート全文（agents/merge.md等のコード例）が含まれ、
    # ターミナル折り返しによりコードブロック判定が崩れてエラーマーカーを誤検出する。
    # エラー検出はシグナルファイル（Phase 1）またはpipe-pane（Phase 2）に任せる。
    #
    # シグナルファイルによる初期エラーチェック
    local status_dir
    status_dir="$(get_status_dir 2>/dev/null)" || true
    if [[ -n "$status_dir" && -f "${status_dir}/signal-error-${issue_number}" ]]; then
        log_warn "Error signal file already present at startup"
        local error_message
        error_message=$(cat "${status_dir}/signal-error-${issue_number}" 2>/dev/null | head -c 200) || error_message="Unknown error"
        rm -f "${status_dir}/signal-error-${issue_number}"
        handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach" "$cleanup_args"
        log_warn "Error notification sent. Session is still running for manual intervention."
    fi

    # シグナルファイルによる初期完了チェック
    if [[ -n "$status_dir" && -f "${status_dir}/signal-complete-${issue_number}" ]]; then
        log_info "Completion signal file already present at startup"
        rm -f "${status_dir}/signal-complete-${issue_number}"
        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args"
        local sig_result=$?
        if [[ $sig_result -eq 0 ]]; then
            return 0
        elif [[ $sig_result -eq 2 ]]; then
            log_warn "PR merge timeout at startup. Continuing to monitor..."
        else
            return 2
        fi
    fi

    # capture-pane による完了マーカーチェック（エラーマーカーはチェックしない）
    local initial_complete_count
    initial_complete_count=$(count_any_markers_outside_codeblock "$baseline_output" "$marker" "$ALT_COMPLETE_MARKER")

    if [[ "$initial_complete_count" -gt 0 ]]; then
        log_info "Completion marker already present at startup (outside codeblock)"

        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args"
        local complete_result=$?

        if [[ $complete_result -eq 0 ]]; then
            return 0  # Completion handled successfully
        elif [[ $complete_result -eq 2 ]]; then
            # PR merge timeout at startup: continue monitoring
            log_warn "PR merge timeout at startup. Will continue monitoring..."
            return 1  # Continue to monitoring loop
        else
            return 2  # Cleanup failed
        fi
    fi

    return 1  # No initial completion marker, continue to monitoring loop
}

# Backward-compatible wrappers delegating to lib/marker.sh shared functions
# These private aliases are kept for internal use within this file.

# Extract error message from file or text (line after error marker)
# Usage: _extract_error_message <source> <error_marker> [alt_error_marker] [is_file]
_extract_error_message() {
    local source="$1"
    local error_marker="$2"
    local alt_error_marker="${3:-}"
    local is_file="${4:-false}"

    local msg=""
    if [[ "$is_file" == "true" ]]; then
        msg=$(strip_ansi < "$source" | grep -A 1 -F "$error_marker" 2>/dev/null | tail -n 1 | head -c 200) || msg=""
        if [[ -z "$msg" && -n "$alt_error_marker" ]]; then
            msg=$(strip_ansi < "$source" | grep -A 1 -F "$alt_error_marker" 2>/dev/null | tail -n 1 | head -c 200) || msg=""
        fi
    else
        msg=$(echo "$source" | strip_ansi | grep -A 1 -F "$error_marker" 2>/dev/null | tail -n 1 | head -c 200) || msg=""
        if [[ -z "$msg" && -n "$alt_error_marker" ]]; then
            msg=$(echo "$source" | strip_ansi | grep -A 1 -F "$alt_error_marker" 2>/dev/null | tail -n 1 | head -c 200) || msg=""
        fi
    fi
    echo "${msg:-Unknown error}"
}

# Handle completion result from handle_complete
# Usage: _handle_complete_result <result_code> <source_label> <interval>
# Returns: 0=exit success, 1=exit failure, 2=continue monitoring
_handle_complete_result() {
    local result_code="$1"
    local source_label="$2"
    local interval="${3:-2}"

    if [[ $result_code -eq 0 ]]; then
        log_info "Cleanup completed successfully ($source_label)"
        exit 0
    elif [[ $result_code -eq 2 ]]; then
        log_warn "PR merge timeout. Continuing to monitor session..."
        return 2
    else
        log_error "Cleanup failed"
        exit 1
    fi
}

# Phase 1: Check signal files (highest priority, most reliable)
# AI creates files directly, so no ANSI/codeblock/scrollout issues
# Usage: _check_signal_files <signal_complete> <signal_error> <session_name> <issue_number> <auto_attach> <cleanup_args>
# Returns: 0=complete handled (exit 0), 1=error handled, 2=PR merge timeout, 255=no signal
_check_signal_files() {
    local signal_complete="$1"
    local signal_error="$2"
    local session_name="$3"
    local issue_number="$4"
    local auto_attach="$5"
    local cleanup_args="$6"

    if [[ -f "$signal_complete" ]]; then
        log_info "Completion signal file detected: $signal_complete"
        rm -f "$signal_complete"

        local sig_result=0
        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" || sig_result=$?
        _handle_complete_result "$sig_result" "signal file"
        return $?  # 2=continue monitoring
    fi

    if [[ -f "$signal_error" ]]; then
        log_warn "Error signal file detected: $signal_error"
        local sig_error_message
        sig_error_message=$(cat "$signal_error" 2>/dev/null | head -c 200) || sig_error_message="Unknown error"
        rm -f "$signal_error"

        handle_error "$session_name" "$issue_number" "$sig_error_message" "$auto_attach" "$cleanup_args"
        log_warn "Error notification sent. Session is still running for manual intervention."
        return 1
    fi

    return 255  # No signal found
}

# Verify marker is outside codeblock for both primary and alt markers
# Usage: _verify_real_marker <source> <primary_marker> <alt_marker> <is_file>
# Returns: 0=real marker found, 1=only in codeblock
_verify_real_marker() {
    local source="$1"
    local primary_marker="$2"
    local alt_marker="$3"
    local is_file="${4:-false}"

    if verify_marker_outside_codeblock "$source" "$primary_marker" "$is_file"; then
        return 0
    fi
    if [[ -n "$alt_marker" ]] && verify_marker_outside_codeblock "$source" "$alt_marker" "$is_file"; then
        return 0
    fi
    return 1
}

# Phase 2a: Check pipe-pane markers (fast grep-based detection)
# Usage: _check_pipe_pane_markers <output_log> <marker> <error_marker> <session_name> <issue_number> <auto_attach> <cleanup_args> <cumulative_complete_var> <cumulative_error_var>
# Returns: 0=complete (exit 0), 1=error handled, 2=PR merge timeout, 255=no new marker
_check_pipe_pane_markers() {
    local output_log="$1"
    local marker="$2"
    local error_marker="$3"
    local session_name="$4"
    local issue_number="$5"
    local auto_attach="$6"
    local cleanup_args="$7"
    local -n _cpp_cumulative_complete="$8"
    local -n _cpp_cumulative_error="$9"

    # Step 1: grep -cF で高速カウント（ファイルをメモリに読み込まない）
    local file_error_count file_complete_count
    file_error_count=$(grep_marker_count_in_file "$output_log" "$error_marker" "$ALT_ERROR_MARKER")
    file_complete_count=$(grep_marker_count_in_file "$output_log" "$marker" "$ALT_COMPLETE_MARKER")

    # Step 2: 新規エラーマーカーが見つかった場合のみコードブロック検証
    if [[ "$file_error_count" -gt 0 ]] && [[ "$file_error_count" -gt "$_cpp_cumulative_error" ]]; then
        if _verify_real_marker "$output_log" "$error_marker" "$ALT_ERROR_MARKER" "true"; then
            log_warn "Error marker detected! (count: $file_error_count)"
            _cpp_cumulative_error="$file_error_count"

            local error_message
            error_message=$(_extract_error_message "$output_log" "$error_marker" "$ALT_ERROR_MARKER" "true")
            handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach" "$cleanup_args"
            log_warn "Error notification sent. Session is still running for manual intervention."
        else
            log_debug "Error marker found in code block, ignoring"
        fi
    fi

    # Step 3: 新規完了マーカーが見つかった場合のみコードブロック検証
    if [[ "$file_complete_count" -gt 0 ]] && [[ "$file_complete_count" -gt "$_cpp_cumulative_complete" ]]; then
        if _verify_real_marker "$output_log" "$marker" "$ALT_COMPLETE_MARKER" "true"; then
            log_info "Completion marker detected! (count: $file_complete_count)"
            _cpp_cumulative_complete="$file_complete_count"

            local complete_result=0
            handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" || complete_result=$?
            _handle_complete_result "$complete_result" "pipe-pane"
            return $?
        else
            log_debug "Complete marker found in code block, ignoring"
        fi
    fi

    return 255  # No new marker
}

# Phase 2b: Periodic capture-pane fallback for pipe-pane mode
# Used to catch markers already output before watcher restart (every 15 loops)
# Note: Only checks completion markers, not error markers.
#   capture-pane output contains template text (agents/merge.md etc.), and
#   TASK_ERROR patterns in code examples get misdetected due to terminal wrapping.
# Usage: _check_capture_pane_fallback <session_name> <marker> <issue_number> <auto_attach> <cleanup_args> <loop_count> <marker_count_current> <cumulative_complete_count>
# Returns: 0=complete (exit 0), 2=PR merge timeout, 255=no marker
_check_capture_pane_fallback() {
    local session_name="$1"
    local marker="$2"
    local issue_number="$3"
    local auto_attach="$4"
    local cleanup_args="$5"
    local loop_count="$6"
    local marker_count_current="$7"
    local cumulative_complete_count="$8"

    # Only check every 15 loops (~30 seconds) and only when no markers found yet
    if [[ "$marker_count_current" -ne 0 ]] || [[ "$cumulative_complete_count" -ne 0 ]] \
       || [[ $((loop_count % 15)) -ne 0 ]]; then
        return 255
    fi

    local capture_fallback_output
    capture_fallback_output=$(get_session_output "$session_name" 500 2>/dev/null) || capture_fallback_output=""
    if [[ -z "$capture_fallback_output" ]]; then
        return 255
    fi

    local capture_complete_count
    capture_complete_count=$(count_any_markers_outside_codeblock "$capture_fallback_output" "$marker" "$ALT_COMPLETE_MARKER")
    if [[ "$capture_complete_count" -gt 0 ]]; then
        log_info "Completion marker found via capture-pane fallback"
        local fb_result=0
        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" || fb_result=$?
        _handle_complete_result "$fb_result" "capture-pane fallback"
        return $?
    fi

    return 255
}

# Phase 2c: Check capture-pane markers (when pipe-pane is not available)
# Usage: _check_capture_pane_markers <session_name> <marker> <error_marker> <issue_number> <auto_attach> <cleanup_args> <cumulative_complete_var> <cumulative_error_var>
# Returns: 0=complete (exit 0), 1=error handled, 2=PR merge timeout, 255=no marker, 3=capture failed
_check_capture_pane_markers() {
    local session_name="$1"
    local marker="$2"
    local error_marker="$3"
    local issue_number="$4"
    local auto_attach="$5"
    local cleanup_args="$6"
    local -n _ccp_cumulative_complete="$7"
    local -n _ccp_cumulative_error="$8"

    local output
    output=$(get_session_output "$session_name" 1000 2>/dev/null) || {
        log_warn "Failed to capture pane output"
        return 3
    }

    local error_count_current
    error_count_current=$(count_any_markers_outside_codeblock "$output" "$error_marker" "$ALT_ERROR_MARKER")
    if [[ "$error_count_current" -gt "$_ccp_cumulative_error" ]]; then
        log_warn "Error marker detected! (cumulative: $_ccp_cumulative_error, current: $error_count_current)"
        _ccp_cumulative_error="$error_count_current"

        local error_message
        error_message=$(_extract_error_message "$output" "$error_marker" "$ALT_ERROR_MARKER")
        handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach" "$cleanup_args"
        log_warn "Error notification sent. Session is still running for manual intervention."
    fi

    local marker_count_current
    marker_count_current=$(count_any_markers_outside_codeblock "$output" "$marker" "$ALT_COMPLETE_MARKER")
    if [[ "$marker_count_current" -gt "$_ccp_cumulative_complete" ]]; then
        log_info "Completion marker detected! (cumulative: $_ccp_cumulative_complete, current: $marker_count_current)"
        _ccp_cumulative_complete="$marker_count_current"

        local complete_result=0
        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" || complete_result=$?
        _handle_complete_result "$complete_result" "capture-pane"
        return $?
    fi

    return 255
}

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
    # Used via nameref in _check_pipe_pane_markers / _check_capture_pane_markers
    local cumulative_complete_count=0
    local cumulative_error_count=0
    cumulative_complete_count=$(count_any_markers_outside_codeblock "$baseline_output" "$marker" "$ALT_COMPLETE_MARKER")
    # shellcheck disable=SC2034
    cumulative_error_count=$(count_any_markers_outside_codeblock "$baseline_output" "$error_marker" "$ALT_ERROR_MARKER")

    # シグナルファイルのパス（ターミナルスクレイピングより信頼性が高い）
    local status_dir
    status_dir="$(get_status_dir)"
    local signal_complete="${status_dir}/signal-complete-${issue_number}"
    local signal_error="${status_dir}/signal-error-${issue_number}"

    local loop_count=0
    local check_result=0
    while true; do
        ((loop_count++)) || true

        if ! session_exists "$session_name"; then
            log_info "Session ended: $session_name"
            break
        fi

        # === Phase 1: シグナルファイルチェック（最優先） ===
        check_result=0
        _check_signal_files "$signal_complete" "$signal_error" \
            "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" || check_result=$?
        if [[ $check_result -eq 2 ]]; then
            sleep "$interval"
            continue
        fi

        # === Phase 2: テキストマーカー検出（フォールバック・後方互換） ===
        check_result=0
        if [[ -n "$output_log" && -f "$output_log" ]]; then
            local pipe_complete_count
            pipe_complete_count=$(grep_marker_count_in_file "$output_log" "$marker" "$ALT_COMPLETE_MARKER")

            _check_pipe_pane_markers "$output_log" "$marker" "$error_marker" \
                "$session_name" "$issue_number" "$auto_attach" "$cleanup_args" \
                cumulative_complete_count cumulative_error_count || check_result=$?

            if [[ $check_result -eq 255 ]]; then
                check_result=0
                _check_capture_pane_fallback "$session_name" "$marker" \
                    "$issue_number" "$auto_attach" "$cleanup_args" \
                    "$loop_count" "$pipe_complete_count" "$cumulative_complete_count" || check_result=$?
            fi
        else
            _check_capture_pane_markers "$session_name" "$marker" "$error_marker" \
                "$issue_number" "$auto_attach" "$cleanup_args" \
                cumulative_complete_count cumulative_error_count || check_result=$?
        fi
        # check_result 2=PR merge timeout, 3=capture failed → retry after sleep
        if [[ $check_result -eq 2 ]] || [[ $check_result -eq 3 ]]; then
            sleep "$interval"
            continue
        fi

        sleep "$interval"
    done

    # セッションが予期せず消滅した場合（マーカー/シグナルなしで終了）
    log_warn "Session disappeared without completion/error signal: $session_name"
    save_status "$issue_number" "error" "$session_name" "Session disappeared unexpectedly (no completion marker detected)"
}

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
    # Note: || true で set -e による即死を防止（return 1 = 監視続行）
    local init_result=0
    check_initial_markers "$session_name" "$issue_number" "$marker" "$error_marker" "$auto_attach" "$cleanup_args" "$baseline_output" || init_result=$?

    if [[ $init_result -eq 0 ]]; then
        log_info "Cleanup completed successfully"
        exit 0
    elif [[ $init_result -eq 2 ]]; then
        log_error "Cleanup failed"
        exit 1
    fi
    # init_result == 1: continue to monitoring loop

    # pipe-paneで全出力をファイルに記録（スクロールアウト対策）
    # tmuxの場合のみ使用。Zellijやpipe-pane非対応環境ではcapture-paneにフォールバック
    local output_log=""
    output_log=$(setup_output_logging "$session_name" "$issue_number")

    # output_log のクリーンアップ用trap（pipe-pane停止 + ログファイル削除）
    # main() に配置することで output_log のスコープが明確になり、
    # run_watch_loop 内での早期終了時も確実にクリーンアップされる
    # shellcheck disable=SC2064
    trap "stop_output_logging '$session_name' '$output_log'; cleanup_output_log '$output_log'" EXIT

    # 監視ループ
    run_watch_loop "$session_name" "$issue_number" "$marker" "$error_marker" "$interval" "$auto_attach" "$cleanup_args" "$baseline_output" "$output_log"
}

# Only run main if script is executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
