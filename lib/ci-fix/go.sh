#!/usr/bin/env bash
# ci-fix/go.sh - Go固有の修正・検証ロジック

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_GO_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_GO_SH_SOURCED="true"

__CI_FIX_GO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_GO_DIR/log.sh"

# Goプロジェクトのlint修正
# Usage: _fix_lint_go
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_lint_go() {
    # golangci-lintがあれば使用
    if command -v golangci-lint &> /dev/null; then
        log_info "Running golangci-lint run --fix..."
        if golangci-lint run --fix 2>&1; then
            log_info "golangci-lint fix applied successfully"
            return 0
        else
            log_warn "golangci-lint fix failed"
            return 1
        fi
    else
        log_warn "golangci-lint not found. Install from: https://golangci-lint.run/usage/install/"
        return 2  # 自動修正不可
    fi
}

# Goプロジェクトのフォーマット修正
# Usage: _fix_format_go
# Returns: 0=修正成功, 1=修正失敗
_fix_format_go() {
    if ! command -v gofmt &> /dev/null; then
        log_error "gofmt not found. Cannot auto-fix format issues."
        return 1
    fi
    if gofmt -w . 2>&1; then
        log_info "gofmt fix applied successfully"
        return 0
    else
        log_error "gofmt fix failed"
        return 1
    fi
}

# Goプロジェクトの検証
# Usage: _validate_go
# Returns: 0=検証成功, 1=検証失敗
_validate_go() {
    if ! command -v go &> /dev/null; then
        log_warn "go not found. Skipping validation."
        return 0
    fi
    log_info "Running go vet..."
    if ! go vet ./... 2>&1; then
        log_error "Go vet failed"
        return 1
    fi
    log_info "Running go test..."
    if ! go test ./... 2>&1; then
        log_error "Test failed"
        return 1
    fi
    return 0
}
