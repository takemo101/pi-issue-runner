#!/usr/bin/env bash
# ============================================================================
# run/session.sh - Agent session management for run.sh
#
# Handles prompt generation and agent session creation/startup.
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_RUN_SESSION_SH_SOURCED:-}" ]]; then
    return 0
fi
_RUN_SESSION_SH_SOURCED="true"

# ライブラリディレクトリを取得
_RUN_SESSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存関係の読み込み
source "$_RUN_SESSION_LIB_DIR/../config.sh"
source "$_RUN_SESSION_LIB_DIR/../log.sh"
source "$_RUN_SESSION_LIB_DIR/../multiplexer.sh"
source "$_RUN_SESSION_LIB_DIR/../workflow.sh"
source "$_RUN_SESSION_LIB_DIR/../agent.sh"
source "$_RUN_SESSION_LIB_DIR/../hooks.sh"
source "$_RUN_SESSION_LIB_DIR/../status.sh"
source "$_RUN_SESSION_LIB_DIR/../tracker.sh"
source "$_RUN_SESSION_LIB_DIR/../cleanup-trap.sh"
source "$_RUN_SESSION_LIB_DIR/../yaml.sh"

# ============================================================================
# Generate prompt file for the agent session
# Arguments: $1=prompt_file, $2=workflow_name, $3=issue_number, $4=issue_title,
#            $5=issue_body, $6=branch_name, $7=full_worktree_path,
#            $8=issue_comments
# ============================================================================
generate_session_prompt() {
    local prompt_file="$1"
    local workflow_name="$2"
    local issue_number="$3"
    local issue_title="$4"
    local issue_body="$5"
    local branch_name="$6"
    local full_worktree_path="$7"
    local issue_comments="$8"

    log_info "Workflow: $workflow_name"

    # gates 後方互換警告
    local _config_for_gates
    _config_for_gates="$(config_file_found 2>/dev/null)" || _config_for_gates=""
    if [[ -n "$_config_for_gates" ]] && [[ -f "$_config_for_gates" ]]; then
        if yaml_exists "$_config_for_gates" ".gates" 2>/dev/null; then
            log_warn "⚠ 'gates' section is deprecated. Move gate definitions into workflow 'steps' as run: entries."
            log_warn "  See: docs/workflows.md#run--call-ステップ非aiステップ"
        fi
    fi

    # ステップグループを解析（run: 対応）
    local workflow_file
    workflow_file=$(find_workflow_file "$workflow_name" ".")
    local typed_steps step_groups has_non_ai_steps=false
    typed_steps="$(get_workflow_steps_typed "$workflow_file")"
    step_groups="$(echo "$typed_steps" | get_step_groups)"

    # non-AI ステップが含まれるか判定
    if echo "$step_groups" | grep -q "^non_ai_group"; then
        has_non_ai_steps=true
    fi

    if [[ "$has_non_ai_steps" == "true" ]]; then
        # non-AIステップがある場合: 最初のAIグループのみのプロンプトを生成
        local first_ai_steps total_groups
        total_groups=$(echo "$step_groups" | wc -l | tr -d ' ')
        first_ai_steps="$(echo "$step_groups" | head -1 | cut -f2)"

        # 最初のグループがAIグループであることを確認
        local first_group_type
        first_group_type="$(echo "$step_groups" | head -1 | cut -f1)"
        if [[ "$first_group_type" != "ai_group" ]]; then
            log_error "Workflow '$workflow_name': first step must be an AI step (e.g., plan, implement), not run:"
            log_error "Move run: steps after at least one AI step."
            exit 1
        fi

        local is_final="false"
        if [[ "$total_groups" -eq 1 ]]; then
            is_final="true"
        fi

        generate_ai_group_prompt 0 "$total_groups" "$first_ai_steps" "$is_final" \
            "$workflow_name" "$issue_number" "$issue_title" "$issue_body" \
            "$branch_name" "$full_worktree_path" "." "$issue_comments" "" > "$prompt_file"

        # ステップグループ情報を保存（watcherが使用）
        save_step_groups "$issue_number" "$step_groups"
        log_info "Step groups saved (non-AI steps detected)"
    else
        # non-AIステップなし: 従来の全ステップ一括プロンプト
        write_workflow_prompt "$prompt_file" "$workflow_name" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$full_worktree_path" "." "$issue_comments"
    fi
}

# ============================================================================
# Apply workflow-specific agent configuration
# Arguments: $1=workflow_file
# ============================================================================
apply_session_agent_config() {
    local workflow_file="$1"
    apply_workflow_agent_override "$workflow_file"
}

# ============================================================================
# Create and start the agent session
# Arguments: $1=session_name, $2=full_worktree_path, $3=prompt_file, $4=extra_agent_args
# ============================================================================
create_agent_session() {
    local session_name="$1"
    local full_worktree_path="$2"
    local prompt_file="$3"
    local extra_agent_args="$4"

    # エージェントコマンド構築
    local full_command
    full_command="$(build_agent_command "$prompt_file" "$extra_agent_args")"

    # tmuxセッション作成
    log_info "=== Starting Agent Session ==="
    log_info "Agent: $(get_agent_type)"
    mux_create_session "$session_name" "$full_worktree_path" "$full_command"
}

# ============================================================================
# Save session metadata after session creation
# Arguments: $1=issue_number, $2=session_name, $3=session_label, $4=workflow_name
# ============================================================================
save_session_metadata() {
    local issue_number="$1"
    local session_name="$2"
    local session_label="$3"
    local workflow_name="$4"

    # Issue #974: セッション作成直後にステータスを保存（レースコンディション回避）
    # Issue #1106: セッションラベルを保存（improve.shで使用）
    save_status "$issue_number" "running" "$session_name" "" "$session_label"
    
    # Issue #1298: トラッカーメタデータを保存（ワークフロー名と開始時刻）
    save_tracker_metadata "$issue_number" "$workflow_name"
}

# ============================================================================
# Run on_start hook
# Arguments: $1=issue_number, $2=session_name, $3=branch_name, 
#            $4=full_worktree_path, $5=issue_title
# ============================================================================
run_session_start_hook() {
    local issue_number="$1"
    local session_name="$2"
    local branch_name="$3"
    local full_worktree_path="$4"
    local issue_title="$5"

    run_hook "on_start" "$issue_number" "$session_name" "feature/$branch_name" "$full_worktree_path" "" "0" "$issue_title"
}

# ============================================================================
# Main session startup orchestrator
# Arguments: $1=session_name, $2=issue_number, $3=issue_title, $4=issue_body,
#            $5=branch_name, $6=full_worktree_path, $7=workflow_name,
#            $8=issue_comments, $9=extra_agent_args, $10=session_label
# ============================================================================
start_agent_session() {
    local session_name="$1"
    local issue_number="$2"
    local issue_title="$3"
    local issue_body="$4"
    local branch_name="$5"
    local full_worktree_path="$6"
    local workflow_name="$7"
    local issue_comments="$8"
    local extra_agent_args="$9"
    local session_label="${10:-}"

    # ワークフローからプロンプトファイルを生成
    local prompt_file="$full_worktree_path/.pi-prompt.md"
    
    # プロンプト生成
    generate_session_prompt "$prompt_file" "$workflow_name" "$issue_number" \
        "$issue_title" "$issue_body" "$branch_name" "$full_worktree_path" "$issue_comments"
    
    # ワークフロー固有のエージェント設定を適用
    local workflow_file
    workflow_file=$(find_workflow_file "$workflow_name" ".")
    apply_session_agent_config "$workflow_file"
    
    # エージェントセッション作成
    create_agent_session "$session_name" "$full_worktree_path" "$prompt_file" "$extra_agent_args"
    
    # セッション作成成功 - クリーンアップ対象から除外
    unregister_worktree_for_cleanup
    
    # メタデータ保存
    save_session_metadata "$issue_number" "$session_name" "$session_label" "$workflow_name"
    
    # on_start hookを実行
    run_session_start_hook "$issue_number" "$session_name" "$branch_name" "$full_worktree_path" "$issue_title"
}
