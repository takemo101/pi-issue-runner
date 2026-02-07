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

# ============================================================================
# Project information collection
# ============================================================================

# Collect project context for AI prompt
# Gathers: file tree, key config files, detected stack info
collect_project_context() {
    local project_dir="${1:-.}"
    local context=""

    # --- Directory structure (depth 3, excluding noise) ---
    context+="## Directory Structure"$'\n'
    context+="$(find "$project_dir" -maxdepth 3 \
        -not -path '*/node_modules/*' \
        -not -path '*/.git/*' \
        -not -path '*/.worktrees/*' \
        -not -path '*/vendor/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/.next/*' \
        -not -path '*/.nuxt/*' \
        -not -name '*.pyc' \
        -not -name '*.lock' \
        -not -name 'package-lock.json' \
        2>/dev/null | head -200 | sed 's|^\./||')"$'\n\n'

    # --- Key config files content ---
    # package.json (truncated)
    if [[ -f "$project_dir/package.json" ]]; then
        context+="## package.json"$'\n'
        context+='```json'$'\n'
        context+="$(head -80 "$project_dir/package.json")"$'\n'
        context+='```'$'\n\n'
    fi

    # pyproject.toml
    if [[ -f "$project_dir/pyproject.toml" ]]; then
        context+="## pyproject.toml"$'\n'
        context+='```toml'$'\n'
        context+="$(head -60 "$project_dir/pyproject.toml")"$'\n'
        context+='```'$'\n\n'
    fi

    # Gemfile
    if [[ -f "$project_dir/Gemfile" ]]; then
        context+="## Gemfile"$'\n'
        context+='```ruby'$'\n'
        context+="$(head -40 "$project_dir/Gemfile")"$'\n'
        context+='```'$'\n\n'
    fi

    # go.mod
    if [[ -f "$project_dir/go.mod" ]]; then
        context+="## go.mod"$'\n'
        context+='```'$'\n'
        context+="$(head -30 "$project_dir/go.mod")"$'\n'
        context+='```'$'\n\n'
    fi

    # Cargo.toml
    if [[ -f "$project_dir/Cargo.toml" ]]; then
        context+="## Cargo.toml"$'\n'
        context+='```toml'$'\n'
        context+="$(head -40 "$project_dir/Cargo.toml")"$'\n'
        context+='```'$'\n\n'
    fi

    # composer.json
    if [[ -f "$project_dir/composer.json" ]]; then
        context+="## composer.json"$'\n'
        context+='```json'$'\n'
        context+="$(head -60 "$project_dir/composer.json")"$'\n'
        context+='```'$'\n\n'
    fi

    # build.gradle / pom.xml (first lines)
    if [[ -f "$project_dir/build.gradle.kts" ]]; then
        context+="## build.gradle.kts (excerpt)"$'\n'
        context+='```kotlin'$'\n'
        context+="$(head -30 "$project_dir/build.gradle.kts")"$'\n'
        context+='```'$'\n\n'
    elif [[ -f "$project_dir/build.gradle" ]]; then
        context+="## build.gradle (excerpt)"$'\n'
        context+='```groovy'$'\n'
        context+="$(head -30 "$project_dir/build.gradle")"$'\n'
        context+='```'$'\n\n'
    fi

    # tsconfig.json
    if [[ -f "$project_dir/tsconfig.json" ]]; then
        context+="## tsconfig.json"$'\n'
        context+='```json'$'\n'
        context+="$(cat "$project_dir/tsconfig.json")"$'\n'
        context+='```'$'\n\n'
    fi

    # README (first 50 lines for project overview)
    if [[ -f "$project_dir/README.md" ]]; then
        context+="## README.md (excerpt)"$'\n'
        context+='```markdown'$'\n'
        context+="$(head -50 "$project_dir/README.md")"$'\n'
        context+='```'$'\n\n'
    fi

    # AGENTS.md (development guide)
    if [[ -f "$project_dir/AGENTS.md" ]]; then
        context+="## AGENTS.md (excerpt)"$'\n'
        context+='```markdown'$'\n'
        context+="$(head -80 "$project_dir/AGENTS.md")"$'\n'
        context+='```'$'\n\n'
    fi

    # CI config
    if [[ -d "$project_dir/.github/workflows" ]]; then
        context+="## CI Workflow files"$'\n'
        for wf in "$project_dir/.github/workflows"/*.{yml,yaml}; do
            [[ -f "$wf" ]] || continue
            context+="### $(basename "$wf")"$'\n'
            context+='```yaml'$'\n'
            context+="$(head -40 "$wf")"$'\n'
            context+='```'$'\n\n'
        done
    fi

    # Existing env files (names only, not content)
    context+="## Environment files found"$'\n'
    local env_candidates=(.env .env.local .env.development .env.development.local .envrc .npmrc .yarnrc.yml .tool-versions .node-version .nvmrc .python-version .ruby-version)
    for f in "${env_candidates[@]}"; do
        if [[ -f "$project_dir/$f" ]]; then
            context+="- $f"$'\n'
        fi
    done
    context+=$'\n'

    # Available multiplexer
    context+="## Available tools"$'\n'
    command -v tmux &>/dev/null && context+="- tmux: available"$'\n' || true
    command -v zellij &>/dev/null && context+="- zellij: available"$'\n' || true
    command -v pi &>/dev/null && context+="- pi: available"$'\n' || true
    command -v claude &>/dev/null && context+="- claude: available"$'\n' || true
    context+=$'\n'

    # Repository name
    local repo_name
    repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
    context+="## Repository name: ${repo_name}"$'\n'

    echo "$context"
}

# ============================================================================
# AI-powered generation
# ============================================================================

# Build the prompt for AI config generation
build_ai_prompt() {
    local project_context="$1"
    local schema_file="$PROJECT_ROOT/schemas/pi-runner.schema.json"

    local prompt=""

    prompt+="You are a configuration generator for pi-issue-runner, a tool that processes GitHub Issues using AI coding agents in Git worktrees."$'\n\n'

    prompt+="Based on the project information below, generate an optimal \`.pi-runner.yaml\` configuration file."$'\n\n'

    prompt+="# Requirements"$'\n'
    prompt+="- Output ONLY the YAML content, no explanation, no markdown fences"$'\n'
    prompt+="- Include helpful comments in the YAML (in Japanese)"$'\n'
    prompt+="- The YAML must conform to the JSON Schema provided below"$'\n'
    prompt+="- Detect the appropriate multiplexer (tmux/zellij) from available tools"$'\n'
    prompt+="- Detect the appropriate agent (pi/claude) from available tools"$'\n'
    prompt+="- Use the repository name as session_prefix"$'\n'
    prompt+="- Include copy_files only for env files that actually exist"$'\n'
    prompt+="- Generate workflows that match the project's tech stack and development patterns"$'\n'
    prompt+="- Each workflow's description should be specific enough for AI auto-selection (-w auto)"$'\n'
    prompt+="- Each workflow's context should describe the project-specific tech stack and conventions"$'\n'
    prompt+="- Do NOT generate the 'workflow:' (singular) key. Use only the 'workflows:' (plural) section"$'\n'
    prompt+="- Always include: default (standard), quick (minimal), thorough (full), docs (documentation) workflows"$'\n'
    prompt+="- Add frontend/backend workflows only if the project has those aspects"$'\n'
    prompt+="- If the project has test frameworks, include test step in default workflow"$'\n'
    prompt+="- Set parallel.max_concurrent to a reasonable value (e.g., 3)"$'\n\n'

    # Schema
    if [[ -f "$schema_file" ]]; then
        prompt+="# JSON Schema for .pi-runner.yaml"$'\n'
        prompt+='```json'$'\n'
        prompt+="$(cat "$schema_file")"$'\n'
        prompt+='```'$'\n\n'
    fi

    # Project context
    prompt+="# Project Information"$'\n'
    prompt+="$project_context"$'\n'

    echo "$prompt"
}

# Generate config using AI (pi --print)
generate_with_ai() {
    local project_context="$1"

    # Determine pi command
    local pi_command="${PI_COMMAND:-pi}"
    if ! command -v "$pi_command" &>/dev/null; then
        log_debug "pi command not found: $pi_command"
        return 1
    fi

    local prompt
    prompt="$(build_ai_prompt "$project_context")"

    log_info "AIで設定を生成中..."

    local response
    local exit_code=0
    response=$(echo "$prompt" | timeout 60 "$pi_command" --print \
        --provider "${PI_RUNNER_AUTO_PROVIDER:-anthropic}" \
        --model "${PI_RUNNER_AUTO_MODEL:-claude-haiku-4-5}" \
        --no-tools \
        --no-session 2>/dev/null) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        log_debug "AI generation failed (exit code: $exit_code)"
        return 1
    fi

    # Strip markdown fences if AI included them
    response="$(echo "$response" | sed '/^```yaml$/d; /^```$/d; /^```yml$/d')"

    # Basic validation: must contain 'worktree:' or 'workflow:'
    if ! echo "$response" | grep -q 'worktree:\|workflow:\|workflows:'; then
        log_debug "AI response doesn't look like valid config"
        return 1
    fi

    echo "$response"
}

# ============================================================================
# Static fallback generation
# ============================================================================

# Detect files that should be copied to worktrees
detect_copy_files() {
    local project_dir="${1:-.}"
    DETECTED_COPY_FILES=()

    local candidates=(
        ".env" ".env.local" ".env.development" ".env.development.local"
        ".envrc" ".npmrc" ".yarnrc.yml"
        "config/master.key" "config/credentials.yml.enc" "config/database.yml"
        ".ruby-version" ".node-version" ".nvmrc" ".python-version" ".tool-versions"
    )

    for file in "${candidates[@]}"; do
        [[ -f "$project_dir/$file" ]] && DETECTED_COPY_FILES+=("$file")
    done

    return 0
}

# Generate static fallback YAML (no AI)
generate_static_yaml() {
    detect_copy_files "."

    cat << 'HEADER'
# pi-issue-runner configuration
# Generated by: generate-config.sh (static fallback)
# Docs: https://github.com/takemo101/pi-issue-runner/blob/main/docs/configuration.md
HEADER

    echo ""
    echo "worktree:"
    echo "  base_dir: \".worktrees\""

    if [[ ${#DETECTED_COPY_FILES[@]} -gt 0 ]]; then
        echo "  copy_files:"
        for f in "${DETECTED_COPY_FILES[@]}"; do
            echo "    - \"$f\""
        done
    fi

    echo ""
    echo "multiplexer:"
    if command -v zellij &>/dev/null && ! command -v tmux &>/dev/null; then
        echo "  type: zellij"
    else
        echo "  type: tmux"
    fi

    local repo_name
    repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
    repo_name="$(echo "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    echo "  session_prefix: \"${repo_name:-pi}\""

    echo ""
    if command -v pi &>/dev/null; then
        echo "agent:"
        echo "  type: pi"
    elif command -v claude &>/dev/null; then
        echo "agent:"
        echo "  type: claude"
    fi

    echo ""
    echo "parallel:"
    echo "  max_concurrent: 3"

    echo ""
    echo "workflows:"
    echo "  default:"
    echo "    description: 標準ワークフロー（計画・実装・レビュー・マージ）"
    echo "    steps:"
    echo "      - plan"
    echo "      - implement"
    echo "      - review"
    echo "      - merge"
    echo ""
    echo "  quick:"
    echo "    description: 小規模修正（typo、設定変更、1ファイル程度の変更）"
    echo "    steps:"
    echo "      - implement"
    echo "      - merge"
    echo ""
    echo "  thorough:"
    echo "    description: 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更）"
    echo "    steps:"
    echo "      - plan"
    echo "      - implement"
    echo "      - test"
    echo "      - review"
    echo "      - merge"
    echo ""
    echo "  docs:"
    echo "    description: ドキュメント作成・更新（README、仕様書、ADR）"
    echo "    steps:"
    echo "      - implement"
    echo "      - review"
    echo "      - merge"

    echo ""
    echo "github:"
    echo "  include_comments: true"
    echo "  max_comments: 10"

    echo ""
    echo "plans:"
    echo "  keep_recent: 10"
    echo "  dir: \"docs/plans\""
}

# ============================================================================
# Validation
# ============================================================================

validate_config() {
    local config_file="${1:-.pi-runner.yaml}"
    local schema_file="$PROJECT_ROOT/schemas/pi-runner.schema.json"

    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found: $schema_file"
        return 1
    fi

    # Try different validation tools
    if command -v ajv &>/dev/null; then
        log_info "Validating with ajv..."
        ajv validate -s "$schema_file" -d "$config_file" --spec=draft7
    elif command -v yq &>/dev/null && command -v python3 &>/dev/null; then
        log_info "Validating with python jsonschema..."
        SCHEMA_FILE="$schema_file" yq -o json "$config_file" | python3 -c "
import json, os, sys
try:
    from jsonschema import validate, ValidationError
    with open(os.environ['SCHEMA_FILE']) as f:
        schema = json.load(f)
    data = json.load(sys.stdin)
    validate(instance=data, schema=schema)
    print('[OK] Configuration is valid')
except ImportError:
    print('[WARN] python jsonschema not installed: pip install jsonschema', file=sys.stderr)
    sys.exit(2)
except ValidationError as e:
    print(f'[ERROR] Validation failed: {e.message}', file=sys.stderr)
    sys.exit(1)
"
    elif command -v check-jsonschema &>/dev/null; then
        log_info "Validating with check-jsonschema..."
        check-jsonschema --schemafile "$schema_file" "$config_file"
    else
        log_warn "No JSON Schema validator found."
        log_warn "Install one of: ajv-cli, python-jsonschema, check-jsonschema"
        log_warn "  npm install -g ajv-cli"
        log_warn "  pip install check-jsonschema"
        return 2
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    local output_file=".pi-runner.yaml"
    local dry_run=false
    local force=false
    local no_ai=false
    local validate_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                if [[ $# -lt 2 ]]; then
                    log_error "--output requires a file path argument"
                    exit 1
                fi
                output_file="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --no-ai)
                no_ai=true
                shift
                ;;
            --validate)
                validate_only=true
                shift
                ;;
            -h|--help)
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
                ;;
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

    # Validate mode
    if [[ "$validate_only" == "true" ]]; then
        validate_config "$output_file"
        return $?
    fi

    # Check existing file
    if [[ -f "$output_file" && "$force" != "true" && "$dry_run" != "true" ]]; then
        log_error "$output_file は既に存在します。--force で上書きするか、--dry-run でプレビューしてください。"
        exit 1
    fi

    # Generate config
    local yaml_content=""

    if [[ "$no_ai" != "true" ]]; then
        # Collect project context
        log_info "プロジェクト情報を収集中..."
        local project_context
        project_context="$(collect_project_context ".")"

        # Try AI generation
        yaml_content="$(generate_with_ai "$project_context")" || {
            log_warn "AI生成に失敗しました。静的テンプレートにフォールバックします。"
            yaml_content=""
        }
    fi

    # Fallback to static generation
    if [[ -z "$yaml_content" ]]; then
        if [[ "$no_ai" == "true" ]]; then
            log_info "静的テンプレートで生成中..."
        fi
        yaml_content="$(generate_static_yaml)"
    fi

    # Output
    if [[ "$dry_run" == "true" ]]; then
        echo "$yaml_content"
    else
        echo "$yaml_content" > "$output_file"
        log_success "$output_file を生成しました"
        echo ""
        echo "次のステップ:"
        echo "  1. $output_file を確認・編集"
        echo "  2. pi-run <issue-number> で実行"
        echo ""
        echo "検証: $(basename "$0") --validate"
    fi
}

main "$@"
