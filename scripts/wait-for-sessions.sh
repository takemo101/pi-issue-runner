#!/usr/bin/env bash
set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# lib/log.sh を読み込み
# shellcheck source=../lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

# lib/config.sh を読み込み
# shellcheck source=../lib/config.sh
source "$PROJECT_ROOT/lib/config.sh"

# lib/status.sh を読み込み
# shellcheck source=../lib/status.sh
source "$PROJECT_ROOT/lib/status.sh"

show_usage() {
    cat << 'EOF'
Usage: wait-for-sessions.sh [OPTIONS] ISSUE_NUMBER...

Wait for multiple issue sessions to complete.

Arguments:
  ISSUE_NUMBER...    One or more issue numbers to wait for

Options:
  --help             Show this help message
  --timeout SECONDS  Maximum time to wait (default: 3600)
  --interval SECONDS Check interval (default: 5)
  --fail-fast        Exit immediately on first error
  --cleanup          Automatically cleanup completed sessions
  --quiet            Suppress progress output

Exit codes:
  0  All sessions completed successfully
  1  One or more sessions failed
  2  Timeout reached
  3  Invalid arguments

Examples:
  wait-for-sessions.sh 42
  wait-for-sessions.sh 42 43 44 --timeout 600
  wait-for-sessions.sh 42 43 --fail-fast --cleanup
EOF
}

# デフォルト値
TIMEOUT=3600
INTERVAL=5
FAIL_FAST=false
CLEANUP=false
QUIET=false
declare -a ISSUE_NUMBERS=()

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --fail-fast)
            FAIL_FAST=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 3
            ;;
        *)
            # Issue番号の検証
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                ISSUE_NUMBERS+=("$1")
            else
                log_error "Invalid issue number: $1"
                exit 3
            fi
            shift
            ;;
    esac
done

# Issue番号が指定されていない場合はエラー
if [[ ${#ISSUE_NUMBERS[@]} -eq 0 ]]; then
    log_error "At least one issue number is required"
    exit 3
fi

# 設定読み込み
load_config_if_exists

# Worktree ベースディレクトリの取得
WORKTREE_BASE_DIR="${PI_RUNNER_WORKTREE_BASE_DIR:-$(get_config worktree_base_dir)}"
STATUS_DIR="$WORKTREE_BASE_DIR/.status"

[[ "$QUIET" == "false" ]] && log_info "Waiting for ${#ISSUE_NUMBERS[@]} session(s) to complete..."
[[ "$CLEANUP" == "true" ]] && [[ "$QUIET" == "false" ]] && log_info "Auto-cleanup enabled"

elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
    all_done=true
    has_error=false
    
    for issue in "${ISSUE_NUMBERS[@]}"; do
        status_file="$STATUS_DIR/${issue}.json"
        
        # ステータスファイルが存在しない場合
        if [[ ! -f "$status_file" ]]; then
            # セッションも存在しない場合は完了とみなす
            session_name="pi-issue-$issue"
            if command -v tmux &>/dev/null && tmux has-session -t "$session_name" 2>/dev/null; then
                all_done=false
                continue
            fi
            # セッションがない場合は完了
            continue
        fi
        
        # ステータスを確認
        status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
        
        case "$status" in
            complete)
                # 完了済み
                if [[ "$CLEANUP" == "true" ]]; then
                    [[ "$QUIET" == "false" ]] && log_info "Cleaning up worktree for issue #$issue..."
                    "$PROJECT_ROOT/scripts/cleanup.sh" "$issue" --quiet 2>/dev/null || true
                fi
                ;;
            error)
                has_error=true
                [[ "$QUIET" == "false" ]] && log_warn "Session #$issue has error status"
                if [[ "$FAIL_FAST" == "true" ]]; then
                    exit 1
                fi
                ;;
            running|unknown)
                all_done=false
                ;;
        esac
    done
    
    # すべて完了した場合
    if [[ "$all_done" == "true" ]]; then
        if [[ "$has_error" == "true" ]]; then
            exit 1
        else
            [[ "$QUIET" == "false" ]] && log_info "All sessions completed successfully"
            exit 0
        fi
    fi
    
    [[ "$QUIET" == "false" ]] && log_info "Still waiting... ($elapsed/$TIMEOUT seconds elapsed)"
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
done

# タイムアウト
[[ "$QUIET" == "false" ]] && log_warn "Timeout reached after $TIMEOUT seconds"
exit 2
