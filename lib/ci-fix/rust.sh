#!/usr/bin/env bash
# ci-fix/rust.sh - Rust固有の修正・検証ロジック

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_RUST_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_RUST_SH_SOURCED="true"

__CI_FIX_RUST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_RUST_DIR/log.sh"

# Rustプロジェクトのlint修正
# Usage: _fix_lint_rust
# Returns: 0=修正成功, 1=修正失敗
_fix_lint_rust() {
    if ! command -v cargo &> /dev/null; then
        log_error "cargo not found. Cannot auto-fix lint issues."
        return 1
    fi
    if cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features 2>&1; then
        log_info "Clippy fix applied successfully"
        return 0
    else
        log_error "Clippy fix failed"
        return 1
    fi
}

# Rustプロジェクトのフォーマット修正
# Usage: _fix_format_rust
# Returns: 0=修正成功, 1=修正失敗
_fix_format_rust() {
    if ! command -v cargo &> /dev/null; then
        log_error "cargo not found. Cannot auto-fix format issues."
        return 1
    fi
    if cargo fmt --all 2>&1; then
        log_info "Format fix applied successfully"
        return 0
    else
        log_error "Format fix failed"
        return 1
    fi
}

# Rustプロジェクトの検証
# Usage: _validate_rust
# Returns: 0=検証成功, 1=検証失敗
_validate_rust() {
    if ! command -v cargo &> /dev/null; then
        log_warn "cargo not found. Skipping validation."
        return 0
    fi
    log_info "Running cargo clippy..."
    if ! cargo clippy --all-targets --all-features -- -D warnings 2>&1; then
        log_error "Clippy check failed"
        return 1
    fi
    log_info "Running cargo test..."
    if ! cargo test --lib 2>&1; then
        log_error "Test failed"
        return 1
    fi
    return 0
}
