#!/usr/bin/env bash
# ci-fix/common.sh - 共通修正関数
#
# プロジェクトタイプ検出と各言語固有モジュールを統合し、
# 汎用的なlint修正・フォーマット修正・ローカル検証を提供します。

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_COMMON_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_COMMON_SH_SOURCED="true"

__CI_FIX_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__CI_FIX_COMMON_LIB_DIR="$(cd "$__CI_FIX_COMMON_DIR/.." && pwd)"

source "$__CI_FIX_COMMON_LIB_DIR/log.sh"
source "$__CI_FIX_COMMON_DIR/detect.sh"
source "$__CI_FIX_COMMON_DIR/rust.sh"
source "$__CI_FIX_COMMON_DIR/node.sh"
source "$__CI_FIX_COMMON_DIR/python.sh"
source "$__CI_FIX_COMMON_DIR/go.sh"
source "$__CI_FIX_COMMON_DIR/bash.sh"

# 自動修正を試行
# Usage: try_auto_fix <failure_type> [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_auto_fix() {
    local failure_type="$1"
    local worktree_path="${2:-.}"
    
    log_info "Attempting auto-fix for: $failure_type"
    
    case "$failure_type" in
        "$FAILURE_TYPE_LINT")
            try_fix_lint "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_FORMAT")
            try_fix_format "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_TEST")
            # テスト失敗はAI修正が必要
            log_info "Test failures require AI-based fixing"
            return 2
            ;;
        "$FAILURE_TYPE_BUILD")
            # ビルドエラーはAI修正が必要
            log_info "Build errors require AI-based fixing"
            return 2
            ;;
        *)
            log_warn "Unknown failure type: $failure_type"
            return 2
            ;;
    esac
}

# Lint修正を試行（汎用版）
# Usage: try_fix_lint [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_fix_lint() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix lint issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    log_info "Detected project type: $project_type"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        case "$project_type" in
            rust)   _fix_lint_rust ;;
            node)   _fix_lint_node ;;
            python) _fix_lint_python ;;
            go)     _fix_lint_go ;;
            bash)   _fix_lint_bash ;;
            *)
                log_warn "Unknown project type. Cannot auto-fix lint."
                return 2  # 自動修正不可
                ;;
        esac
    )
}

# フォーマット修正を試行（汎用版）
# Usage: try_fix_format [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_fix_format() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix format issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    log_info "Detected project type: $project_type"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        case "$project_type" in
            rust)   _fix_format_rust ;;
            node)   _fix_format_node ;;
            python) _fix_format_python ;;
            go)     _fix_format_go ;;
            bash)   _fix_format_bash ;;
            *)
                log_warn "Unknown project type. Cannot auto-fix format."
                return 2  # 自動修正不可
                ;;
        esac
    )
}

# ローカル検証を実行
# Usage: run_local_validation [worktree_path]
# Returns: 0=検証成功, 1=検証失敗
run_local_validation() {
    local worktree_path="${1:-.}"
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    log_info "Running local validation for $project_type project..."
    
    (
        cd "$worktree_path" || return 1
        case "$project_type" in
            rust)   _validate_rust ;;
            node)   _validate_node ;;
            python) _validate_python ;;
            go)     _validate_go ;;
            bash)   _validate_bash ;;
            *)
                log_warn "Unknown project type: $project_type. Skipping validation."
                return 0
                ;;
        esac
        log_info "Local validation passed"
        return 0
    )
}
