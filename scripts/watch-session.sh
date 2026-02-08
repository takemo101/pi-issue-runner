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
                    notify_error "$session_name" "$issue_number" "PR #$pr_number is not merged yet - will retry"
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
    log_info "Error marker: $error_marker"
    log_info "Check interval: ${interval}s"
    log_info "Auto-attach on error: $auto_attach"
    
    # 初期ステータスを保存
    save_status "$issue_number" "running" "$session_name"

    # 初期遅延（プロンプト表示を待つ）
    local initial_delay
    initial_delay="$(get_config watcher_initial_delay)"
    log_info "Waiting for initial prompt display (${initial_delay}s)..."
    sleep "$initial_delay"

    # 初期出力をキャプチャ（ベースライン）
    local baseline_output
    baseline_output=$(get_session_output "$session_name" 1000 2>/dev/null) || baseline_output=""
    
    # 初期化時点でマーカーが既にあるか確認（高速完了タスク対応）
    # Issue #281: 初期化中（10秒待機中）にマーカーが出力された場合の検出
    # Issue #393, #648, #651: コードブロック内のマーカーを誤検出しないよう除外
    local initial_error_count
    initial_error_count=$(count_markers_outside_codeblock "$baseline_output" "$error_marker")
    
    if [[ "$initial_error_count" -gt 0 ]]; then
        log_warn "Error marker already present at startup (outside codeblock)"
        
        # エラーメッセージを抽出（マーカー行の次の行）
        local error_message
        error_message=$(echo "$baseline_output" | grep -A 1 -F "$error_marker" | tail -n 1 | head -c 200) || error_message="Unknown error"
        
        handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach" "$cleanup_args"
        log_warn "Error notification sent. Session is still running for manual intervention."
        # エラーの場合は監視を続行（ユーザーが修正する可能性があるため）
    fi
    
    local initial_complete_count
    initial_complete_count=$(count_markers_outside_codeblock "$baseline_output" "$marker")
    
    if [[ "$initial_complete_count" -gt 0 ]]; then
        log_info "Completion marker already present at startup (outside codeblock)"
        
        handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args"
        local complete_result=$?
        
        if [[ $complete_result -eq 0 ]]; then
            log_info "Cleanup completed successfully"
            exit 0
        elif [[ $complete_result -eq 2 ]]; then
            # PR merge timeout at startup: continue monitoring
            log_warn "PR merge timeout at startup. Will continue monitoring..."
            # Fall through to monitoring loop
        else
            log_error "Cleanup failed"
            exit 1
        fi
    fi
    
    log_info "Starting marker detection..."

    # 監視ループ
    while true; do
        # セッションが存在しなくなったら終了
        if ! session_exists "$session_name"; then
            log_info "Session ended: $session_name"
            break
        fi

        # 最新の出力をキャプチャ（最後の100行）
        local output
        output=$(get_session_output "$session_name" 100 2>/dev/null) || {
            log_warn "Failed to capture pane output"
            sleep "$interval"
            continue
        }

        # エラーマーカー検出（完了マーカーより先にチェック）
        # Issue #393, #648, #651: コードブロック内のマーカーを誤検出しないよう除外
        local error_count_baseline
        local error_count_current
        error_count_baseline=$(count_markers_outside_codeblock "$baseline_output" "$error_marker")
        error_count_current=$(count_markers_outside_codeblock "$output" "$error_marker")
        
        if [[ "$error_count_current" -gt "$error_count_baseline" ]]; then
            log_warn "Error marker detected outside codeblock! (baseline: $error_count_baseline, current: $error_count_current)"
            
            # エラーメッセージを抽出（マーカー行の次の行）
            local error_message
            error_message=$(echo "$output" | grep -A 1 -F "$error_marker" | tail -n 1 | head -c 200) || error_message="Unknown error"
            
            handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach" "$cleanup_args"
            
            log_warn "Error notification sent. Session is still running for manual intervention."
            
            # エラー後もセッションは継続するため、ベースラインを更新して監視を続ける
            baseline_output="$output"
        fi
        
        # 完了マーカー検出
        # Issue #393, #648, #651: コードブロック内のマーカーを誤検出しないよう除外
        local marker_count_baseline
        local marker_count_current
        marker_count_baseline=$(count_markers_outside_codeblock "$baseline_output" "$marker")
        marker_count_current=$(count_markers_outside_codeblock "$output" "$marker")
        
        if [[ "$marker_count_current" -gt "$marker_count_baseline" ]]; then
            log_info "Completion marker detected outside codeblock! (baseline: $marker_count_baseline, current: $marker_count_current)"
            
            handle_complete "$session_name" "$issue_number" "$auto_attach" "$cleanup_args"
            local complete_result=$?
            
            if [[ $complete_result -eq 0 ]]; then
                log_info "Cleanup completed successfully"
                exit 0
            elif [[ $complete_result -eq 2 ]]; then
                # PR merge timeout: continue monitoring
                log_warn "PR merge timeout. Continuing to monitor session..."
                baseline_output="$output"  # Update baseline to prevent re-triggering
                sleep "$interval"
                continue
            else
                log_error "Cleanup failed"
                exit 1
            fi
        fi

        sleep "$interval"
    done
}

# Only run main if script is executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
