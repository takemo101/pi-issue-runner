#!/usr/bin/env bash
# ============================================================================
# generate-config.sh - Analyze project and generate .pi-runner.yaml
#
# Scans the current project structure, detects languages, frameworks,
# and development patterns, then generates an optimized .pi-runner.yaml.
#
# Usage: ./scripts/generate-config.sh [options]
#
# Options:
#   --output, -o FILE   Output file path (default: .pi-runner.yaml)
#   --dry-run           Print to stdout without writing
#   --force             Overwrite existing config
#   --no-workflows      Skip workflow generation
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
fi

# ============================================================================
# Detection functions
# ============================================================================

# Detect programming languages and frameworks
detect_stack() {
    local project_dir="${1:-.}"
    
    DETECTED_LANGUAGES=()
    DETECTED_FRAMEWORKS=()
    DETECTED_TEST_FRAMEWORKS=()
    DETECTED_PACKAGE_MANAGERS=()
    DETECTED_CI=()
    
    # --- Node.js / TypeScript ---
    if [[ -f "$project_dir/package.json" ]]; then
        DETECTED_LANGUAGES+=("javascript")
        DETECTED_PACKAGE_MANAGERS+=("npm")
        
        [[ -f "$project_dir/yarn.lock" ]] && DETECTED_PACKAGE_MANAGERS+=("yarn")
        [[ -f "$project_dir/pnpm-lock.yaml" ]] && DETECTED_PACKAGE_MANAGERS+=("pnpm")
        [[ -f "$project_dir/bun.lockb" ]] && DETECTED_PACKAGE_MANAGERS+=("bun")
        
        if [[ -f "$project_dir/tsconfig.json" ]]; then
            DETECTED_LANGUAGES+=("typescript")
        fi
        
        # Detect frameworks from package.json
        if command -v jq &>/dev/null && [[ -f "$project_dir/package.json" ]]; then
            local deps
            deps="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$project_dir/package.json" 2>/dev/null || true)"
            
            echo "$deps" | grep -qx "next" && DETECTED_FRAMEWORKS+=("nextjs")
            echo "$deps" | grep -qx "react" && DETECTED_FRAMEWORKS+=("react")
            echo "$deps" | grep -qx "vue" && DETECTED_FRAMEWORKS+=("vue")
            echo "$deps" | grep -qx "svelte" && DETECTED_FRAMEWORKS+=("svelte")
            echo "$deps" | grep -qx "@angular/core" && DETECTED_FRAMEWORKS+=("angular")
            echo "$deps" | grep -qx "express" && DETECTED_FRAMEWORKS+=("express")
            echo "$deps" | grep -qx "fastify" && DETECTED_FRAMEWORKS+=("fastify")
            echo "$deps" | grep -qx "@nestjs/core" && DETECTED_FRAMEWORKS+=("nestjs")
            echo "$deps" | grep -qx "hono" && DETECTED_FRAMEWORKS+=("hono")
            echo "$deps" | grep -qx "tailwindcss" && DETECTED_FRAMEWORKS+=("tailwindcss")
            echo "$deps" | grep -qx "@prisma/client" && DETECTED_FRAMEWORKS+=("prisma")
            echo "$deps" | grep -qx "drizzle-orm" && DETECTED_FRAMEWORKS+=("drizzle")
            
            # Test frameworks
            echo "$deps" | grep -qx "jest" && DETECTED_TEST_FRAMEWORKS+=("jest")
            echo "$deps" | grep -qx "vitest" && DETECTED_TEST_FRAMEWORKS+=("vitest")
            echo "$deps" | grep -qx "mocha" && DETECTED_TEST_FRAMEWORKS+=("mocha")
            { echo "$deps" | grep -qx "playwright" || echo "$deps" | grep -qx "@playwright/test"; } && DETECTED_TEST_FRAMEWORKS+=("playwright")
            echo "$deps" | grep -qx "cypress" && DETECTED_TEST_FRAMEWORKS+=("cypress")
        fi
    fi
    
    # --- Python ---
    if [[ -f "$project_dir/pyproject.toml" || -f "$project_dir/setup.py" || -f "$project_dir/requirements.txt" || -f "$project_dir/Pipfile" ]]; then
        DETECTED_LANGUAGES+=("python")
        [[ -f "$project_dir/Pipfile" ]] && DETECTED_PACKAGE_MANAGERS+=("pipenv")
        [[ -f "$project_dir/poetry.lock" ]] && DETECTED_PACKAGE_MANAGERS+=("poetry")
        [[ -f "$project_dir/uv.lock" ]] && DETECTED_PACKAGE_MANAGERS+=("uv")
        
        # Python frameworks
        local py_deps=""
        if [[ -f "$project_dir/requirements.txt" ]]; then
            py_deps="$(cat "$project_dir/requirements.txt")"
        elif [[ -f "$project_dir/pyproject.toml" ]]; then
            py_deps="$(cat "$project_dir/pyproject.toml")"
        fi
        
        if [[ -n "$py_deps" ]]; then
            echo "$py_deps" | grep -qi "django" && DETECTED_FRAMEWORKS+=("django")
            echo "$py_deps" | grep -qi "flask" && DETECTED_FRAMEWORKS+=("flask")
            echo "$py_deps" | grep -qi "fastapi" && DETECTED_FRAMEWORKS+=("fastapi")
            echo "$py_deps" | grep -qi "pytest" && DETECTED_TEST_FRAMEWORKS+=("pytest")
        fi
    fi
    
    # --- Ruby ---
    if [[ -f "$project_dir/Gemfile" ]]; then
        DETECTED_LANGUAGES+=("ruby")
        DETECTED_PACKAGE_MANAGERS+=("bundler")
        
        local gemfile_content
        gemfile_content="$(cat "$project_dir/Gemfile")"
        echo "$gemfile_content" | grep -q "rails" && DETECTED_FRAMEWORKS+=("rails")
        echo "$gemfile_content" | grep -q "rspec" && DETECTED_TEST_FRAMEWORKS+=("rspec")
        echo "$gemfile_content" | grep -q "minitest" && DETECTED_TEST_FRAMEWORKS+=("minitest")
    fi
    
    # --- Go ---
    if [[ -f "$project_dir/go.mod" ]]; then
        DETECTED_LANGUAGES+=("go")
        DETECTED_PACKAGE_MANAGERS+=("go-modules")
        DETECTED_TEST_FRAMEWORKS+=("go-test")
    fi
    
    # --- Rust ---
    if [[ -f "$project_dir/Cargo.toml" ]]; then
        DETECTED_LANGUAGES+=("rust")
        DETECTED_PACKAGE_MANAGERS+=("cargo")
        DETECTED_TEST_FRAMEWORKS+=("cargo-test")
    fi
    
    # --- PHP ---
    if [[ -f "$project_dir/composer.json" ]]; then
        DETECTED_LANGUAGES+=("php")
        DETECTED_PACKAGE_MANAGERS+=("composer")
        
        if command -v jq &>/dev/null; then
            local php_deps
            php_deps="$(jq -r '(.require // {}) + (."require-dev" // {}) | keys[]' "$project_dir/composer.json" 2>/dev/null || true)"
            echo "$php_deps" | grep -q "laravel/framework" && DETECTED_FRAMEWORKS+=("laravel")
            echo "$php_deps" | grep -q "symfony/" && DETECTED_FRAMEWORKS+=("symfony")
            echo "$php_deps" | grep -q "phpunit/" && DETECTED_TEST_FRAMEWORKS+=("phpunit")
        fi
    fi
    
    # --- Java / Kotlin ---
    if [[ -f "$project_dir/pom.xml" ]]; then
        DETECTED_LANGUAGES+=("java")
        DETECTED_PACKAGE_MANAGERS+=("maven")
    elif [[ -f "$project_dir/build.gradle" || -f "$project_dir/build.gradle.kts" ]]; then
        DETECTED_LANGUAGES+=("java")
        DETECTED_PACKAGE_MANAGERS+=("gradle")
        [[ -f "$project_dir/build.gradle.kts" ]] && DETECTED_LANGUAGES+=("kotlin")
    fi
    
    # --- Shell ---
    if [[ -f "$project_dir/.shellcheckrc" ]] || find "$project_dir" -maxdepth 2 -name "*.sh" -type f 2>/dev/null | head -1 | grep -q .; then
        DETECTED_LANGUAGES+=("bash")
    fi
    if find "$project_dir/test" -name "*.bats" -type f 2>/dev/null | head -1 | grep -q .; then
        DETECTED_TEST_FRAMEWORKS+=("bats")
    fi
    
    # --- CI detection ---
    [[ -d "$project_dir/.github/workflows" ]] && DETECTED_CI+=("github-actions")
    [[ -f "$project_dir/.gitlab-ci.yml" ]] && DETECTED_CI+=("gitlab-ci")
    [[ -f "$project_dir/.circleci/config.yml" ]] && DETECTED_CI+=("circleci")
    [[ -f "$project_dir/Jenkinsfile" ]] && DETECTED_CI+=("jenkins")
    
    return 0
}

# Detect files that should be copied to worktrees
detect_copy_files() {
    local project_dir="${1:-.}"
    
    DETECTED_COPY_FILES=()
    
    local candidates=(
        ".env"
        ".env.local"
        ".env.development"
        ".env.development.local"
        ".envrc"
        ".npmrc"
        ".yarnrc.yml"
        "config/master.key"
        "config/credentials.yml.enc"
        "config/database.yml"
        ".ruby-version"
        ".node-version"
        ".nvmrc"
        ".python-version"
        ".tool-versions"
    )
    
    for file in "${candidates[@]}"; do
        if [[ -f "$project_dir/$file" ]]; then
            DETECTED_COPY_FILES+=("$file")
        fi
    done
    
    return 0
}

# Check if array contains a value (safe for empty arrays)
_array_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Detect project type categories for workflow suggestion
detect_project_type() {
    local has_frontend=false
    local has_backend=false
    local has_fullstack=false
    local has_cli=false
    local has_lib=false
    
    # Frontend indicators
    if [[ ${#DETECTED_FRAMEWORKS[@]} -gt 0 ]]; then
        for fw in react vue svelte angular nextjs; do
            if _array_contains "$fw" "${DETECTED_FRAMEWORKS[@]}"; then
                has_frontend=true
                break
            fi
        done
        
        # Backend indicators
        for fw in express fastify nestjs hono django flask fastapi rails laravel symfony; do
            if _array_contains "$fw" "${DETECTED_FRAMEWORKS[@]}"; then
                has_backend=true
                break
            fi
        done
        
        # Fullstack
        if [[ "$has_frontend" == "true" && "$has_backend" == "true" ]]; then
            has_fullstack=true
        fi
        if _array_contains "nextjs" "${DETECTED_FRAMEWORKS[@]}"; then
            has_fullstack=true
        fi
    fi
    
    # CLI / Library
    if [[ "${#DETECTED_FRAMEWORKS[@]}" -eq 0 ]]; then
        if [[ ${#DETECTED_LANGUAGES[@]} -gt 0 ]] && _array_contains "bash" "${DETECTED_LANGUAGES[@]}"; then
            has_cli=true
        elif [[ -d "bin/" ]] || [[ -d "cmd/" ]]; then
            has_cli=true
        else
            has_lib=true
        fi
    fi
    
    PROJECT_HAS_FRONTEND="$has_frontend"
    PROJECT_HAS_BACKEND="$has_backend"
    PROJECT_HAS_FULLSTACK="$has_fullstack"
    PROJECT_HAS_CLI="$has_cli"
    PROJECT_HAS_LIB="$has_lib"
    PROJECT_HAS_TESTS="${#DETECTED_TEST_FRAMEWORKS[@]}"
}

# ============================================================================
# YAML generation
# ============================================================================

# Generate the YAML config
generate_yaml() {
    local include_workflows="${1:-true}"
    
    cat << 'HEADER'
# pi-issue-runner configuration
# Generated by: generate-config.sh
# Schema: https://github.com/takemo101/pi-issue-runner/schemas/pi-runner.schema.json
# Docs: https://github.com/takemo101/pi-issue-runner/blob/main/docs/configuration.md
HEADER
    
    echo ""
    
    # --- worktree ---
    echo "# ====================================="
    echo "# Worktree設定"
    echo "# ====================================="
    echo "worktree:"
    echo "  base_dir: \".worktrees\""
    
    if [[ ${#DETECTED_COPY_FILES[@]} -gt 0 ]]; then
        echo "  copy_files:"
        for f in "${DETECTED_COPY_FILES[@]}"; do
            echo "    - \"$f\""
        done
    else
        echo "  # copy_files:"
        echo "  #   - .env"
        echo "  #   - .env.local"
    fi
    
    echo ""
    
    # --- multiplexer ---
    echo "# ====================================="
    echo "# マルチプレクサ設定"
    echo "# ====================================="
    echo "multiplexer:"
    
    # Detect available multiplexer
    if command -v zellij &>/dev/null && ! command -v tmux &>/dev/null; then
        echo "  type: zellij"
    else
        echo "  type: tmux"
    fi
    
    # Use repo name as prefix if possible
    local repo_name
    repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
    repo_name="$(echo "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
    if [[ -n "$repo_name" && "$repo_name" != "." ]]; then
        echo "  session_prefix: \"$repo_name\""
    else
        echo "  session_prefix: \"pi\""
    fi
    
    echo ""
    
    # --- agent ---
    echo "# ====================================="
    echo "# エージェント設定"
    echo "# ====================================="
    if command -v pi &>/dev/null; then
        echo "agent:"
        echo "  type: pi"
        echo "  # args:"
        echo "  #   - --model"
        echo "  #   - claude-sonnet-4-20250514"
    elif command -v claude &>/dev/null; then
        echo "agent:"
        echo "  type: claude"
    else
        echo "# agent:"
        echo "#   type: pi"
        echo "#   args:"
        echo "#     - --model"
        echo "#     - claude-sonnet-4-20250514"
    fi
    
    echo ""
    
    # --- parallel ---
    echo "# ====================================="
    echo "# 並列実行設定"
    echo "# ====================================="
    echo "parallel:"
    echo "  max_concurrent: 3"
    
    echo ""
    
    # --- default workflow ---
    echo "# ====================================="
    echo "# デフォルトワークフロー"
    echo "# ====================================="
    echo "workflow:"
    if [[ "$PROJECT_HAS_TESTS" -gt 0 ]]; then
        echo "  steps:"
        echo "    - plan"
        echo "    - implement"
        echo "    - test"
        echo "    - review"
        echo "    - merge"
    else
        echo "  steps:"
        echo "    - plan"
        echo "    - implement"
        echo "    - review"
        echo "    - merge"
    fi
    
    echo ""
    
    # --- named workflows ---
    if [[ "$include_workflows" == "true" ]]; then
        echo "# ====================================="
        echo "# 名前付きワークフロー"
        echo "# ====================================="
        echo "workflows:"
        
        # Quick workflow (always useful)
        echo "  quick:"
        echo "    description: 小規模修正（typo、設定変更、1ファイル程度の変更）"
        echo "    steps:"
        echo "      - implement"
        echo "      - merge"
        echo ""
        
        # Thorough workflow (always useful)
        echo "  thorough:"
        echo "    description: 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更）"
        echo "    steps:"
        echo "      - plan"
        echo "      - implement"
        echo "      - test"
        echo "      - review"
        echo "      - merge"
        echo ""
        
        # Frontend workflow
        if [[ "$PROJECT_HAS_FRONTEND" == "true" ]]; then
            echo "  frontend:"
            echo "    description: フロントエンド実装（UIコンポーネント、スタイリング、画面レイアウト）"
            echo "    steps:"
            echo "      - plan"
            echo "      - implement"
            echo "      - review"
            echo "      - merge"
            echo "    context: |"
            echo "      ## 技術スタック"
            # List frontend frameworks
            for fw in "${DETECTED_FRAMEWORKS[@]}"; do
                case "$fw" in
                    react|vue|svelte|angular|nextjs|tailwindcss)
                        echo "      - $fw"
                        ;;
                esac
            done
            if printf '%s\n' "${DETECTED_LANGUAGES[@]}" | grep -qx "typescript" 2>/dev/null; then
                echo "      - TypeScript"
            fi
            echo "      "
            echo "      ## 重視すべき点"
            echo "      - レスポンシブデザイン"
            echo "      - アクセシビリティ"
            echo "      - コンポーネントの再利用性"
            echo ""
        fi
        
        # Backend workflow
        if [[ "$PROJECT_HAS_BACKEND" == "true" ]]; then
            echo "  backend:"
            echo "    description: バックエンドAPI実装（DB操作、認証、ビジネスロジック）"
            echo "    steps:"
            echo "      - plan"
            echo "      - implement"
            echo "      - test"
            echo "      - review"
            echo "      - merge"
            echo "    context: |"
            echo "      ## 技術スタック"
            for fw in "${DETECTED_FRAMEWORKS[@]}"; do
                case "$fw" in
                    express|fastify|nestjs|hono|django|flask|fastapi|rails|laravel|symfony|prisma|drizzle)
                        echo "      - $fw"
                        ;;
                esac
            done
            echo "      "
            echo "      ## 重視すべき点"
            echo "      - API設計"
            echo "      - 入力バリデーション"
            echo "      - エラーハンドリング"
            echo "      - テストの充実"
            echo ""
        fi
        
        # Docs workflow
        echo "  docs:"
        echo "    description: ドキュメント作成・更新（README、仕様書、ADR）"
        echo "    steps:"
        echo "      - implement"
        echo "      - review"
        echo "      - merge"
        echo "    context: |"
        echo "      ## 目的"
        echo "      ドキュメントの作成・更新に特化する。"
        echo "      コードの変更は原則行わない。"
    fi
    
    echo ""
    
    # --- github ---
    echo "# ====================================="
    echo "# GitHub設定"
    echo "# ====================================="
    echo "github:"
    echo "  include_comments: true"
    echo "  max_comments: 10"
    
    echo ""
    
    # --- plans ---
    echo "# ====================================="
    echo "# 計画書設定"
    echo "# ====================================="
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
        yq -o json "$config_file" | python3 -c "
import json, sys
try:
    from jsonschema import validate, ValidationError
    with open('$schema_file') as f:
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
# Report
# ============================================================================

print_detection_report() {
    echo ""
    echo "📋 プロジェクト解析結果"
    echo "========================"
    
    if [[ ${#DETECTED_LANGUAGES[@]} -gt 0 ]]; then
        echo "言語:               $(IFS=', '; echo "${DETECTED_LANGUAGES[*]}")"
    else
        echo "言語:               (未検出)"
    fi
    
    if [[ ${#DETECTED_FRAMEWORKS[@]} -gt 0 ]]; then
        echo "フレームワーク:     $(IFS=', '; echo "${DETECTED_FRAMEWORKS[*]}")"
    fi
    
    if [[ ${#DETECTED_TEST_FRAMEWORKS[@]} -gt 0 ]]; then
        echo "テスト:             $(IFS=', '; echo "${DETECTED_TEST_FRAMEWORKS[*]}")"
    fi
    
    if [[ ${#DETECTED_PACKAGE_MANAGERS[@]} -gt 0 ]]; then
        echo "パッケージマネージャ: $(IFS=', '; echo "${DETECTED_PACKAGE_MANAGERS[*]}")"
    fi
    
    if [[ ${#DETECTED_CI[@]} -gt 0 ]]; then
        echo "CI:                 $(IFS=', '; echo "${DETECTED_CI[*]}")"
    fi
    
    if [[ ${#DETECTED_COPY_FILES[@]} -gt 0 ]]; then
        echo "コピー対象ファイル: $(IFS=', '; echo "${DETECTED_COPY_FILES[*]}")"
    fi
    
    echo ""
    echo "プロジェクトタイプ:"
    [[ "$PROJECT_HAS_FULLSTACK" == "true" ]] && echo "  ✅ フルスタック" || true
    [[ "$PROJECT_HAS_FRONTEND" == "true" && "$PROJECT_HAS_FULLSTACK" != "true" ]] && echo "  ✅ フロントエンド" || true
    [[ "$PROJECT_HAS_BACKEND" == "true" && "$PROJECT_HAS_FULLSTACK" != "true" ]] && echo "  ✅ バックエンド" || true
    [[ "$PROJECT_HAS_CLI" == "true" ]] && echo "  ✅ CLI / スクリプト" || true
    [[ "$PROJECT_HAS_LIB" == "true" ]] && echo "  ✅ ライブラリ" || true
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    local output_file=".pi-runner.yaml"
    local dry_run=false
    local force=false
    local include_workflows=true
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
            --no-workflows)
                include_workflows=false
                shift
                ;;
            --validate)
                validate_only=true
                shift
                ;;
            -h|--help)
                cat << 'HELP'
Usage: generate-config.sh [options]

プロジェクトの構造を解析し、最適な .pi-runner.yaml を生成します。

Options:
    -o, --output FILE   出力ファイルパス (default: .pi-runner.yaml)
    --dry-run           ファイルに書き込まず標準出力に表示
    --force             既存ファイルを上書き
    --no-workflows      ワークフロー生成をスキップ
    --validate          既存の設定をスキーマで検証
    -h, --help          このヘルプを表示

Examples:
    generate-config.sh                  # 解析して .pi-runner.yaml を生成
    generate-config.sh --dry-run        # 結果をプレビュー
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
    
    # Run detection
    log_info "プロジェクトを解析中..."
    detect_stack "."
    detect_copy_files "."
    detect_project_type
    
    # Print report
    print_detection_report
    
    # Generate config
    local yaml_content
    yaml_content="$(generate_yaml "$include_workflows")"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "--- 生成される設定 ---"
        echo "$yaml_content"
        echo "--- ここまで ---"
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
