#!/usr/bin/env bash
# ============================================================================
# sweep.sh - Check all sessions for COMPLETE markers and run cleanup
#
# Scans all active pi-issue-runner sessions for completion markers and
# executes cleanup.sh for sessions that have completed but haven't been
# cleaned up (e.g., due to watcher process crash or timing issues).
#
# Usage: ./scripts/sweep.sh [options]
#
# Options:
#   --dry-run           Show target sessions without executing cleanup
#   --force             Skip PR merge confirmation during cleanup
#   --check-errors      Also check for ERROR markers (default: COMPLETE only)
#   -v, --verbose       Show detailed output
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/sweep.sh --dry-run
#   ./scripts/sweep.sh --force
#   ./scripts/sweep.sh --check-errors
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/marker.sh"
source "$SCRIPT_DIR/../lib/status.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --dry-run           対象セッションの表示のみ（実行しない）
    --force             cleanup時にPRマージ確認をスキップ
    --check-errors      ERRORマーカーもチェック（デフォルトはCOMPLETEのみ）
    -v, --verbose       詳細ログ出力
    -h, --help          このヘルプを表示

Description:
    全てのアクティブなpi-issue-runnerセッションをスキャンし、
    COMPLETEマーカーが出力されているセッションに対して
    cleanup.shを実行します。
    
    watch-session.shがクラッシュしたりタイミング問題で
    クリーンアップが実行されなかったセッションの検出と
    クリーンアップに使用します。

Examples:
    $(basename "$0") --dry-run
    $(basename "$0") --force
    $(basename "$0") --check-errors
EOF
}

# Parse command line arguments
parse_sweep_arguments() {
    local -n _dry_run_ref=$1
    local -n _force_ref=$2
    local -n _check_errors_ref=$3
    shift 3
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                _dry_run_ref=true
                shift
                ;;
            --force)
                _force_ref=true
                shift
                ;;
            --check-errors)
                _check_errors_ref=true
                shift
                ;;
            -v|--verbose)
                enable_verbose
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
    done
}

# Check session for markers
# Usage: check_session_markers <session_name> <issue_number> <check_errors>
# Returns: "complete", "error", or ""
check_session_markers() {
    local session_name="$1"
    local issue_number="$2"
    local check_errors="$3"
    
    # セッション出力を取得（最後の100行）
    local output
    if ! output=$(mux_get_session_output "$session_name" 100 2>/dev/null); then
        log_warn "Failed to get output for session: $session_name"
        echo ""
        return
    fi
    
    # COMPLETEマーカーをチェック
    local complete_marker="###TASK_COMPLETE_${issue_number}###"
    local complete_count
    complete_count=$(count_markers_outside_codeblock "$output" "$complete_marker")
    
    if [[ "$complete_count" -gt 0 ]]; then
        echo "complete"
        return
    fi
    
    # ERRORマーカーをチェック（オプション）
    if [[ "$check_errors" == "true" ]]; then
        local error_marker="###TASK_ERROR_${issue_number}###"
        local error_count
        error_count=$(count_markers_outside_codeblock "$output" "$error_marker")
        
        if [[ "$error_count" -gt 0 ]]; then
            echo "error"
            return
        fi
    fi
    
    echo ""
}

# Execute cleanup for a session
# Usage: execute_cleanup <session_name> <issue_number> <force>
# Returns: 0 on success, 1 on failure, 2 on lock conflict (skip)
execute_cleanup() {
    local session_name="$1"
    local issue_number="$2"
    local force="$3"
    
    # クリーンアップロックをチェック（Issue #1077対策）
    if is_cleanup_locked "$issue_number"; then
        log_info "⏭️  Skipping cleanup for Issue #$issue_number (lock held by another process)"
        return 2  # スキップ（ロック競合）
    fi
    
    log_info "Executing cleanup for session: $session_name (Issue #$issue_number)"
    
    # cleanup.shを実行
    local cleanup_args=""
    if [[ "$force" == "true" ]]; then
        cleanup_args="--force"
    fi
    
    # shellcheck disable=SC2086
    if "$SCRIPT_DIR/cleanup.sh" "$session_name" $cleanup_args; then
        log_info "✅ Cleanup completed: $session_name"
        return 0
    else
        log_error "❌ Cleanup failed: $session_name"
        return 1
    fi
}

main() {
    local dry_run=false
    local force=false
    local check_errors=false
    
    # Parse command line arguments
    parse_sweep_arguments dry_run force check_errors "$@"
    
    require_config_file "pi-sweep" || exit 1
    load_config
    
    log_info "=== Session Sweep ==="
    log_info "Mode: $(if [[ "$dry_run" == "true" ]]; then echo "DRY RUN"; else echo "EXECUTE"; fi)"
    log_info "Check errors: $check_errors"
    log_info ""
    
    # セッション一覧を取得
    local sessions
    sessions="$(mux_list_sessions)"
    
    if [[ -z "$sessions" ]]; then
        log_info "No active sessions found."
        exit 0
    fi
    
    # カウンター
    local total_sessions=0
    local complete_sessions=0
    local error_sessions=0
    local cleanup_success=0
    local cleanup_failed=0
    local cleanup_skipped=0
    
    # 各セッションをチェック
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        total_sessions=$((total_sessions + 1))
        
        # Issue番号を抽出
        local issue_num
        issue_num=$(mux_extract_issue_number "$session" 2>/dev/null) || {
            log_debug "Could not extract issue number from: $session (skipping)"
            continue
        }
        
        # マーカーをチェック
        local marker_type
        marker_type=$(check_session_markers "$session" "$issue_num" "$check_errors")
        
        if [[ -z "$marker_type" ]]; then
            log_debug "No markers found: $session"
            continue
        fi
        
        # マーカー発見
        if [[ "$marker_type" == "complete" ]]; then
            complete_sessions=$((complete_sessions + 1))
            log_info "✓ COMPLETE marker detected: $session (Issue #$issue_num)"
            
            if [[ "$dry_run" == "true" ]]; then
                log_info "  [DRY RUN] Would run: cleanup.sh $session $(if [[ "$force" == "true" ]]; then echo "--force"; fi)"
            else
                # クリーンアップ実行
                execute_cleanup "$session" "$issue_num" "$force"
                local cleanup_result=$?
                
                if [[ $cleanup_result -eq 0 ]]; then
                    cleanup_success=$((cleanup_success + 1))
                elif [[ $cleanup_result -eq 2 ]]; then
                    cleanup_skipped=$((cleanup_skipped + 1))
                else
                    cleanup_failed=$((cleanup_failed + 1))
                fi
            fi
        elif [[ "$marker_type" == "error" ]]; then
            error_sessions=$((error_sessions + 1))
            log_warn "✗ ERROR marker detected: $session (Issue #$issue_num)"
            log_warn "  Manual intervention required. Session not cleaned up."
        fi
    done <<< "$sessions"
    
    # サマリー表示
    echo ""
    log_info "=== Summary ==="
    log_info "Total sessions scanned: $total_sessions"
    log_info "Sessions with COMPLETE marker: $complete_sessions"
    if [[ "$check_errors" == "true" ]]; then
        log_info "Sessions with ERROR marker: $error_sessions"
    fi
    
    if [[ "$dry_run" == "false" ]]; then
        log_info "Cleanup succeeded: $cleanup_success"
        if [[ "$cleanup_skipped" -gt 0 ]]; then
            log_info "Cleanup skipped (locked by another process): $cleanup_skipped"
        fi
        if [[ "$cleanup_failed" -gt 0 ]]; then
            log_error "Cleanup failed: $cleanup_failed"
        fi
    fi
    
    # 終了コード
    if [[ "$cleanup_failed" -gt 0 ]]; then
        exit 1
    fi
}

# Only run main if script is executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
