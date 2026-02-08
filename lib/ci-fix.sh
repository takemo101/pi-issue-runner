#!/usr/bin/env bash
# ci-fix.sh - CI失敗検出・自動修正機能（オーケストレーター）
#
# このライブラリはCI失敗を検出して自動修正を試行します。
# 対応する失敗タイプ:
#   - Lint/Clippy: cargo clippy --fix
#   - Format: cargo fmt
#   - Test失敗: AI解析による修正
#   - ビルドエラー: AI解析による修正
#
# 【重要】使用状況について:
#   このファイルは他のスクリプトから直接 source されるのではなく、
#   scripts/ci-fix-helper.sh というラッパースクリプトを介して使用されます。
#   これは意図的な設計で、ライブラリ層とCLIインターフェース層を分離しています。
#
# 使用フロー:
#   agents/ci-fix.md (エージェントテンプレート)
#     → scripts/ci-fix-helper.sh (CLIラッパー)
#       → lib/ci-fix.sh (このオーケストレーター)
#         → lib/ci-fix/*.sh (サブモジュール)
#
# 直接使用する場合:
#   source lib/ci-fix.sh
#   handle_ci_failure 42 123 /path/to/worktree
#
# サブモジュール構成:
#   - lib/ci-fix/detect.sh: プロジェクトタイプ検出
#   - lib/ci-fix/rust.sh: Rust固有の修正・検証ロジック
#   - lib/ci-fix/node.sh: Node固有の修正・検証ロジック
#   - lib/ci-fix/python.sh: Python固有の修正・検証ロジック
#   - lib/ci-fix/go.sh: Go固有の修正・検証ロジック
#   - lib/ci-fix/bash.sh: Bash固有の修正・検証ロジック
#   - lib/ci-fix/common.sh: 共通修正関数（try_auto_fix, try_fix_lint 等）
#   - lib/ci-fix/escalation.sh: エスカレーション処理
#
# 依存モジュール:
#   - lib/log.sh: ログ出力
#   - lib/github.sh: GitHub CLI操作
#   - lib/ci-monitor.sh: CI状態監視
#   - lib/ci-classifier.sh: 失敗タイプ分類
#   - lib/ci-retry.sh: リトライ管理
#
# 関連ファイル:
#   - scripts/ci-fix-helper.sh: このライブラリのCLIラッパー
#   - agents/ci-fix.md: ci-fixエージェントテンプレート
#   - workflows/ci-fix.yaml: ci-fixワークフロー定義

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CI_FIX_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_SH_SOURCED="true"

__CI_FIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存モジュール
source "$__CI_FIX_LIB_DIR/log.sh"
source "$__CI_FIX_LIB_DIR/github.sh"
source "$__CI_FIX_LIB_DIR/ci-monitor.sh"
source "$__CI_FIX_LIB_DIR/ci-classifier.sh"
source "$__CI_FIX_LIB_DIR/ci-retry.sh"

# サブモジュール
source "$__CI_FIX_LIB_DIR/ci-fix/common.sh"
source "$__CI_FIX_LIB_DIR/ci-fix/escalation.sh"

# ===================
# メイン処理
# ===================

# CI失敗を検出して自動修正を試行
# Usage: handle_ci_failure <issue_number> <pr_number> [worktree_path]
# Returns: 0=修正成功・マージ可能, 1=修正失敗・エスカレーション必要, 2=致命的エラー
handle_ci_failure() {
    local issue_number="$1"
    local pr_number="$2"
    local worktree_path="${3:-.}"
    
    log_info "Handling CI failure for Issue #$issue_number, PR #$pr_number"
    
    # リトライ回数チェック
    if ! should_continue_retry "$issue_number"; then
        log_warn "Maximum retries reached. Escalating..."
        escalate_to_manual "$pr_number" "Maximum retry count exceeded"
        return 1
    fi
    
    # リトライ回数をインクリメント
    increment_retry_count "$issue_number"
    
    # 失敗ログを取得
    local failure_log
    failure_log=$(get_failed_ci_logs "$pr_number" || echo "")
    
    if [[ -z "$failure_log" ]]; then
        log_warn "Could not retrieve failure logs"
        escalate_to_manual "$pr_number" "Failed to retrieve CI logs"
        return 1
    fi
    
    # 失敗タイプを分類
    local failure_type
    failure_type=$(classify_ci_failure "$failure_log")
    log_info "Detected failure type: $failure_type"
    
    # 自動修正を試行
    local fix_result
    try_auto_fix "$failure_type" "$worktree_path"
    fix_result=$?
    
    case $fix_result in
        0)
            # 自動修正成功
            log_info "Auto-fix applied successfully"
            
            # ローカル検証
            if run_local_validation "$worktree_path"; then
                return 0
            else
                log_warn "Local validation failed after auto-fix"
                return 1
            fi
            ;;
        2)
            # AI修正が必要
            log_info "Auto-fix not available for this failure type. Requires AI fixing."
            return 1
            ;;
        *)
            # 修正失敗
            log_error "Auto-fix failed"
            return 1
            ;;
    esac
}
