#!/usr/bin/env bash
# ============================================================================
# dashboard.sh - Project dashboard
#
# Displays a comprehensive overview of the project status, including
# running sessions, blocked issues, and ready-to-work issues.
#
# Usage: ./scripts/dashboard.sh [options]
#
# Options:
#   --json              Output in JSON format
#   --no-color          Disable colored output (for CI environments)
#   --compact           Compact view (summary only)
#   --section <name>    Show only specific section
#                       (summary|progress|blocked|ready)
#   -w, --watch         Auto-refresh mode (every 5 seconds)
#   -v, --verbose       Show detailed information
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/dashboard.sh
#   ./scripts/dashboard.sh --compact
#   ./scripts/dashboard.sh --json
#   ./scripts/dashboard.sh --watch
# ============================================================================

set -euo pipefail

# Bash 4.0以上を要求（連想配列のサポート）
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "[ERROR] Bash 4.0 or higher is required (current: ${BASH_VERSION})" >&2
    echo "[INFO] Install: brew install bash (macOS)" >&2
    echo "[INFO] Then use: /usr/local/bin/bash $(realpath "$0")" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/dashboard.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

プロジェクト全体の状況を表示します。

Options:
    --json              JSON形式で出力
    --no-color          色なし出力（CI環境向け）
    --compact           コンパクト表示（サマリーのみ）
    --section <name>    特定セクションのみ表示
                        (summary|progress|blocked|ready)
    -w, --watch         自動更新モード（5秒ごと）
    -v, --verbose       詳細情報を表示
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0")                    # 標準表示
    $(basename "$0") --compact          # サマリーのみ
    $(basename "$0") --json             # JSON出力
    $(basename "$0") --watch            # 自動更新
    $(basename "$0") --section summary  # サマリーのみ表示

Sections:
    summary     サマリー統計
    progress    進行中のIssue
    blocked     ブロックされたIssue
    ready       実行可能なIssue
EOF
}

main() {
    local json_mode=false
    local compact=false
    local section="all"
    local watch_mode=false
    local verbose=false
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_mode=true
                shift
                ;;
            --no-color)
                export NO_COLOR=1
                shift
                ;;
            --compact)
                compact=true
                shift
                ;;
            --section)
                if [[ $# -lt 2 ]]; then
                    log_error "--section requires an argument"
                    usage >&2
                    exit 1
                fi
                section="$2"
                # セクション名の検証
                case "$section" in
                    summary|progress|blocked|ready)
                        ;;
                    *)
                        log_error "Invalid section: $section"
                        log_info "Valid sections: summary, progress, blocked, ready"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -w|--watch)
                watch_mode=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                enable_verbose
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
    done
    
    # パイプやリダイレクト時は自動的にno-color
    if [[ ! -t 1 ]]; then
        export NO_COLOR=1
    fi
    
    # 依存関係チェック
    if ! command -v gh &>/dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install: https://cli.github.com/"
        exit 1
    fi
    
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI is not authenticated"
        log_info "Run: gh auth login"
        exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed"
        log_info "Install: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
    
    # 設定読み込み
    load_config
    
    # 表示モード
    if [[ "$json_mode" == "true" ]]; then
        # JSON出力
        output_json
    elif [[ "$watch_mode" == "true" ]]; then
        # 自動更新モード
        while true; do
            clear
            draw_dashboard "$compact" "$section" "$verbose"
            echo ""
            echo "Press Ctrl+C to exit | Refreshing every 5 seconds..."
            sleep 5
        done
    else
        # 通常表示
        draw_dashboard "$compact" "$section" "$verbose"
    fi
}

main "$@"
