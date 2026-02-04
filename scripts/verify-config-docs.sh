#!/usr/bin/env bash
# verify-config-docs.sh - docs/configuration.mdとlib/config.shの整合性検証

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

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

# メイン処理
main() {
    echo "=== Configuration Documentation Verification ==="
    echo ""
    
    local exit_code=0
    
    # 1. 設定項目の存在チェック
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
    else
        log_error "Configuration mismatch detected:"
        echo ""
        echo "Missing in documentation:"
        comm -23 <(echo "$config_vars") <(echo "$doc_vars") | sed 's/^/  - PI_RUNNER_/'
        echo ""
        echo "Extra in documentation:"
        comm -13 <(echo "$config_vars") <(echo "$doc_vars") | sed 's/^/  - PI_RUNNER_/'
        exit_code=1
    fi
    
    echo ""
    
    # 2. デフォルト値のサンプルチェック（一部のみ）
    echo "2. Checking default values (sample)..."
    
    local sample_vars=(
        "WORKTREE_BASE_DIR:.worktrees"
        "MULTIPLEXER_SESSION_PREFIX:pi"
        "PARALLEL_MAX_CONCURRENT:0"
        "PLANS_KEEP_RECENT:10"
    )
    
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
            exit_code=1
        fi
    done
    
    echo ""
    
    # 3. ドキュメント構造チェック
    echo "3. Checking document structure..."
    
    local sections=(
        "worktree"
        "multiplexer"
        "pi"
        "agent"
        "parallel"
        "plans"
        "improve_logs"
        "agents"
        "github"
    )
    
    for section in "${sections[@]}"; do
        if grep -q "### $section" "$PROJECT_ROOT/docs/configuration.md"; then
            log_info "Section \"$section\" found"
        else
            log_warn "Section \"$section\" not found (may use different heading)"
        fi
    done
    
    echo ""
    
    # 結果サマリー
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ Configuration documentation is up-to-date${NC}"
    else
        echo -e "${RED}❌ Configuration documentation needs update${NC}"
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
