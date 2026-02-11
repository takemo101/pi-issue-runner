#!/usr/bin/env bash
# ============================================================================
# lib/watcher/markers.sh - Marker detection functions for watch-session
#
# Responsibilities:
#   - Pipe-pane marker detection (_check_pipe_pane_markers)
#   - Capture-pane fallback detection (_check_capture_pane_fallback)
#   - Capture-pane marker detection (_check_capture_pane_markers)
#   - Initial marker checking (check_initial_markers)
#   - Marker verification outside codeblocks (_verify_real_marker)
# ============================================================================

set -euo pipefail

# Source required libraries
WATCHER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../marker.sh
source "$WATCHER_LIB_DIR/../marker.sh"
# shellcheck source=../log.sh
source "$WATCHER_LIB_DIR/../log.sh"
# shellcheck source=../config.sh
source "$WATCHER_LIB_DIR/../config.sh"
# shellcheck source=../multiplexer.sh
source "$WATCHER_LIB_DIR/../multiplexer.sh"

# ============================================================================
# Helper: Extract error message from file or text (line after error marker)
# Usage: _extract_error_message <source> <error_marker> [alt_error_marker] [is_file]
# ============================================================================
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

# ============================================================================
# Verify marker is outside codeblock for both primary and alt markers
# Usage: _verify_real_marker <source> <primary_marker> <alt_marker> <is_file>
# Returns: 0=real marker found, 1=only in codeblock
# ============================================================================
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

# ============================================================================
# Check for markers already present at startup (fast-completing tasks)
# Usage: check_initial_markers <session_name> <issue_number> <marker> <error_marker> <auto_attach> <cleanup_args> <baseline_output> <alt_complete_marker> <alt_error_marker>
# Returns: 0 if completion handled, 1 if should continue monitoring, 2 if cleanup failed
# ============================================================================
check_initial_markers() {
    local session_name="$1"
    local issue_number="$2"
    local marker="$3"
    local error_marker="$4"
    local auto_attach="$5"
    local cleanup_args="$6"
    local baseline_output="$7"
    local alt_complete_marker="${8:-}"
    local alt_error_marker="${9:-}"

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
        # handle_error is passed as callback - caller should source handle_error separately
        # For now, return special code to indicate error signal found
        echo "ERROR_SIGNAL:${error_message}"
        return 1
    fi

    # シグナルファイルによる初期完了チェック
    if [[ -n "$status_dir" && -f "${status_dir}/signal-complete-${issue_number}" ]]; then
        log_info "Completion signal file already present at startup"
        rm -f "${status_dir}/signal-complete-${issue_number}"
        echo "COMPLETE_SIGNAL"
        return 0
    fi

    # capture-pane による完了マーカーチェック（エラーマーカーはチェックしない）
    local initial_complete_count
    initial_complete_count=$(count_any_markers_outside_codeblock "$baseline_output" "$marker" "$alt_complete_marker")

    if [[ "$initial_complete_count" -gt 0 ]]; then
        log_info "Completion marker already present at startup (outside codeblock)"
        echo "COMPLETE_MARKER"
        return 0
    fi

    return 1  # No initial completion marker, continue to monitoring loop
}

# ============================================================================
# Phase 2a: Check pipe-pane markers (incremental grep-based detection)
# Scans only new content since last check to avoid false positives from
# continue prompts that contain marker text (displayed via pi's Steering output).
# Usage: _check_pipe_pane_markers <output_log> <marker> <error_marker> <session_name> <issue_number> <auto_attach> <cleanup_args> <cumulative_complete_var> <cumulative_error_var> <alt_complete_marker> <alt_error_marker> <phase_complete_marker>
# Returns: 0=complete (exit 0), 1=error handled, 2=PR merge timeout, 255=no new marker
# ============================================================================
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
    local alt_complete_marker="${10:-}"
    local alt_error_marker="${11:-}"
    local phase_complete_marker="${12:-}"
    local -n _cpp_cumulative_phase="${13:-_cpp_cumulative_phase_unused}"
    local -n _pipe_pane_last_offset="${14:-_pipe_pane_last_offset_unused}"

    # Step 0: 差分スキャン — 前回チェック位置から新しい部分のみを抽出
    local current_size=0
    current_size=$(wc -c < "$output_log" 2>/dev/null) || current_size=0
    if [[ "$current_size" -le "${_pipe_pane_last_offset:-0}" ]]; then
        return 255  # ファイルサイズ変化なし
    fi

    local new_content=""
    new_content=$(tail -c +"$((_pipe_pane_last_offset + 1))" "$output_log" 2>/dev/null) || new_content=""
    _pipe_pane_last_offset="$current_size"

    if [[ -z "$new_content" ]]; then
        return 255
    fi

    # Step 1: 差分内のマーカーカウント
    local new_error_count=0 new_complete_count=0 new_phase_count=0
    new_error_count=$(echo "$new_content" | grep -cF "$error_marker" 2>/dev/null) || new_error_count=0
    if [[ -n "$alt_error_marker" ]]; then
        local alt_c=0
        alt_c=$(echo "$new_content" | grep -cF "$alt_error_marker" 2>/dev/null) || alt_c=0
        new_error_count=$((new_error_count + alt_c))
    fi
    new_complete_count=$(echo "$new_content" | grep -cF "$marker" 2>/dev/null) || new_complete_count=0
    if [[ -n "$alt_complete_marker" ]]; then
        local alt_c=0
        alt_c=$(echo "$new_content" | grep -cF "$alt_complete_marker" 2>/dev/null) || alt_c=0
        new_complete_count=$((new_complete_count + alt_c))
    fi

    # Step 2: 新規エラーマーカーが見つかった場合のみコードブロック検証
    if [[ "$new_error_count" -gt 0 ]]; then
        if _verify_real_marker "$output_log" "$error_marker" "$alt_error_marker" "true"; then
            local file_error_count
            file_error_count=$(grep_marker_count_in_file "$output_log" "$error_marker" "$alt_error_marker")
            log_warn "Error marker detected! (count: $file_error_count)"
            _cpp_cumulative_error="$file_error_count"

            local error_message
            error_message=$(_extract_error_message "$output_log" "$error_marker" "$alt_error_marker" "true")
            echo "ERROR_MARKER:${error_message}"
            return 1
        else
            log_debug "Error marker found in code block, ignoring"
        fi
    fi

    # Step 3: PHASE_COMPLETE マーカーチェック（run: ステップ対応）
    if [[ -n "$phase_complete_marker" ]]; then
        new_phase_count=$(echo "$new_content" | grep -cF "$phase_complete_marker" 2>/dev/null) || new_phase_count=0
        if [[ "$new_phase_count" -gt 0 ]]; then
            # 差分内にマーカーがある場合、コードブロック外か検証
            local phase_outside_count
            phase_outside_count=$(count_markers_outside_codeblock "$new_content" "$phase_complete_marker")
            if [[ "$phase_outside_count" -gt 0 ]]; then
                _cpp_cumulative_phase=$((_cpp_cumulative_phase + phase_outside_count))
                log_info "Phase complete marker detected! (count: $_cpp_cumulative_phase)"
                echo "PHASE_MARKER"
                return 0
            fi
        fi
    fi

    # Step 4: 新規完了マーカーが見つかった場合のみコードブロック検証
    if [[ "$new_complete_count" -gt 0 ]]; then
        local complete_outside_count
        complete_outside_count=$(count_any_markers_outside_codeblock "$new_content" "$marker" "$alt_complete_marker")
        if [[ "$complete_outside_count" -gt 0 ]]; then
            _cpp_cumulative_complete=$((_cpp_cumulative_complete + complete_outside_count))
            log_info "Completion marker detected! (count: $_cpp_cumulative_complete)"
            echo "COMPLETE_MARKER"
            return 0
        else
            log_debug "Complete marker found in code block, ignoring"
        fi
    fi

    return 255  # No new marker
}

# ============================================================================
# Phase 2b: Periodic capture-pane fallback for pipe-pane mode
# Used to catch markers when pipe-pane hasn't flushed (every 15 loops ~30s)
# This handles the case where the AI outputs a marker then goes idle,
# causing tmux pipe-pane to hold the buffer without flushing to the log file.
# Checks both TASK_COMPLETE and PHASE_COMPLETE markers.
# Note: Does not check error markers to avoid false positives from template text.
# Usage: _check_capture_pane_fallback <session_name> <marker> <issue_number> <auto_attach> <cleanup_args> <loop_count> <marker_count_current> <cumulative_complete_count> <alt_complete_marker> <alt_error_marker> <phase_complete_marker>
# Returns: 0=complete (exit 0), 2=PR merge timeout, 255=no marker
# ============================================================================
_check_capture_pane_fallback() {
    local session_name="$1"
    local marker="$2"
    local issue_number="$3"
    local auto_attach="$4"
    local cleanup_args="$5"
    local loop_count="$6"
    local marker_count_current="$7"
    local cumulative_complete_count="$8"
    local alt_complete_marker="$9"
    local phase_complete_marker="${10:-}"

    # Only check every 15 loops (~30 seconds) and only when no markers found yet
    if [[ "$marker_count_current" -ne 0 ]] || [[ "$cumulative_complete_count" -ne 0 ]] \
       || [[ $((loop_count % 15)) -ne 0 ]]; then
        return 255
    fi

    local capture_fallback_output
    capture_fallback_output=$(mux_get_session_output "$session_name" 500 2>/dev/null) || capture_fallback_output=""
    if [[ -z "$capture_fallback_output" ]]; then
        return 255
    fi

    # Check PHASE_COMPLETE marker first (run: step workflow)
    if [[ -n "$phase_complete_marker" ]]; then
        local capture_phase_count=0
        capture_phase_count=$(count_markers_outside_codeblock "$capture_fallback_output" "$phase_complete_marker") || capture_phase_count=0
        if [[ "$capture_phase_count" -gt 0 ]]; then
            log_info "Phase complete marker found via capture-pane fallback (count: $capture_phase_count)"
            echo "PHASE_MARKER:${capture_phase_count}"
            return 0
        fi
    fi

    # Check TASK_COMPLETE marker
    local capture_complete_count
    capture_complete_count=$(count_any_markers_outside_codeblock "$capture_fallback_output" "$marker" "$alt_complete_marker")
    if [[ "$capture_complete_count" -gt 0 ]]; then
        log_info "Completion marker found via capture-pane fallback"
        echo "COMPLETE_MARKER"
        return 0
    fi

    return 255
}

# ============================================================================
# Phase 2c: Check capture-pane markers (when pipe-pane is not available)
# Usage: _check_capture_pane_markers <session_name> <marker> <error_marker> <issue_number> <auto_attach> <cleanup_args> <cumulative_complete_var> <cumulative_error_var> <alt_complete_marker> <alt_error_marker>
# Returns: 0=complete (exit 0), 1=error handled, 2=PR merge timeout, 255=no marker, 3=capture failed
# ============================================================================
_check_capture_pane_markers() {
    local session_name="$1"
    local marker="$2"
    local error_marker="$3"
    local issue_number="$4"
    local auto_attach="$5"
    local cleanup_args="$6"
    local -n _ccp_cumulative_complete="$7"
    local -n _ccp_cumulative_error="$8"
    local alt_complete_marker="$9"
    local alt_error_marker="${10:-}"

    local output
    output=$(mux_get_session_output "$session_name" 1000 2>/dev/null) || {
        log_warn "Failed to capture pane output"
        return 3
    }

    local error_count_current
    error_count_current=$(count_any_markers_outside_codeblock "$output" "$error_marker" "$alt_error_marker")
    if [[ "$error_count_current" -gt "$_ccp_cumulative_error" ]]; then
        log_warn "Error marker detected! (cumulative: $_ccp_cumulative_error, current: $error_count_current)"
        _ccp_cumulative_error="$error_count_current"

        local error_message
        error_message=$(_extract_error_message "$output" "$error_marker" "$alt_error_marker")
        echo "ERROR_MARKER:${error_message}"
        return 1
    fi

    local marker_count_current
    marker_count_current=$(count_any_markers_outside_codeblock "$output" "$marker" "$alt_complete_marker")
    if [[ "$marker_count_current" -gt "$_ccp_cumulative_complete" ]]; then
        log_info "Completion marker detected! (cumulative: $_ccp_cumulative_complete, current: $marker_count_current)"
        _ccp_cumulative_complete="$marker_count_current"
        echo "COMPLETE_MARKER"
        return 0
    fi

    return 255
}

# ============================================================================
# Phase 1: Check signal files (highest priority, most reliable)
# AI creates files directly, so no ANSI/codeblock/scrollout issues
# Usage: _check_signal_files <signal_complete> <signal_error> <session_name> <issue_number> <auto_attach> <cleanup_args>
# Returns: 0=complete handled (exit 0), 1=error handled, 2=PR merge timeout, 255=no signal
# ============================================================================
_check_signal_files() {
    local signal_complete="$1"
    local signal_error="$2"
    local session_name="$3"
    local issue_number="$4"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local auto_attach="$5"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local cleanup_args="$6"

    if [[ -f "$signal_complete" ]]; then
        log_info "Completion signal file detected: $signal_complete"
        rm -f "$signal_complete"
        echo "COMPLETE_SIGNAL"
        return 0
    fi

    if [[ -f "$signal_error" ]]; then
        log_warn "Error signal file detected: $signal_error"
        local sig_error_message
        sig_error_message=$(cat "$signal_error" 2>/dev/null | head -c 200) || sig_error_message="Unknown error"
        rm -f "$signal_error"
        echo "ERROR_SIGNAL:${sig_error_message}"
        return 1
    fi

    return 255  # No signal found
}

# Export functions for use by watch-session.sh
export -f _extract_error_message
export -f _verify_real_marker
export -f check_initial_markers
export -f _check_pipe_pane_markers
export -f _check_capture_pane_fallback
export -f _check_capture_pane_markers
export -f _check_signal_files
