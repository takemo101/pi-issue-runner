#!/usr/bin/env bash
# ============================================================================
# lib/generate-config.sh - Reusable functions for project analysis and config generation
#
# Provides:
#   - Project information collection (_collect_*, collect_project_context)
#   - AI-powered generation (build_ai_prompt, generate_with_ai)
#   - Static fallback generation (generate_static_yaml and helpers)
#   - Config validation (validate_config)
#
# Usage:
#   source "$PROJECT_ROOT/lib/generate-config.sh"
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_GENERATE_CONFIG_SH_SOURCED:-}" ]]; then
    return 0
fi
_GENERATE_CONFIG_SH_SOURCED="true"

_GENERATE_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_GENERATE_CONFIG_LIB_DIR/compat.sh"

# ============================================================================
# Project information collection
# ============================================================================

# Collect directory structure (depth 3, excluding build artifacts)
_collect_directory_structure() {
    local project_dir="${1:-.}"
    local context=""

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

    echo "$context"
}

# Find config files that exist in the project directory
# Returns a list of "filename:language:max_lines" entries, one per line
_find_config_files() {
    local project_dir="${1:-.}"

    # Define config file candidates: filename:language:max_lines
    local candidates=(
        "package.json:json:80"
        "pyproject.toml:toml:60"
        "Gemfile:ruby:40"
        "go.mod::30"
        "Cargo.toml:toml:40"
        "composer.json:json:60"
        "tsconfig.json:json:0"
    )

    for entry in "${candidates[@]}"; do
        local filename="${entry%%:*}"
        if [[ -f "$project_dir/$filename" ]]; then
            echo "$entry"
        fi
    done

    # Special case: build.gradle variants (only one)
    if [[ -f "$project_dir/build.gradle.kts" ]]; then
        echo "build.gradle.kts:kotlin:30"
    elif [[ -f "$project_dir/build.gradle" ]]; then
        echo "build.gradle:groovy:30"
    fi
}

# Parse a single config file into markdown context
# Args: project_dir filename language max_lines
_parse_config_content() {
    local project_dir="$1"
    local filename="$2"
    local language="$3"
    local max_lines="$4"

    local filepath="$project_dir/$filename"
    [[ -f "$filepath" ]] || return 0

    local content=""
    content+="## $filename"$'\n'
    content+='```'"${language}"$'\n'
    if [[ "$max_lines" -eq 0 ]]; then
        content+="$(cat "$filepath")"$'\n'
    else
        content+="$(head -"$max_lines" "$filepath")"$'\n'
    fi
    content+='```'$'\n\n'
    echo "$content"
}

# Collect key configuration files content
_collect_config_files() {
    local project_dir="${1:-.}"
    local context=""

    local entry
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local filename language max_lines
        filename="$(echo "$entry" | cut -d: -f1)"
        language="$(echo "$entry" | cut -d: -f2)"
        max_lines="$(echo "$entry" | cut -d: -f3)"
        context+="$(_parse_config_content "$project_dir" "$filename" "$language" "$max_lines")"
    done < <(_find_config_files "$project_dir")

    echo "$context"
}

# Collect documentation files
_collect_documentation() {
    local project_dir="${1:-.}"
    local context=""

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

    echo "$context"
}

# Collect CI configuration
_collect_ci_config() {
    local project_dir="${1:-.}"
    local context=""

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

    echo "$context"
}

# Collect environment information
_collect_environment_info() {
    local project_dir="${1:-.}"
    local context=""

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

# Collect project context for AI prompt
# Gathers: file tree, key config files, detected stack info
collect_project_context() {
    local project_dir="${1:-.}"
    local context=""

    context+="$(_collect_directory_structure "$project_dir")"
    context+="$(_collect_config_files "$project_dir")"
    context+="$(_collect_documentation "$project_dir")"
    context+="$(_collect_ci_config "$project_dir")"
    context+="$(_collect_environment_info "$project_dir")"

    echo "$context"
}

# ============================================================================
# AI-powered generation
# ============================================================================

# Build the prompt for AI config generation
# Requires: PROJECT_ROOT to be set (for schema file path)
build_ai_prompt() {
    local project_context="$1"
    local schema_file="${PROJECT_ROOT:-.}/schemas/pi-runner.schema.json"

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
    prompt+="- Workflows can have an optional 'agent' field to override the global agent settings (type, args, command, template)"$'\n'
    prompt+="- Use lightweight models (e.g., claude-sonnet-4) for simple workflows (quick, docs) and powerful models for complex workflows (thorough)"$'\n'
    prompt+="- Do NOT generate the 'workflow:' (singular) key. Use only the 'workflows:' (plural) section"$'\n'
    prompt+="- Always include: default (standard), quick (minimal), thorough (full), docs (documentation) workflows"$'\n'
    prompt+="- Add frontend/backend workflows only if the project has those aspects"$'\n'
    prompt+="- If the project has test frameworks, include test step in default workflow"$'\n'
    prompt+="- Set parallel.max_concurrent to a reasonable value (e.g., 3)"$'\n'
    prompt+="- Detect test and lint commands from the project and generate a top-level 'gates:' section"$'\n'
    prompt+="- Gates are quality check commands run after task completion (exit 0 = pass)"$'\n'
    prompt+="- Include lint commands before test commands in gates (lint is faster)"$'\n'
    prompt+="- Only include gates for tools that actually exist in the project"$'\n\n'

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

    # Detected gates hint
    if [[ -n "${DETECTED_GATES+x}" ]] && [[ ${#DETECTED_GATES[@]} -gt 0 ]]; then
        prompt+="# Detected Quality Gate Commands (use as reference)"$'\n'
        for gate in "${DETECTED_GATES[@]}"; do
            prompt+="- $gate"$'\n'
        done
        prompt+=$'\n'
    fi

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
    response=$(echo "$prompt" | safe_timeout 60 "$pi_command" --print \
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
# Gates detection
# ============================================================================

# Detect quality gate commands based on project structure
# Populates the global DETECTED_GATES array
#
# Detection targets:
#   - package.json (test/lint scripts) → npm test, npm run lint
#   - Makefile (test/lint targets) → make test, make lint
#   - Cargo.toml → cargo test, cargo clippy
#   - go.mod → go test ./..., go vet ./...
#   - pyproject.toml / setup.py → pytest, ruff check . or flake8
#   - .shellcheckrc / scripts/*.sh → shellcheck -x scripts/*.sh lib/*.sh
#   - test/ + *.bats → bats --jobs 4 test/
#
# Usage: detect_gates <project_dir>
# Side effect: populates DETECTED_GATES array
detect_gates() {
    local project_dir="${1:-.}"
    DETECTED_GATES=()

    # Node.js
    if [[ -f "$project_dir/package.json" ]]; then
        if grep -qE '"lint"\s*:' "$project_dir/package.json" 2>/dev/null; then
            DETECTED_GATES+=("npm run lint")
        fi
        if grep -qE '"test"\s*:' "$project_dir/package.json" 2>/dev/null; then
            DETECTED_GATES+=("npm test")
        fi
    fi

    # Makefile
    if [[ -f "$project_dir/Makefile" ]]; then
        if grep -qE '^lint\s*:' "$project_dir/Makefile" 2>/dev/null; then
            DETECTED_GATES+=("make lint")
        fi
        if grep -qE '^test\s*:' "$project_dir/Makefile" 2>/dev/null; then
            DETECTED_GATES+=("make test")
        fi
    fi

    # Rust
    if [[ -f "$project_dir/Cargo.toml" ]]; then
        DETECTED_GATES+=("cargo clippy")
        DETECTED_GATES+=("cargo test")
    fi

    # Go
    if [[ -f "$project_dir/go.mod" ]]; then
        DETECTED_GATES+=("go vet ./...")
        DETECTED_GATES+=("go test ./...")
    fi

    # Python
    if [[ -f "$project_dir/pyproject.toml" ]] || [[ -f "$project_dir/setup.py" ]]; then
        if [[ -f "$project_dir/pyproject.toml" ]] && grep -qE '\[tool\.ruff\]' "$project_dir/pyproject.toml" 2>/dev/null; then
            DETECTED_GATES+=("ruff check .")
        elif [[ -f "$project_dir/.flake8" ]] || { [[ -f "$project_dir/setup.cfg" ]] && grep -qE '\[flake8\]' "$project_dir/setup.cfg" 2>/dev/null; }; then
            DETECTED_GATES+=("flake8")
        fi
        DETECTED_GATES+=("pytest")
    fi

    # ShellCheck
    local has_shell_scripts=false
    if [[ -f "$project_dir/.shellcheckrc" ]]; then
        has_shell_scripts=true
    elif ls "$project_dir"/scripts/*.sh &>/dev/null; then
        has_shell_scripts=true
    fi
    if [[ "$has_shell_scripts" == "true" ]]; then
        DETECTED_GATES+=("shellcheck -x scripts/*.sh lib/*.sh")
    fi

    # Bats
    if [[ -d "$project_dir/test" ]]; then
        if find "$project_dir/test" -name '*.bats' -print -quit 2>/dev/null | grep -q .; then
            DETECTED_GATES+=("bats --jobs 4 test/")
        fi
    fi

    return 0
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

# Generate static YAML header
_generate_static_header() {
    cat << 'HEADER'
# pi-issue-runner configuration
# Generated by: generate-config.sh (static fallback)
# Docs: https://github.com/takemo101/pi-issue-runner/blob/main/docs/configuration.md
HEADER
}

# Generate worktree section
_generate_static_worktree() {
    echo ""
    echo "worktree:"
    echo "  base_dir: \".worktrees\""

    if [[ ${#DETECTED_COPY_FILES[@]} -gt 0 ]]; then
        echo "  copy_files:"
        for f in "${DETECTED_COPY_FILES[@]}"; do
            echo "    - \"$f\""
        done
    fi
}

# Generate multiplexer section
_generate_static_multiplexer() {
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
}

# Generate agent and parallel sections
_generate_static_agent_and_parallel() {
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
}

# Generate gates section from DETECTED_GATES array
_generate_static_gates() {
    if [[ ${#DETECTED_GATES[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo "gates:"
    for gate in "${DETECTED_GATES[@]}"; do
        echo "  - \"$gate\""
    done
}

# Generate workflows section
_generate_static_workflows() {
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
    echo "    agent:"
    echo "      type: pi"
    echo "      args:"
    echo "        - --model"
    echo "        - claude-sonnet-4-20250514"
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
    echo "    agent:"
    echo "      type: pi"
    echo "      args:"
    echo "        - --model"
    echo "        - claude-sonnet-4-20250514"
}

# Generate github and plans sections
_generate_static_github_and_plans() {
    echo ""
    echo "github:"
    echo "  include_comments: true"
    echo "  max_comments: 10"

    echo ""
    echo "plans:"
    echo "  keep_recent: 10"
    echo "  dir: \"docs/plans\""
}

# Generate static fallback YAML (no AI)
generate_static_yaml() {
    detect_copy_files "."
    detect_gates "."

    _generate_static_header
    _generate_static_worktree
    _generate_static_multiplexer
    _generate_static_agent_and_parallel
    _generate_static_gates
    _generate_static_workflows
    _generate_static_github_and_plans
}

# ============================================================================
# Validation
# ============================================================================

validate_config() {
    local config_file="${1:-.pi-runner.yaml}"
    local schema_file="${PROJECT_ROOT:-.}/schemas/pi-runner.schema.json"

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
