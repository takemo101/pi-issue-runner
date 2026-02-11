#!/usr/bin/env bash
# ============================================================================
# lib/watcher/phase.sh - Phase management functions for watch-session
#
# Responsibilities:
#   - Phase completion handling (handle_phase_complete)
#   - Non-AI step execution (_run_non_ai_steps)
#   - Complete handling (handle_complete)
# ============================================================================

set -euo pipefail

# Source required libraries
WATCHER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../log.sh
source "$WATCHER_LIB_DIR/../log.sh"
# shellcheck source=../config.sh
source "$WATCHER_LIB_DIR/../config.sh"
# shellcheck source=../multiplexer.sh
source "$WATCHER_LIB_DIR/../multiplexer.sh"
# shellcheck source=../status.sh
source "$WATCHER_LIB_DIR/../status.sh"
# shellcheck source=../tracker.sh
source "$WATCHER_LIB_DIR/../tracker.sh"
# shellcheck source=../hooks.sh
source "$WATCHER_LIB_DIR/../hooks.sh"
# shellcheck source=../workflow.sh
source "$WATCHER_LIB_DIR/../workflow.sh"
# shellcheck source=../step-runner.sh
source "$WATCHER_LIB_DIR/../step-runner.sh"
# shellcheck source=../worktree.sh
source "$WATCHER_LIB_DIR/../worktree.sh"

# ============================================================================
# Globals for phase tracking (managed by watch-session.sh)
# These are sourced from the parent script's context
# ============================================================================

# ============================================================================
# Resolve worktree information for an issue
# Usage: _resolve_worktree_info <issue_number> <worktree_path_var> <branch_name_var>
# Sets: worktree_path_var and branch_name_var via nameref
# ============================================================================
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

# ============================================================================
# Save completion status and handle plan file deletion
# Usage: _complete_status_and_plans <issue_number> <session_name>
# ============================================================================
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

# ============================================================================
# Run completion hooks
# Usage: _run_completion_hooks <issue_number> <session_name> <branch_name> <worktree_path> [gates_json]
# ============================================================================
_run_completion_hooks() {
    local issue_number="$1"
    local session_name="$2"
    local branch_name="$3"
    local worktree_path="$4"
    local gates_json="${5:-}"
    
    record_tracker_entry "$issue_number" "success" "" "$gates_json" 2>/dev/null || true
    
    run_hook "on_success" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "" "0" "" 2>/dev/null || true
}

# ============================================================================
# Run cleanup with retry logic
# Usage: _run_cleanup_with_retry <session_name> <cleanup_args> <watcher_script_dir>
# Returns: 0 on success, 1 on failure
# ============================================================================
_run_cleanup_with_retry() {
    local session_name="$1"
    local cleanup_args="${2:-}"
    local watcher_script_dir="${3:-}"
    
    log_info "Running cleanup..."
    
    # セッション終了の最終確認（handle_complete で kill 済みだが念のため待機）
    if mux_session_exists "$session_name"; then
        local cleanup_delay
        cleanup_delay="$(get_config watcher_cleanup_delay)"
        log_info "Session still alive, waiting for termination (${cleanup_delay}s)..."
        sleep "$cleanup_delay"
    fi
    
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
        if "${watcher_script_dir}/cleanup.sh" "$session_name" $cleanup_args $force_flag; then
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

# ============================================================================
# Post-cleanup maintenance: orphan detection and plan rotation
# Usage: _post_cleanup_maintenance <watcher_script_dir>
# ============================================================================
_post_cleanup_maintenance() {
    local watcher_script_dir="${1:-}"
    
    # orphaned worktreeの検出と修復
    log_info "Checking for any orphaned worktrees with 'complete' status..."
    local orphaned_count
    orphaned_count=$(count_complete_with_existing_worktrees)
    
    if [[ "$orphaned_count" -gt 0 ]]; then
        log_info "Found $orphaned_count orphaned worktree(s) with 'complete' status. Cleaning up..."
        # shellcheck source=../cleanup-orphans.sh
        cleanup_complete_with_worktrees "false" "false" || {
            log_warn "Some orphaned worktrees could not be cleaned up automatically"
        }
    else
        log_debug "No orphaned worktrees found"
    fi
    
    # 古い計画書をローテーション
    log_info "Rotating old plans..."
    "${watcher_script_dir}/cleanup.sh" --rotate-plans 2>/dev/null || {
        log_warn "Plan rotation failed (non-critical)"
    }
}

# ============================================================================
# Run non-AI steps (run:) for quality verification
# Usage: _run_non_ai_steps <session_name> <issue_number> <worktree_path> <branch_name> <non_ai_group_escaped>
# Args:
#   non_ai_group_escaped: \n区切りの run/call ステップ定義（get_step_groups の non_ai_group 出力）
# Returns: 0=all passed or no steps, 1=step failed (nudge sent, continue monitoring)
# ============================================================================
_run_non_ai_steps() {
    local session_name="$1"
    local issue_number="$2"
    local worktree_path="$3"
    local branch_name="$4"
    local non_ai_group_escaped="$5"

    if [[ -z "$non_ai_group_escaped" ]]; then
        log_debug "No non-AI steps defined, skipping"
        return 0
    fi

    log_info "Running non-AI steps for Issue #$issue_number..."

    # run: 出力ファイルパスを追跡（成功時のnudge用）
    local -a _run_output_paths=()

    # \n を改行に戻して各ステップを処理
    local step_line
    while IFS= read -r step_line; do
        [[ -z "$step_line" ]] && continue

        local step_type
        step_type="${step_line%%	*}"
        local rest="${step_line#*	}"

        # タブ区切りフィールドを分解
        local cmd_or_name timeout max_retry retry_interval continue_on_fail description
        # shellcheck disable=SC2034  # max_retry, retry_interval reserved for future per-step retry
        IFS=$'\t' read -r cmd_or_name timeout max_retry retry_interval continue_on_fail description <<< "$rest"

        local display_name="${description:-$cmd_or_name}"
        log_info "Step: $display_name"

        local step_output="" step_result=0
        if [[ "$step_type" == "run" ]]; then
            if [[ "${PI_SKIP_RUN:-}" == "1" ]]; then
                log_info "run: step skipped (PI_SKIP_RUN=1): $display_name"
                continue
            fi
            step_output=$(run_command_step "$cmd_or_name" "$timeout" "$worktree_path" "$issue_number" "" "$branch_name" "$description" 2>&1) || step_result=$?
            # run: 出力ファイルパスを記録
            if [[ -n "${PI_LAST_RUN_OUTPUT_PATH:-}" ]]; then
                _run_output_paths+=("${display_name}=${PI_LAST_RUN_OUTPUT_PATH}")
            fi
        elif [[ "$step_type" == "call" ]]; then
            log_warn "call: steps are deprecated and ignored. Use AI steps instead: $cmd_or_name"
            continue
        else
            log_warn "Unknown step type: $step_type, skipping"
            continue
        fi

        if [[ $step_result -ne 0 ]]; then
            if [[ "$continue_on_fail" == "true" ]]; then
                log_warn "Step failed but continue_on_fail=true: $display_name"
                continue
            fi

            log_warn "Step failed: $display_name"

            # nudge でAIセッションにエラー内容を送信
            local output_path_info=""
            if [[ -n "${PI_LAST_RUN_OUTPUT_PATH:-}" ]]; then
                output_path_info="$(printf '\n詳細出力: %s' "$PI_LAST_RUN_OUTPUT_PATH")"
            fi
            local nudge_message
            nudge_message="$(printf 'ステップ「%s」が失敗しました。以下の問題を修正してから、再度フェーズ完了マーカーを出力してください。%s\n\n%s' "$display_name" "$output_path_info" "$step_output")"

            if mux_session_exists "$session_name"; then
                mux_send_keys "$session_name" "$nudge_message"
                log_info "Step failure nudge sent to session: $session_name"
            else
                log_warn "Session $session_name no longer exists, cannot send nudge"
            fi

            return 1
        fi

        log_info "Step passed: $display_name"
    done < <(printf '%b\n' "$non_ai_group_escaped")

    # 成功時: run: 出力パスをエクスポート（後続nudgeで使用）
    if [[ ${#_run_output_paths[@]} -gt 0 ]]; then
        PI_RUN_OUTPUT_SUMMARY="$(printf '%s\n' "${_run_output_paths[@]}")"
        export PI_RUN_OUTPUT_SUMMARY
    fi

    log_info "All non-AI steps passed for Issue #$issue_number"
    return 0
}

# ============================================================================
# Check PR merge status with retry logic
# Usage: check_pr_merge_status <session_name> <branch_name> <issue_number> [max_attempts] [retry_interval]
# Returns: 0 if PR is merged or closed, 1 if still open/not found after all retries, 2 if timed out
# ============================================================================
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
                return 2  # Timeout
            fi
        fi
    done
    
    # Should not reach here, but return error code as fallback
    return 1
}

# ============================================================================
# Handle completion result from handle_complete
# Usage: _handle_complete_result <result_code> <source_label> <interval>
# Returns: 0=exit success, 1=exit failure, 2=continue monitoring
# ============================================================================
_handle_complete_result() {
    local result_code="$1"
    local source_label="$2"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
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

# ============================================================================
# PHASE_COMPLETE ハンドリング（run: ステップ対応）
# ============================================================================

# ============================================================================
# PHASE_COMPLETE マーカー検出時のハンドラー
# non-AI ステップ群を実行し、成功したら次のAIグループのプロンプトを nudge
# Usage: handle_phase_complete <session_name> <issue_number> <auto_attach> <cleanup_args> <current_phase_index_var> <step_groups_data_var> <phase_retry_count_var> <max_step_retries> <alt_complete_marker> <alt_error_marker> <phase_complete_marker>
# Returns: 0=次のAIグループへ進行, 1=エラー, 2=non-AIステップ失敗（再監視を継続）
# ============================================================================
handle_phase_complete() {
    local session_name="$1"
    local issue_number="$2"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local auto_attach="$3"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local cleanup_args="${4:-}"
    local -n _current_phase_index="$5"
    local -n _step_groups_data="$6"
    local -n _phase_retry_count="$7"
    local max_step_retries="${8:-10}"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local alt_complete_marker="${9:-}"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local alt_error_marker="${10:-}"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local phase_complete_marker="${11:-}"

    log_info "Phase complete detected: $session_name (Issue #$issue_number)"

    # ステップグループ情報を読み込み（初回のみ）
    if [[ -z "$_step_groups_data" ]]; then
        _step_groups_data="$(load_step_groups "$issue_number" 2>/dev/null)" || _step_groups_data=""
        if [[ -z "$_step_groups_data" ]]; then
            log_warn "No step groups data found. Treating as regular COMPLETE."
            return 0
        fi
    fi

    local total_groups
    total_groups=$(echo "$_step_groups_data" | wc -l | tr -d ' ')

    # 現在のフェーズの次のグループを取得
    local next_index=$((_current_phase_index + 1))

    if [[ $next_index -ge $total_groups ]]; then
        log_info "All phases complete (no more groups)"
        return 0
    fi

    # 次のグループを取得
    local next_group
    next_group="$(echo "$_step_groups_data" | sed -n "$((next_index + 1))p")"
    local next_type="${next_group%%	*}"
    local next_content="${next_group#*	}"

    if [[ "$next_type" == "non_ai_group" ]]; then
        # non-AI ステップ群を実行
        local worktree_path branch_name
        _resolve_worktree_info "$issue_number" worktree_path branch_name

        local step_result=0
        _run_non_ai_steps "$session_name" "$issue_number" "$worktree_path" "$branch_name" "$next_content" || step_result=$?

        if [[ $step_result -ne 0 ]]; then
            _phase_retry_count=$((_phase_retry_count + 1))
            if [[ $_phase_retry_count -ge $max_step_retries ]]; then
                log_error "Non-AI steps exceeded max retries ($max_step_retries). Aborting."
                return 1
            fi
            log_warn "Non-AI steps failed (retry $_phase_retry_count/$max_step_retries). Waiting for AI fix..."
            return 2
        fi

        # non-AI ステップ通過 → リトライカウンタをリセット
        _phase_retry_count=0
        _current_phase_index=$next_index

        # さらに次のグループを確認
        local after_index=$((_current_phase_index + 1))
        if [[ $after_index -ge $total_groups ]]; then
            # non-AI が最後のグループ → 全フェーズ完了として処理
            log_info "All phases complete (non-AI steps were the last group)"
            return 0
        fi

        local after_group
        after_group="$(echo "$_step_groups_data" | sed -n "$((after_index + 1))p")"
        local after_type="${after_group%%	*}"
        local after_content="${after_group#*	}"

        if [[ "$after_type" == "ai_group" ]]; then
            # 次のAIグループのプロンプトを nudge
            _current_phase_index=$after_index
            local is_final="false"
            if [[ $((after_index + 1)) -ge $total_groups ]]; then
                is_final="true"
            fi

            # ワークフロー名を取得
            local workflow_name=""
            local tracker_meta
            tracker_meta="$(load_tracker_metadata "$issue_number" 2>/dev/null)" || tracker_meta=""
            if [[ -n "$tracker_meta" ]]; then
                workflow_name="$(echo "$tracker_meta" | cut -f1)"
            fi

            # 次のAIグループのプロンプトをファイルに書き出す
            local worktree_path_resolved branch_name_resolved
            _resolve_worktree_info "$issue_number" worktree_path_resolved branch_name_resolved
            # AIグループのインデックスを正確に計算
            local ai_group_index=0 _gi
            for ((_gi=0; _gi<=after_index; _gi++)); do
                local _g_type
                _g_type="$(echo "$_step_groups_data" | sed -n "$((_gi + 1))p" | cut -f1)"
                [[ "$_g_type" == "ai_group" ]] && ((ai_group_index++)) || true
            done
            ((ai_group_index--)) || true  # 0始まりに調整

            # プロンプトをファイルに書き出す
            local phase_num=$((ai_group_index + 1))
            local prompt_filename=".pi-prompt-phase${phase_num}.md"
            local prompt_filepath="${worktree_path_resolved}/${prompt_filename}"

            write_ai_group_prompt_file "$prompt_filepath" \
                "$ai_group_index" "$total_groups" "$after_content" "$is_final" \
                "$workflow_name" "$issue_number" "" "" "$branch_name_resolved" "$worktree_path_resolved" "." "" ""

            # run: 出力の参照情報をファイルに追記
            if [[ -n "${PI_RUN_OUTPUT_SUMMARY:-}" ]]; then
                append_run_output_summary "$prompt_filepath" "$PI_RUN_OUTPUT_SUMMARY"
                unset PI_RUN_OUTPUT_SUMMARY
            fi

            if mux_session_exists "$session_name"; then
                mux_send_keys "$session_name" "Read and follow the instructions in ${prompt_filename}"
                log_info "Continue prompt file written: $prompt_filepath (sent path to session)"
            else
                log_warn "Session $session_name no longer exists"
                return 1
            fi

            # AIグループの完了待ちに戻る
            return 2
        fi
    elif [[ "$next_type" == "ai_group" ]]; then
        # 次がAIグループ（non-AI ステップがなかった場合）
        _current_phase_index=$next_index
        log_info "Next group is AI, continuing..."
        return 2
    fi

    return 0
}

# ============================================================================
# 完了ハンドリング関数
# Usage: handle_complete <session_name> <issue_number> <auto_attach> <cleanup_args> <watcher_script_dir>
# Returns: 0 on success, 1 on cleanup failure, 2 on PR merge timeout or gate failure (continue monitoring)
# ============================================================================
handle_complete() {
    local session_name="$1"
    local issue_number="$2"
    # shellcheck disable=SC2034  # Reserved for future use (API consistency)
    local auto_attach="$3"
    local cleanup_args="${4:-}"
    local watcher_script_dir="${5:-}"
    
    log_info "Session completed: $session_name (Issue #$issue_number)"
    
    # 1. worktreeパスとブランチ名を取得
    local worktree_path branch_name
    _resolve_worktree_info "$issue_number" worktree_path branch_name
    
    # 2. (gates は廃止 — run: ステップに統合済み。#1406)
    local gates_json=""
    
    # 3. ステータスと計画書の処理
    _complete_status_and_plans "$issue_number" "$session_name"

    # 3.5. ステップグループ情報をクリーンアップ
    remove_step_groups "$issue_number" 2>/dev/null || true
    
    # 4. Hook実行
    _run_completion_hooks "$issue_number" "$session_name" "$branch_name" "$worktree_path" "$gates_json"
    
    # 5. PR確認（リトライロジック付き）
    local pr_check_result
    check_pr_merge_status "$session_name" "$branch_name" "$issue_number"
    pr_check_result=$?
    
    if [[ $pr_check_result -eq 2 ]]; then
        local force_cleanup
        force_cleanup="$(get_config watcher_force_cleanup_on_timeout)"
        if [[ "$force_cleanup" == "true" ]]; then
            log_warn "PR merge timeout. Force cleanup enabled - proceeding with cleanup anyway."
        else
            log_warn "PR merge timeout. Will continue monitoring for manual completion."
            log_warn "Hint: Set watcher.force_cleanup_on_timeout: false in .pi-runner.yaml to disable auto-cleanup on timeout."
            return 2
        fi
    elif [[ $pr_check_result -ne 0 ]]; then
        log_error "PR check failed with unexpected error"
        return 1
    fi
    
    # 6. セッションを明示的に終了させる（cleanup前にworktreeロックを解放）
    # AIがCOMPLETEマーカーを出した後もプロンプト待ちで居座るケースを防ぐ
    if mux_session_exists "$session_name"; then
        log_info "Terminating session before cleanup: $session_name"
        mux_kill_session "$session_name" 10 2>/dev/null || true
        
        # mux_kill_session 後に確認
        if mux_session_exists "$session_name"; then
            log_warn "Session still alive after kill attempt, proceeding with cleanup anyway"
        fi
    fi
    
    # 7. Cleanup実行
    if ! _run_cleanup_with_retry "$session_name" "$cleanup_args" "$watcher_script_dir"; then
        return 1
    fi
    
    # 8. 事後処理
    _post_cleanup_maintenance "$watcher_script_dir"
    
    log_info "Cleanup completed successfully"
    
    return 0
}

# Export functions for use by watch-session.sh
export -f _resolve_worktree_info
export -f _complete_status_and_plans
export -f _run_completion_hooks
export -f _run_cleanup_with_retry
export -f _post_cleanup_maintenance
export -f _run_non_ai_steps
export -f check_pr_merge_status
export -f _handle_complete_result
export -f handle_phase_complete
export -f handle_complete
