#!/usr/bin/env bash
# ============================================================================
# generate-config.sh - Analyze project and generate .pi-runner.yaml using AI
#
# Collects project structure information (languages, frameworks, files)
# and uses AI (pi --print) to generate an optimized .pi-runner.yaml.
# Falls back to static template generation when AI is unavailable.
#
# Usage: ./scripts/generate-config.sh [options]
#
# Options:
#   -o, --output FILE   Output file path (default: .pi-runner.yaml)
#   --dry-run           Print to stdout without writing
#   --force             Overwrite existing config
#   --no-ai             Skip AI generation, use static fallback only
#   --validate          Validate existing config against schema
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# lib/log.sh をロード（存在する場合）
if [[ -f "$PROJECT_ROOT/lib/log.sh" ]]; then
    source "$PROJECT_ROOT/lib/log.sh"
else
    log_info()    { echo "[INFO] $*"; }
    log_warn()    { echo "[WARN] $*" >&2; }
    log_error()   { echo "[ERROR] $*" >&2; }
    log_success() { echo "[OK] $*"; }
    log_debug()   { [[ "${DEBUG:-}" == "1" ]] && echo "[DEBUG] $*" >&2 || true; }
fi

# lib/generate-config.sh をロード
source "$PROJECT_ROOT/lib/generate-config.sh"

# ============================================================================
# Argument parsing
# ============================================================================

# Show help message and exit
_show_help() {
    cat << 'HELP'
Usage: generate-config.sh [options]

プロジェクトの構造をAIで解析し、最適な .pi-runner.yaml を生成します。
AI (pi --print) が利用できない場合は静的テンプレートにフォールバックします。

Options:
    -o, --output FILE   出力ファイルパス (default: .pi-runner.yaml)
    --dry-run           ファイルに書き込まず標準出力に表示
    --force             既存ファイルを上書き
    --no-ai             AI生成をスキップし、静的テンプレートのみ使用
    --validate          既存の設定をスキーマで検証
    -h, --help          このヘルプを表示

Environment Variables:
    PI_COMMAND                  piコマンドのパス (default: pi)
    PI_RUNNER_AUTO_PROVIDER     AIプロバイダー (default: anthropic)
    PI_RUNNER_AUTO_MODEL        AIモデル (default: claude-haiku-4-5)

Examples:
    generate-config.sh                  # AI解析して .pi-runner.yaml を生成
    generate-config.sh --dry-run        # 結果をプレビュー
    generate-config.sh --no-ai          # 静的テンプレートで生成
    generate-config.sh --validate       # 既存設定を検証
    generate-config.sh -o custom.yaml   # カスタム出力先
HELP
    exit 0
}

parse_arguments() {
    # Set defaults
    OUTPUT_FILE=".pi-runner.yaml"
    DRY_RUN=false
    FORCE=false
    NO_AI=false
    VALIDATE_ONLY=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                if [[ $# -lt 2 ]]; then
                    log_error "--output requires a file path argument"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --dry-run)     DRY_RUN=true; shift ;;
            --force)       FORCE=true; shift ;;
            --no-ai)       NO_AI=true; shift ;;
            --validate)    VALIDATE_ONLY=true; shift ;;
            -h|--help)     _show_help ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                exit 1
                ;;
        esac
    done
}

# Validate parsed arguments against current state
validate_arguments() {
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        return 0
    fi

    if [[ -f "$OUTPUT_FILE" && "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        log_error "$OUTPUT_FILE は既に存在します。--force で上書きするか、--dry-run でプレビューしてください。"
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================

# Generate YAML content using AI with static fallback
_generate_yaml_content() {
    local yaml_content=""

    if [[ "$NO_AI" != "true" ]]; then
        log_info "プロジェクト情報を収集中..."
        local project_context
        project_context="$(collect_project_context ".")"

        detect_gates "."

        yaml_content="$(generate_with_ai "$project_context")" || {
            log_warn "AI生成に失敗しました。静的テンプレートにフォールバックします。"
            yaml_content=""
        }
    fi

    if [[ -z "$yaml_content" ]]; then
        if [[ "$NO_AI" == "true" ]]; then
            log_info "静的テンプレートで生成中..."
        fi
        yaml_content="$(generate_static_yaml)"
    fi

    echo "$yaml_content"
}

# Output generated YAML to stdout or file
_output_yaml() {
    local yaml_content="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "$yaml_content"
    else
        echo "$yaml_content" > "$OUTPUT_FILE"
        log_success "$OUTPUT_FILE を生成しました"
        echo ""
        echo "次のステップ:"
        echo "  1. $OUTPUT_FILE を確認・編集"
        echo "  2. pi-run <issue-number> で実行"
        echo ""
        echo "検証: $(basename "$0") --validate"
    fi
}

main() {
    parse_arguments "$@"

    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        validate_config "$OUTPUT_FILE"
        return $?
    fi

    validate_arguments

    local yaml_content
    yaml_content="$(_generate_yaml_content)"

    _output_yaml "$yaml_content"
}

main "$@"
