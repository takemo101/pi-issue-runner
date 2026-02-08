#!/usr/bin/env bash
# ci-fix/node.sh - Node/JavaScript固有の修正・検証ロジック

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_NODE_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_NODE_SH_SOURCED="true"

__CI_FIX_NODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_NODE_DIR/log.sh"

# Nodeプロジェクトのlint修正
# Usage: _fix_lint_node
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_lint_node() {
    # npm scriptsにlint:fixがあればそれを使用、なければeslintを試行
    if grep -q '"lint:fix"' package.json 2>/dev/null; then
        log_info "Running npm run lint:fix..."
        if npm run lint:fix 2>&1; then
            log_info "Lint fix applied successfully"
            return 0
        else
            log_warn "npm run lint:fix failed"
            return 1
        fi
    elif command -v npx &> /dev/null; then
        log_info "Trying npx eslint --fix..."
        if npx eslint --fix . 2>&1; then
            log_info "ESLint fix applied successfully"
            return 0
        else
            log_warn "ESLint fix failed or not configured"
            return 2  # 自動修正不可
        fi
    else
        log_warn "No linter found for Node project"
        return 2  # 自動修正不可
    fi
}

# Nodeプロジェクトのフォーマット修正
# Usage: _fix_format_node
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_format_node() {
    # npm scriptsにformatがあればそれを使用、なければprettierを試行
    if grep -q '"format"' package.json 2>/dev/null; then
        log_info "Running npm run format..."
        if npm run format 2>&1; then
            log_info "Format fix applied successfully"
            return 0
        else
            log_warn "npm run format failed"
            return 1
        fi
    elif command -v npx &> /dev/null; then
        log_info "Trying npx prettier --write..."
        if npx prettier --write . 2>&1; then
            log_info "Prettier fix applied successfully"
            return 0
        else
            log_warn "Prettier fix failed or not configured"
            return 2  # 自動修正不可
        fi
    else
        log_warn "No formatter found for Node project"
        return 2  # 自動修正不可
    fi
}

# Nodeプロジェクトの検証
# Usage: _validate_node
# Returns: 0=検証成功, 1=検証失敗
_validate_node() {
    # Check if lint script exists in package.json scripts section
    if command -v jq &>/dev/null; then
        if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
            log_info "Running npm run lint..."
            if ! npm run lint 2>&1; then
                log_error "Lint check failed"
                return 1
            fi
        fi
        if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
            log_info "Running npm test..."
            if ! npm test 2>&1; then
                log_error "Test failed"
                return 1
            fi
        fi
    else
        # Fallback: check if package.json contains "lint" or "test" script keys
        if grep -q '"lint"' package.json 2>/dev/null; then
            log_info "Running npm run lint..."
            if ! npm run lint 2>&1; then
                log_error "Lint check failed"
                return 1
            fi
        fi
        if grep -q '"test"' package.json 2>/dev/null; then
            log_info "Running npm test..."
            if ! npm test 2>&1; then
                log_error "Test failed"
                return 1
            fi
        fi
    fi
    return 0
}
