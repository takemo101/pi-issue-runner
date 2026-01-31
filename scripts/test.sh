#!/usr/bin/env bash
# test.sh - テスト一括実行スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../test"

usage() {
    cat << EOF
Usage: $(basename "$0") [options] [pattern]

Options:
    -v, --verbose   詳細ログを表示
    -f, --fail-fast 最初の失敗で終了
    -h, --help      このヘルプを表示

Arguments:
    pattern         テストファイル名のパターン（例: config, workflow）

Examples:
    $(basename "$0")           # 全テスト実行
    $(basename "$0") config    # config_test.sh のみ
    $(basename "$0") -f        # fail-fast モード
EOF
}

main() {
    local fail_fast=false
    local verbose=false
    local pattern="*"

    # 引数パース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            -f|--fail-fast)
                fail_fast=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                pattern="$1"
                shift
                ;;
        esac
    done

    local total=0
    local passed=0
    local failed=0
    local failed_tests=()

    echo "=== Running Tests ==="
    echo ""

    # テストファイルを収集
    local test_files=()
    for test_file in "$TEST_DIR"/${pattern}_test.sh; do
        [[ -f "$test_file" ]] && test_files+=("$test_file")
    done

    # パターンにマッチするファイルがない場合
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No test files matching pattern: ${pattern}_test.sh"
        exit 1
    fi

    for test_file in "${test_files[@]}"; do
        local test_name
        test_name="$(basename "$test_file")"
        ((total++))

        echo "Running: $test_name..."

        if [[ "$verbose" == "true" ]]; then
            if bash "$test_file"; then
                ((passed++))
                echo "✓ $test_name passed"
            else
                ((failed++))
                failed_tests+=("$test_name")
                echo "✗ $test_name failed"
                if [[ "$fail_fast" == "true" ]]; then
                    echo ""
                    echo "Stopping due to --fail-fast"
                    break
                fi
            fi
            echo ""
        else
            # 非verboseモードでは出力を抑制
            if bash "$test_file" > /dev/null 2>&1; then
                ((passed++))
                echo "✓ $test_name passed"
            else
                ((failed++))
                failed_tests+=("$test_name")
                echo "✗ $test_name failed"
                if [[ "$fail_fast" == "true" ]]; then
                    echo ""
                    echo "Stopping due to --fail-fast"
                    break
                fi
            fi
        fi
    done

    # サマリー表示
    echo ""
    echo "==================="
    echo "Total:  $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo "==================="

    # 失敗したテストの一覧
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        echo ""
        echo "Failed tests:"
        for test_name in "${failed_tests[@]}"; do
            echo "  - $test_name"
        done
    fi

    # 終了コード: 失敗数（最大255）
    if [[ $failed -gt 255 ]]; then
        exit 255
    fi
    exit "$failed"
}

main "$@"
