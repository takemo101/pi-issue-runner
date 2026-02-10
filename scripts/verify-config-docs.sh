#!/usr/bin/env bash
# ============================================================================
# verify-config-docs.sh - docs/configuration.mdとlib/config.shの整合性検証
#
# 設定ファイル（lib/config.sh）とドキュメント（docs/configuration.md）の
# 整合性を検証し、差異を報告します。
#
# Usage: ./scripts/verify-config-docs.sh [options]
#
# Options:
#   -h, --help     Show this help message
#   -v, --verbose  Show verbose output
#
# Exit codes:
#   0 - All checks passed
#   1 - Mismatch detected
#
# Examples:
#   ./scripts/verify-config-docs.sh
#   ./scripts/verify-config-docs.sh --help
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/log.sh"

# lib/config.shからCONFIG_*変数を抽出
extract_config_vars() {
    grep -E "^CONFIG_[A-Z_]+=" "$PROJECT_ROOT/lib/config.sh" | \
        sed -E 's/^CONFIG_([A-Z_]+)=.*/\1/' | \
        sort
}

# docs/configuration.mdから環境変数を抽出
extract_doc_vars() {
    grep -E "^\| \`PI_RUNNER_[A-Z_]+\`" "$PROJECT_ROOT/docs/configuration.md" | \
        sed -E 's/^\| `PI_RUNNER_([A-Z_]+)`.*/\1/' | \
        sort
}

# デフォルト値を抽出
extract_default_value() {
    local var_name="$1"
    grep -E "^CONFIG_${var_name}=" "$PROJECT_ROOT/lib/config.sh" | \
        sed -E 's/^[^=]+="\$\{[^}]+:-([^}]*)\}".*/\1/' | \
        sed -E 's/^[^=]+="([^"]*)".*/\1/'
}

# Check configuration items exist in both config.sh and documentation
# Returns: 0 if all items match, 1 if mismatch detected
check_config_items() {
    echo "1. Checking configuration items..."
    local config_vars
    local doc_vars

    config_vars=$(extract_config_vars)
    doc_vars=$(extract_doc_vars)

    local config_count
    local doc_count
    config_count=$(echo "$config_vars" | wc -l | tr -d ' ')
    doc_count=$(echo "$doc_vars" | wc -l | tr -d ' ')

    echo "   - lib/config.sh: $config_count items"
    echo "   - docs/configuration.md: $doc_count items"

    if [[ "$config_vars" == "$doc_vars" ]]; then
        log_info "All configuration items are documented"
        return 0
    else
        log_error "Configuration mismatch detected:"
        echo ""
        echo "Missing in documentation:"
        comm -23 <(echo "$config_vars") <(echo "$doc_vars") | sed 's/^/  - PI_RUNNER_/'
        echo ""
        echo "Extra in documentation:"
        comm -13 <(echo "$config_vars") <(echo "$doc_vars") | sed 's/^/  - PI_RUNNER_/'
        return 1
    fi
}

# Check sample default values match between config.sh and documentation
# Returns: 0 if all match, 1 if mismatch detected
check_default_values() {
    echo "2. Checking default values (sample)..."

    local sample_vars=(
        "WORKTREE_BASE_DIR:.worktrees"
        "MULTIPLEXER_SESSION_PREFIX:pi"
        "PARALLEL_MAX_CONCURRENT:0"
        "PLANS_KEEP_RECENT:10"
    )

    local has_error=false
    local value
    local expected
    for item in "${sample_vars[@]}"; do
        local var_name="${item%%:*}"
        expected="${item#*:}"
        value=$(extract_default_value "$var_name")

        if [[ "$value" == "$expected" ]]; then
            log_info "CONFIG_${var_name} = \"${value}\""
        else
            log_error "CONFIG_${var_name}: expected \"${expected}\", got \"${value}\""
            has_error=true
        fi
    done

    [[ "$has_error" == "false" ]]
}

# Check document structure has expected sections
# Returns: always 0 (warnings only)
check_document_structure() {
    echo "3. Checking document structure..."

    local sections=(
        "worktree"
        "multiplexer"
        "pi"
        "agent"
        "parallel"
        "plans"
        "improve"
        "agents"
        "github"
        "watcher"
        "auto"
        "workflow"
        "workflows"
    )

    for section in "${sections[@]}"; do
        if grep -q "### $section" "$PROJECT_ROOT/docs/configuration.md"; then
            log_info "Section \"$section\" found"
        else
            log_warn "Section \"$section\" not found (may use different heading)"
        fi
    done
}

# Check hooks configuration documentation
# Returns: 0 if all hooks documented, 1 if missing
check_hooks_config() {
    echo "4. Checking hooks configuration..."

    local has_error=false

    # hooks.mdまたはconfiguration.mdの存在確認
    local hooks_doc=""
    if [[ -f "$PROJECT_ROOT/docs/hooks.md" ]]; then
        hooks_doc="$PROJECT_ROOT/docs/hooks.md"
        log_info "docs/hooks.md exists"
    elif grep -q "### hooks" "$PROJECT_ROOT/docs/configuration.md" 2>/dev/null; then
        hooks_doc="$PROJECT_ROOT/docs/configuration.md"
        log_info "hooks section exists in docs/configuration.md"
    else
        log_error "Neither docs/hooks.md nor hooks section in docs/configuration.md exists"
        return 1
    fi

    # サポートされているイベントの確認
    local hook_events=(
        "on_start"
        "on_success"
        "on_error"
        "on_cleanup"
        "on_improve_start"
        "on_improve_end"
        "on_iteration_start"
        "on_iteration_end"
        "on_review_complete"
    )

    for event in "${hook_events[@]}"; do
        if grep -q "\`$event\`" "$hooks_doc" 2>/dev/null; then
            log_info "Hook event \"$event\" is documented"
        else
            log_error "Hook event \"$event\" is not documented"
            has_error=true
        fi
    done

    # 設定例の確認
    if grep -q "^hooks:" "$hooks_doc" 2>/dev/null; then
        log_info "Hooks configuration example found"
    else
        log_warn "Hooks configuration example not found (recommended)"
    fi

    [[ "$has_error" == "false" ]]
}

# メイン処理
main() {
    echo "=== Configuration Documentation Verification ==="
    echo ""

    local exit_code=0

    check_config_items || exit_code=1
    echo ""

    check_default_values || exit_code=1
    echo ""

    check_document_structure
    echo ""

    check_hooks_config || exit_code=1
    echo ""

    # 結果サマリー
    if [[ $exit_code -eq 0 ]]; then
        log_info "✅ Configuration documentation is up-to-date"
    else
        log_error "❌ Configuration documentation needs update"
    fi

    return $exit_code
}

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Verify consistency between lib/config.sh and docs/configuration.md

OPTIONS:
    -h, --help     Show this help message
    -v, --verbose  Show verbose output

EXAMPLES:
    # Run verification
    $0

    # Run with verbose output
    $0 --verbose

EXIT CODES:
    0  All checks passed
    1  Configuration mismatch detected
EOF
}

# 引数パース
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# verbose mode は将来の拡張用に予約（現在は使用していない）
if [[ "$VERBOSE" == "true" ]]; then
    echo "Verbose mode enabled (reserved for future use)" >&2
fi

main
