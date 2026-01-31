#!/usr/bin/env bash
# test.sh - テスト一括実行スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../test"

usage() {
    cat << EOF
Usage: $(basename "$0") [options] [target]

Options:
    -v, --verbose   詳細ログを表示
    -f, --fail-fast 最初の失敗で終了
    -l, --legacy    旧形式テスト（*_test.sh）も実行
    -h, --help      このヘルプを表示

Target:
    lib             test/lib/*.bats のみ実行
    scripts         test/scripts/*.bats のみ実行
    (default)       全Batsテストを実行

Examples:
    $(basename "$0")             # 全Batsテスト実行
    $(basename "$0") lib         # test/lib/*.bats のみ
    $(basename "$0") -v          # 詳細ログ付き
    $(basename "$0") -f          # fail-fast モード
    $(basename "$0") -l          # 旧形式テストも含む
EOF
}

check_bats() {
    if ! command -v bats &> /dev/null; then
        echo "Error: bats is not installed" >&2
        echo "Install with: brew install bats-core" >&2
        return 1
    fi
}

run_bats_tests() {
    local verbose="$1"
    local fail_fast="$2"
    local target="$3"
    
    local bats_args=()
    
    if [[ "$verbose" == "true" ]]; then
        bats_args+=(--tap)
    fi
    
    # Determine which test files to run
    local test_files=()
    case "$target" in
        lib)
            test_files=("$TEST_DIR"/lib/*.bats)
            ;;
        scripts)
            test_files=("$TEST_DIR"/scripts/*.bats)
            ;;
        *)
            test_files=("$TEST_DIR"/lib/*.bats "$TEST_DIR"/scripts/*.bats)
            ;;
    esac
    
    # Filter to existing files only
    local existing_files=()
    for f in "${test_files[@]}"; do
        [[ -f "$f" ]] && existing_files+=("$f")
    done
    
    if [[ ${#existing_files[@]} -eq 0 ]]; then
        echo "No Bats test files found for target: $target"
        return 1
    fi
    
    echo "=== Running Bats Tests ==="
    echo ""
    
    if [[ "$fail_fast" == "true" ]]; then
        # Run tests one by one for fail-fast
        for test_file in "${existing_files[@]}"; do
            echo "Running: $(basename "$test_file")..."
            if [[ ${#bats_args[@]} -gt 0 ]]; then
                if ! bats "${bats_args[@]}" "$test_file"; then
                    echo ""
                    echo "Stopping due to --fail-fast"
                    return 1
                fi
            else
                if ! bats "$test_file"; then
                    echo ""
                    echo "Stopping due to --fail-fast"
                    return 1
                fi
            fi
        done
    else
        if [[ ${#bats_args[@]} -gt 0 ]]; then
            bats "${bats_args[@]}" "${existing_files[@]}"
        else
            bats "${existing_files[@]}"
        fi
    fi
}

run_legacy_tests() {
    local verbose="$1"
    local fail_fast="$2"
    
    local total=0
    local passed=0
    local failed=0
    local failed_tests=()
    
    echo ""
    echo "=== Running Legacy Tests ==="
    echo ""
    
    for test_file in "$TEST_DIR"/*_test.sh; do
        [[ -f "$test_file" ]] || continue
        
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
    
    if [[ $total -eq 0 ]]; then
        echo "No legacy test files found"
        return 0
    fi
    
    echo ""
    echo "Legacy Test Results:"
    echo "==================="
    echo "Total:  $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo "==================="
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        echo ""
        echo "Failed tests:"
        for test_name in "${failed_tests[@]}"; do
            echo "  - $test_name"
        done
    fi
    
    return "$failed"
}

main() {
    local fail_fast=false
    local verbose=false
    local legacy=false
    local target=""
    
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
            -l|--legacy)
                legacy=true
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
                target="$1"
                shift
                ;;
        esac
    done
    
    local exit_code=0
    
    # Run Bats tests
    if check_bats; then
        if ! run_bats_tests "$verbose" "$fail_fast" "$target"; then
            exit_code=1
            if [[ "$fail_fast" == "true" ]]; then
                exit "$exit_code"
            fi
        fi
    else
        echo "Skipping Bats tests (bats not installed)"
        exit_code=1
    fi
    
    # Run legacy tests if requested
    if [[ "$legacy" == "true" ]]; then
        local legacy_result=0
        run_legacy_tests "$verbose" "$fail_fast" || legacy_result=$?
        if [[ $legacy_result -gt 0 ]]; then
            exit_code=$legacy_result
        fi
    fi
    
    exit "$exit_code"
}

main "$@"
