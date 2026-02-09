#!/usr/bin/env bash
# ci-fix/bash.sh - Bash固有の修正・検証ロジック

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_BASH_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_BASH_SH_SOURCED="true"

__CI_FIX_BASH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_BASH_DIR/log.sh"

# Bashプロジェクトのlint修正
# Usage: _fix_lint_bash
# Returns: 2=自動修正不可（ShellCheckは自動修正をサポートしない）
_fix_lint_bash() {
    # ShellCheckは自動修正をサポートしていない
    log_warn "Bash linting (shellcheck) does not support auto-fix"
    return 2  # 自動修正不可
}

# Bashプロジェクトのフォーマット修正
# Usage: _fix_format_bash
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_format_bash() {
    # shfmtがあれば使用
    if command -v shfmt &> /dev/null; then
        log_info "Running shfmt..."
        # shfmt はデフォルトで .editorconfig を参照する
        # -i オプションを指定しないことで、プロジェクト固有の設定を尊重
        if shfmt -w . 2>&1; then
            log_info "shfmt fix applied successfully"
            return 0
        else
            log_error "shfmt fix failed"
            return 1
        fi
    else
        log_warn "shfmt not found. Install from: https://github.com/mvdan/sh"
        return 2  # 自動修正不可
    fi
}

# Bashプロジェクトの検証
# Usage: _validate_bash
# Returns: 0=検証成功, 1=検証失敗
_validate_bash() {
    if command -v shellcheck &>/dev/null; then
        log_info "Running shellcheck..."
        if ! shellcheck -x scripts/*.sh lib/*.sh 2>&1; then
            log_error "ShellCheck failed"
            return 1
        fi
    fi
    if command -v bats &>/dev/null; then
        log_info "Running bats..."
        if ! bats test/ 2>&1; then
            log_error "Bats test failed"
            return 1
        fi
    fi
    return 0
}
