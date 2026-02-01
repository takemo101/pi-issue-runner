#!/usr/bin/env bash
# watch-session.sh - セッション出力を監視し、完了/エラーマーカーでアクションを実行

set -euo pipefail

# SCRIPT_DIRを保存（sourceで上書きされるため）
WATCHER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WATCHER_SCRIPT_DIR/../lib/config.sh"
source "$WATCHER_SCRIPT_DIR/../lib/log.sh"
source "$WATCHER_SCRIPT_DIR/../lib/tmux.sh"
source "$WATCHER_SCRIPT_DIR/../lib/notify.sh"
source "$WATCHER_SCRIPT_DIR/../lib/worktree.sh"
source "$WATCHER_SCRIPT_DIR/../lib/hooks.sh"
source "$WATCHER_SCRIPT_DIR/../lib/cleanup-orphans.sh"

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

main() {
    local session_name=""
    local marker=""
    local interval=2
    local cleanup_args=""
    local auto_attach=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --marker)
                marker="$2"
                shift 2
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --cleanup-args)
                cleanup_args="$2"
                shift 2
                ;;
            --no-auto-attach)
                auto_attach=false
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
                if [[ -z "$session_name" ]]; then
                    session_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$session_name" ]]; then
        log_error "Session name is required"
        usage >&2
        exit 1
    fi

    # セッション存在確認
    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        log_error "Session not found: $session_name"
        exit 1
    fi

    # Issue番号を抽出してマーカーを生成
    local issue_number
    issue_number=$(extract_issue_number "$session_name")
    
    if [[ -z "$issue_number" ]]; then
        log_error "Could not extract issue number from session name: $session_name"
        exit 1
    fi
    
    if [[ -z "$marker" ]]; then
        marker="###TASK_COMPLETE_${issue_number}###"
    fi
    
    # エラーマーカーを生成
    local error_marker="###TASK_ERROR_${issue_number}###"

    log_info "Watching session: $session_name"
    log_info "Completion marker: $marker"
    log_info "Error marker: $error_marker"
    log_info "Check interval: ${interval}s"
    log_info "Auto-attach on error: $auto_attach"
    
    # 初期ステータスを保存
    save_status "$issue_number" "running" "$session_name"

    # 初期遅延（プロンプト表示を待つ）
    log_info "Waiting for initial prompt display..."
    sleep 10

    # 初期出力をキャプチャ（ベースライン）
    local baseline_output
    baseline_output=$(tmux capture-pane -t "$session_name" -p -S -1000 2>/dev/null) || baseline_output=""
    
    # 初期化時点でマーカーが既にあるか確認（高速完了タスク対応）
    # Issue #281: 初期化中（10秒待機中）にマーカーが出力された場合の検出
    if echo "$baseline_output" | grep -qF "$error_marker" 2>/dev/null; then
        log_warn "Error marker already present at startup"
        
        # エラーメッセージを抽出
        local error_message
        error_message=$(echo "$baseline_output" | grep -A 1 "$error_marker" | tail -n 1 | head -c 200) || error_message="Unknown error"
        
        handle_error "$session_name" "$issue_number" "$error_message" "$auto_attach"
        log_warn "Error notification sent. Session is still running for manual intervention."
        # エラーの場合は監視を続行（ユーザーが修正する可能性があるため）
    elif echo "$baseline_output" | grep -qF "$marker" 2>/dev/null; then
        log_info "Completion marker already present at startup"
        
        handle_complete "$session_name" "$issue_number"
        
        log_info "Running cleanup..."
        sleep 2
        
        # shellcheck disable=SC2086
        "$WATCHER_SCRIPT_DIR/cleanup.sh" "$session_name" $cleanup_args || {
            log_error "Cleanup failed"
            exit 1
        }
        
        # 古い計画書をローテーション
        log_info "Rotating old plans..."
        "$WATCHER_SCRIPT_DIR/cleanup.sh" --rotate-plans || {
            log_warn "Plan rotation failed (non-critical)"
        }
        
        log_info "Cleanup completed successfully"
        exit 0
    fi
    
    log_info "Starting marker detection..."

    # 監視ループ
    while true; do
        # セッションが存在しなくなったら終了
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            log_info "Session ended: $session_name"
            break
        fi

        # 最新の出力をキャプチャ（最後の100行）
        local output
        output=$(tmux capture-pane -t "$session_name" -p -S -100 2>/dev/null) || {
            log_warn "Failed to capture pane output"
            sleep "$interval"
            continue
        }

        # エラーマーカー検出（完了マーカーより先にチェック）
        local error_count_baseline
        local error_count_current
        error_count_baseline=$(echo "$baseline_output" | grep -cF "$error_marker" 2>/dev/null) || error_count_baseline=0
        error_count_current=$(echo "$output" | grep -cF "$error_marker" 2>/dev/null) || error_count_current=0
        
        if [[ "$error_count_current" -gt "$error_count_baseline" ]]; then
            log_warn "Error marker detected! (baseline: $error_count_baseline, current: $error_count_current)"
            
            # エラーメッセージを抽出（マーカーの次の行）
            local error_message
            error_message=$(echo "$output" | grep -A 1 "$error_marker" | tail -n 1 | head -c 200) || error_message="Unknown error"
            
            # worktreeパスとブランチ名を取得
            local worktree_path=""
            local branch_name=""
            if worktree_path="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
                branch_name="$(get_worktree_branch "$worktree_path" 2>/dev/null)" || branch_name=""
            fi
            
            # ステータスを保存
            save_status "$issue_number" "error" "$session_name" "$error_message"
            
            # on_error hookを実行（hook未設定時はデフォルト動作）
            run_hook "on_error" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "$error_message" "1" ""
            
            # auto_attachが有効な場合はTerminalを開く
            if [[ "$auto_attach" == "true" ]] && is_macos; then
                open_terminal_and_attach "$session_name"
            fi
            
            log_warn "Error notification sent. Session is still running for manual intervention."
            
            # エラー後もセッションは継続するため、ベースラインを更新して監視を続ける
            baseline_output="$output"
        fi
        
        # 完了マーカー検出
        local marker_count_baseline
        local marker_count_current
        marker_count_baseline=$(echo "$baseline_output" | grep -cF "$marker" 2>/dev/null) || marker_count_baseline=0
        marker_count_current=$(echo "$output" | grep -cF "$marker" 2>/dev/null) || marker_count_current=0
        
        if [[ "$marker_count_current" -gt "$marker_count_baseline" ]]; then
            log_info "Completion marker detected! (baseline: $marker_count_baseline, current: $marker_count_current)"
            
            # worktreeパスとブランチ名を取得
            local worktree_path=""
            local branch_name=""
            if worktree_path="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
                branch_name="$(get_worktree_branch "$worktree_path" 2>/dev/null)" || branch_name=""
            fi
            
            # ステータスを保存
            save_status "$issue_number" "complete" "$session_name"
            
            # on_success hookを実行（hook未設定時はデフォルト動作）
            run_hook "on_success" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "" "0" ""
            
            log_info "Running cleanup..."
            
            # 少し待機（AIが出力を完了するまで）
            sleep 2
            
            # cleanup実行（リトライ付き）
            local cleanup_success=false
            local cleanup_attempt=1
            local max_cleanup_attempts=2
            
            while [[ $cleanup_attempt -le $max_cleanup_attempts ]]; do
                log_info "Cleanup attempt $cleanup_attempt/$max_cleanup_attempts..."
                
                # shellcheck disable=SC2086
                if "$WATCHER_SCRIPT_DIR/cleanup.sh" "$session_name" $cleanup_args; then
                    cleanup_success=true
                    break
                else
                    log_warn "Cleanup attempt $cleanup_attempt failed"
                    if [[ $cleanup_attempt -lt $max_cleanup_attempts ]]; then
                        log_info "Retrying in 3 seconds..."
                        sleep 3
                    fi
                fi
                cleanup_attempt=$((cleanup_attempt + 1))
            done
            
            if [[ "$cleanup_success" == "false" ]]; then
                log_error "Cleanup failed after $max_cleanup_attempts attempts"
                
                # orphaned worktreeとしてマーク
                log_warn "This worktree may need manual cleanup. You can run:"
                log_warn "  ./scripts/cleanup.sh --orphan-worktrees --force"
                exit 1
            fi
            
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
            "$WATCHER_SCRIPT_DIR/cleanup.sh" --rotate-plans || {
                log_warn "Plan rotation failed (non-critical)"
            }
            
            log_info "Cleanup completed successfully"
            exit 0
        fi

        sleep "$interval"
    done
}

# handle_complete と handle_error 関数（後方互換性のため）
handle_complete() {
    local session_name="$1"
    local issue_number="$2"
    log_info "Session completed: $session_name (Issue #$issue_number)"
}

handle_error() {
    local session_name="$1"
    local issue_number="$2"
    local error_message="$3"
    local auto_attach="${4:-true}"
    
    log_warn "Session error detected: $session_name (Issue #$issue_number)"
    log_warn "Error: $error_message"
}

main "$@"
