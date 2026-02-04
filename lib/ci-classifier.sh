#!/usr/bin/env bash
# ci-classifier.sh - CI失敗タイプ分類機能
#
# このライブラリはCI失敗ログの取得とタイプ分類を提供します。

set -euo pipefail

_CI_CLASSIFIER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CI_CLASSIFIER_LIB_DIR/log.sh"

# ===================
# 定数定義
# ===================

# 失敗タイプ定数
FAILURE_TYPE_LINT="lint"
FAILURE_TYPE_FORMAT="format"
FAILURE_TYPE_TEST="test"
FAILURE_TYPE_BUILD="build"
FAILURE_TYPE_UNKNOWN="unknown"

# ===================
# 失敗ログ取得・分析
# ===================

# 失敗したCIのログを取得
# Usage: get_failed_ci_logs <pr_number>
get_failed_ci_logs() {
    local pr_number="$1"
    
    log_info "Fetching failed CI logs for PR #$pr_number"
    
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI not found"
        return 1
    fi
    
    # 最新の失敗したワークフロー実行を取得
    local run_id
    run_id=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
    
    if [[ -z "$run_id" ]]; then
        log_warn "No failed runs found"
        return 1
    fi
    
    # 失敗したジョブのログを取得
    gh run view "$run_id" --log-failed 2>/dev/null || echo ""
}

# CI失敗タイプを分類
# Usage: classify_ci_failure <log_content>
# Returns: lint | format | test | build | unknown
classify_ci_failure() {
    local log_content="$1"
    
    # フォーマットエラーをチェック（最も具体的なので先に）
    if echo "$log_content" | grep -qE '(Diff in|would have been reformatted|fmt check failed)'; then
        echo "$FAILURE_TYPE_FORMAT"
        return 0
    fi
    
    # Lint/Clippyエラーをチェック
    if echo "$log_content" | grep -qE '(warning:|clippy::|error: could not compile.*clippy)'; then
        echo "$FAILURE_TYPE_LINT"
        return 0
    fi
    
    # テスト失敗をチェック
    if echo "$log_content" | grep -qE '(FAILED|test result: FAILED|failures:)'; then
        echo "$FAILURE_TYPE_TEST"
        return 0
    fi
    
    # ビルドエラーをチェック
    if echo "$log_content" | grep -qE '(error\[E|cannot find|unresolved import|expected.*found)'; then
        echo "$FAILURE_TYPE_BUILD"
        return 0
    fi
    
    echo "$FAILURE_TYPE_UNKNOWN"
}
