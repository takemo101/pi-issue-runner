#!/usr/bin/env bash
# ============================================================================
# test.sh - Test runner script
#
# Runs all tests including Bats tests and ShellCheck static analysis.
# Supports parallel execution, verbose output, and fail-fast mode.
#
# Usage: ./scripts/test.sh [options] [target]
#
# Options:
#   -v, --verbose     Show verbose logs
#   -f, --fail-fast   Stop on first failure
#   -s, --shellcheck  Run ShellCheck only
#   -a, --all         Run all checks (bats + shellcheck)
#   -j, --jobs N      Number of parallel jobs (default: 4)
#   --fast            Fast mode (skip heavy tests)
#   -h, --help        Show help message
#
# Target:
#   lib               Run test/lib/*.bats only
#   scripts           Run test/scripts/*.bats only
#   regression        Run test/regression/*.bats only
#   (default)         Run all Bats tests
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#
# Examples:
#   ./scripts/test.sh
#   ./scripts/test.sh lib
#   ./scripts/test.sh -v
#   ./scripts/test.sh -f
#   ./scripts/test.sh -s
#   ./scripts/test.sh -a
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
TEST_DIR="$SCRIPT_DIR/../test"

usage() {
    cat << EOF
Usage: $(basename "$0") [options] [target]

Options:
    -v, --verbose     詳細ログを表示
    -f, --fail-fast   最初の失敗で終了
    -s, --shellcheck  ShellCheckを実行
    -a, --all         全てのチェック（bats + shellcheck）を実行
    -j, --jobs N      並列実行のジョブ数（デフォルト: 4）
    --fast            高速モード（重いテストをスキップ）
    -h, --help        このヘルプを表示

Target:
    lib               test/lib/*.bats のみ実行
    scripts           test/scripts/*.bats のみ実行
    regression        test/regression/*.bats のみ実行
    skills            test/skills/**/*.bats のみ実行
    (default)         全Batsテストを実行

Environment:
    BATS_JOBS         並列実行のジョブ数（デフォルト: 4）
    BATS_FAST_MODE    1=高速モード有効

Examples:
    $(basename "$0")             # 全Batsテスト実行
    $(basename "$0") lib         # test/lib/*.bats のみ
    $(basename "$0") -v          # 詳細ログ付き
    $(basename "$0") -f          # fail-fast モード
    $(basename "$0") -s          # ShellCheckのみ実行
    $(basename "$0") -a          # Batsテスト + ShellCheck
EOF
}

check_bats() {
    if ! command -v bats &> /dev/null; then
        echo "Error: bats is not installed" >&2
        echo "Install with: brew install bats-core" >&2
        return 1
    fi
}

check_shellcheck() {
    if ! command -v shellcheck &> /dev/null; then
        echo "Warning: shellcheck is not installed" >&2
        echo "Install with: brew install shellcheck" >&2
        return 1
    fi
}

run_shellcheck() {
    local verbose="$1"
    
    echo "=== Running ShellCheck ==="
    echo ""
    
    if ! check_shellcheck; then
        echo "Skipping ShellCheck (not installed)"
        return 1
    fi
    
    local script_files=()
    local lib_files=()
    
    # Collect script files
    for f in "$PROJECT_ROOT"/scripts/*.sh; do
        [[ -f "$f" ]] && script_files+=("$f")
    done
    
    # Collect lib files (including subdirectories)
    while IFS= read -r f; do
        lib_files+=("$f")
    done < <(find "$PROJECT_ROOT/lib" -name "*.sh" -type f | sort)
    
    local all_files=("${script_files[@]}" "${lib_files[@]}")
    
    if [[ ${#all_files[@]} -eq 0 ]]; then
        echo "No shell scripts found"
        return 0
    fi
    
    echo "Checking ${#all_files[@]} files..."
    echo ""
    
    local shellcheck_args=(-x)  # Follow sourced files
    
    if [[ "$verbose" == "true" ]]; then
        shellcheck_args+=(-f gcc)  # GCC-style output for verbose
    fi
    
    if shellcheck "${shellcheck_args[@]}" "${all_files[@]}"; then
        echo ""
        echo "✓ ShellCheck passed: ${#all_files[@]} files checked"
        return 0
    else
        echo ""
        echo "✗ ShellCheck found issues"
        return 1
    fi
}

run_bats_tests() {
    local verbose="$1"
    local fail_fast="$2"
    local target="$3"
    local jobs="$4"
    local fast_mode="$5"
    
    local bats_args=()
    
    if [[ "$verbose" == "true" ]]; then
        bats_args+=(--tap)
    fi
    
    # 並列実行の設定
    if [[ "$jobs" -gt 1 && "$fail_fast" != "true" ]]; then
        bats_args+=(--jobs "$jobs")
    fi
    
    # Determine which test directories to run
    # ディレクトリ単位で順次実行（大量ファイル一括実行のハング回避）
    local targets=()
    case "$target" in
        lib)
            targets=("lib")
            ;;
        scripts)
            targets=("scripts")
            ;;
        regression)
            targets=("regression")
            ;;
        skills)
            targets=("skills")
            ;;
        *)
            targets=("lib" "scripts" "regression" "skills")
            ;;
    esac
    
    echo "=== Running Bats Tests ==="
    echo ""
    
    local overall_exit=0
    
    for dir_target in "${targets[@]}"; do
        local test_files=()
        case "$dir_target" in
            lib)
                # lib直下 + lib/improve/ のサブディレクトリ
                for f in "$TEST_DIR"/lib/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                for f in "$TEST_DIR"/lib/improve/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                for f in "$TEST_DIR"/lib/ci-fix/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                ;;
            scripts)
                for f in "$TEST_DIR"/scripts/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                ;;
            regression)
                for f in "$TEST_DIR"/regression/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                ;;
            skills)
                for f in "$TEST_DIR"/skills/**/*.bats; do [[ -f "$f" ]] && test_files+=("$f"); done
                ;;
        esac
        
        if [[ ${#test_files[@]} -eq 0 ]]; then
            continue
        fi
        
        echo "--- Running $dir_target tests (${#test_files[@]} files) ---"
        
        if [[ "$fail_fast" == "true" ]]; then
            # Run tests one by one for fail-fast
            for test_file in "${test_files[@]}"; do
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
                if ! bats "${bats_args[@]}" "${test_files[@]}"; then
                    overall_exit=1
                fi
            else
                if ! bats "${test_files[@]}"; then
                    overall_exit=1
                fi
            fi
        fi
        
        echo ""
    done
    
    return "$overall_exit"
}

main() {
    local fail_fast=false
    local verbose=false
    local shellcheck_only=false
    local run_all=false
    local fast_mode=false
    local jobs="${BATS_JOBS:-4}"
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
            -s|--shellcheck)
                shellcheck_only=true
                shift
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            --fast)
                fast_mode=true
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
    
    # 環境変数で高速モードを有効化
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        fast_mode=true
    fi
    
    local exit_code=0
    
    # ShellCheck only mode
    if [[ "$shellcheck_only" == "true" ]]; then
        if ! run_shellcheck "$verbose"; then
            exit 1
        fi
        exit 0
    fi
    
    # Run all checks mode
    if [[ "$run_all" == "true" ]]; then
        # Run ShellCheck first
        if ! run_shellcheck "$verbose"; then
            exit_code=1
            if [[ "$fail_fast" == "true" ]]; then
                exit "$exit_code"
            fi
        fi
        echo ""
    fi
    
    # Run Bats tests
    if check_bats; then
        # 並列実行情報を表示
        if [[ "$jobs" -gt 1 && "$fail_fast" != "true" ]]; then
            echo "Running tests in parallel with $jobs jobs..."
        fi
        if [[ "$fast_mode" == "true" ]]; then
            echo "Fast mode enabled: skipping heavy tests..."
            export BATS_FAST_MODE=1
        fi
        
        if ! run_bats_tests "$verbose" "$fail_fast" "$target" "$jobs" "$fast_mode"; then
            exit_code=1
        fi
    else
        echo "Skipping Bats tests (bats not installed)"
        exit_code=1
    fi
    
    exit "$exit_code"
}

main "$@"
