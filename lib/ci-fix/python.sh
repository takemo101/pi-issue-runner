#!/usr/bin/env bash
# ci-fix/python.sh - Python固有の修正・検証ロジック

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_PYTHON_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_PYTHON_SH_SOURCED="true"

__CI_FIX_PYTHON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_PYTHON_DIR/log.sh"

# Pythonプロジェクトのlint修正
# Usage: _fix_lint_python
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_lint_python() {
    # autopep8で自動修正を試行
    if command -v autopep8 &> /dev/null; then
        log_info "Running autopep8..."
        if autopep8 --in-place --aggressive --aggressive --recursive . 2>&1; then
            log_info "autopep8 fix applied successfully"
            return 0
        else
            log_error "autopep8 fix failed"
            return 1
        fi
    else
        log_warn "autopep8 not found. Install with: pip install autopep8"
        return 2  # 自動修正不可
    fi
}

# Pythonプロジェクトのフォーマット修正
# Usage: _fix_format_python
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
_fix_format_python() {
    # blackを優先、なければautopep8
    if command -v black &> /dev/null; then
        log_info "Running black..."
        if black . 2>&1; then
            log_info "black fix applied successfully"
            return 0
        else
            log_error "black fix failed"
            return 1
        fi
    elif command -v autopep8 &> /dev/null; then
        log_info "Running autopep8..."
        if autopep8 --in-place --recursive . 2>&1; then
            log_info "autopep8 fix applied successfully"
            return 0
        else
            log_error "autopep8 fix failed"
            return 1
        fi
    else
        log_warn "No formatter found for Python project (black or autopep8)"
        return 2  # 自動修正不可
    fi
}

# Pythonプロジェクトの検証
# Usage: _validate_python
# Returns: 0=検証成功, 1=検証失敗
_validate_python() {
    if command -v flake8 &>/dev/null; then
        log_info "Running flake8..."
        if ! flake8 . 2>&1; then
            log_error "Flake8 check failed"
            return 1
        fi
    fi
    if command -v pytest &>/dev/null; then
        log_info "Running pytest..."
        if ! pytest --tb=short 2>&1; then
            log_error "Test failed"
            return 1
        fi
    fi
    return 0
}
