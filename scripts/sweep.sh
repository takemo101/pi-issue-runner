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
source "$SCRIPT_DIR/../lib/tmux.sh"
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

# Check session for markers using pipe-pane log file or capture-pane fallback
# Usage: check_session_markers <session_name> <issue_number> <check_errors>
# Returns: "complete", "error", or ""
check_session_markers() {
    local session_name="$1"
    local issue_number="$2"
    local check_errors="$3"
    
    local output=""
    
    # 0. シグナルファイルを最優先でチェック（最も信頼性が高い）
    local status_dir
    status_dir="$(get_status_dir 2>/dev/null)" || true
    
    if [[ -n "$status_dir" ]]; then
        if [[ -f "${status_dir}/signal-complete-${issue_number}" ]]; then
            log_debug "Signal file detected: signal-complete-${issue_number}"
            echo "complete"
            return
        fi
        if [[ "$check_errors" == "true" ]] && [[ -f "${status_dir}/signal-error-${issue_number}" ]]; then
            log_debug "Signal file detected: signal-error-${issue_number}"
            echo "error"
            return
        fi
    fi
    
    # 1. pipe-pane ログファイルを検索（全出力を記録しているため確実）
    local log_file="${status_dir}/output-${issue_number}.log"
    
    if [[ -n "$status_dir" && -f "$log_file" ]]; then
        log_debug "Using pipe-pane log file: $log_file"
        
        # COMPLETEマーカーをチェック（grep -cF で高速検索）
        local complete_marker="###TASK_COMPLETE_${issue_number}###"
        local alt_complete_marker="###COMPLETE_TASK_${issue_number}###"
        
        if grep -qF "$complete_marker" "$log_file" 2>/dev/null || \
           grep -qF "$alt_complete_marker" "$log_file" 2>/dev/null; then
            # コードブロック内のマーカーを除外（周辺30行のみ検証で高速化）
            if verify_marker_outside_codeblock "$log_file" "$complete_marker" "true" || \
               verify_marker_outside_codeblock "$log_file" "$alt_complete_marker" "true"; then
                echo "complete"
                return
            fi
            log_debug "Marker found but inside code block, ignoring"
        fi
        
        # ERRORマーカーをチェック（オプション）
        if [[ "$check_errors" == "true" ]]; then
            local error_marker="###TASK_ERROR_${issue_number}###"
            local alt_error_marker="###ERROR_TASK_${issue_number}###"
            
            if grep -qF "$error_marker" "$log_file" 2>/dev/null || \
               grep -qF "$alt_error_marker" "$log_file" 2>/dev/null; then
                # コードブロック内のマーカーを除外（周辺30行のみ検証で高速化）
                if verify_marker_outside_codeblock "$log_file" "$error_marker" "true" || \
                   verify_marker_outside_codeblock "$log_file" "$alt_error_marker" "true"; then
                    echo "error"
                    return
                fi
                log_debug "Error marker found but inside code block, ignoring"
            fi
        fi
        
        echo ""
        return
    fi
    
    # 2. フォールバック: capture-pane で最後の500行を取得
    log_debug "No pipe-pane log found, falling back to capture-pane (500 lines)"
    if ! output=$(get_session_output "$session_name" 500 2>/dev/null); then
        log_warn "Failed to get output for session: $session_name"
        echo ""
        return
    fi
    
    # COMPLETEマーカーをチェック（代替パターンも検出：AIが語順を間違えるケースに対応）
    local complete_marker="###TASK_COMPLETE_${issue_number}###"
    local alt_complete_marker="###COMPLETE_TASK_${issue_number}###"
    local complete_count
    complete_count=$(count_any_markers_outside_codeblock "$output" "$complete_marker" "$alt_complete_marker")
    
    if [[ "$complete_count" -gt 0 ]]; then
        echo "complete"
        return
    fi
    
    # ERRORマーカーをチェック（オプション）（代替パターンも検出）
    if [[ "$check_errors" == "true" ]]; then
        local error_marker="###TASK_ERROR_${issue_number}###"
        local alt_error_marker="###ERROR_TASK_${issue_number}###"
        local error_count
        error_count=$(count_any_markers_outside_codeblock "$output" "$error_marker" "$alt_error_marker")
        
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
    
    # シグナルファイルを削除（cleanup.sh 実行前に削除して重複検出を防止）
    local status_dir
    status_dir="$(get_status_dir 2>/dev/null)" || true
    if [[ -n "$status_dir" ]]; then
        rm -f "${status_dir}/signal-complete-${issue_number}" 2>/dev/null || true
        rm -f "${status_dir}/signal-error-${issue_number}" 2>/dev/null || true
    fi
    
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
    sessions="$(list_sessions)"
    
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
        issue_num=$(extract_issue_number "$session" 2>/dev/null) || {
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
