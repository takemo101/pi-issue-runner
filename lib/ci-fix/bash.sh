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
        local sh_files_arr=()
        while IFS= read -r -d "" f; do
            sh_files_arr+=("$f")
        done < <(find . -maxdepth 3 -name "*.sh" -not -path "./.git/*" -not -path "./node_modules/*" -print0 2>/dev/null || true)
        if [[ ${#sh_files_arr[@]} -eq 0 ]]; then
            log_warn "No .sh files found for shfmt"
            return 2  # 自動修正不可
        fi
        local file_count=${#sh_files_arr[@]}
        log_info "Running shfmt on ${file_count} files..."
        # shfmt はデフォルトで .editorconfig を参照する
        # -i オプションを指定しないことで、プロジェクト固有の設定を尊重
        if shfmt -w "${sh_files_arr[@]}" 2>&1; then
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
        local sh_files_arr=()
        while IFS= read -r -d "" f; do
            sh_files_arr+=("$f")
        done < <(find . -maxdepth 3 -name "*.sh" -not -path "./.git/*" -not -path "./node_modules/*" -print0 2>/dev/null || true)
        if [[ ${#sh_files_arr[@]} -gt 0 ]]; then
            local file_count=${#sh_files_arr[@]}
            log_info "Running shellcheck on ${file_count} files..."
            if ! shellcheck -x "${sh_files_arr[@]}" 2>&1; then
                log_error "ShellCheck failed"
                return 1
            fi
        else
            log_warn "No .sh files found for shellcheck, skipping"
        fi
    fi
    if command -v bats &>/dev/null; then
        # test/ または tests/ ディレクトリが存在する場合のみ実行
        local test_dir=""
        if [[ -d "test" ]]; then
            test_dir="test"
        elif [[ -d "tests" ]]; then
            test_dir="tests"
        fi
        if [[ -n "$test_dir" ]]; then
            log_info "Running bats in $test_dir/..."
            if ! bats "$test_dir/" 2>&1; then
                log_error "Bats test failed"
                return 1
            fi
        else
            log_warn "No test directory found for bats"
        fi
    fi
    return 0
}
