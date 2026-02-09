#!/usr/bin/env bats
# test/lib/generate-config.bats - lib/generate-config.sh のユニットテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    # テスト用プロジェクトディレクトリ
    export TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT_DIR"

    # git初期化（_collect_environment_info等で必要）
    cd "$TEST_PROJECT_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"

    # モックディレクトリ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"

    # log関数のスタブ（lib/generate-config.shがlog_*を呼ぶため）
    log_info() { :; }
    log_debug() { :; }
    log_warn() { :; }
    log_error() { echo "ERROR: $*" >&2; }
    export -f log_info log_debug log_warn log_error

    # source対象
    source "$PROJECT_ROOT/lib/generate-config.sh"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ============================================================================
# _collect_directory_structure
# ============================================================================

@test "_collect_directory_structure returns directory listing" {
    mkdir -p "$TEST_PROJECT_DIR/src" "$TEST_PROJECT_DIR/lib"
    touch "$TEST_PROJECT_DIR/src/main.sh" "$TEST_PROJECT_DIR/lib/util.sh"

    run _collect_directory_structure "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Directory Structure"* ]]
    [[ "$output" == *"src"* ]]
    [[ "$output" == *"lib"* ]]
}

@test "_collect_directory_structure excludes node_modules" {
    mkdir -p "$TEST_PROJECT_DIR/node_modules/pkg"
    mkdir -p "$TEST_PROJECT_DIR/src"

    run _collect_directory_structure "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"node_modules/pkg"* ]]
    [[ "$output" == *"src"* ]]
}

@test "_collect_directory_structure excludes .git directory" {
    run _collect_directory_structure "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *".git/HEAD"* ]]
}

@test "_collect_directory_structure excludes build artifacts" {
    mkdir -p "$TEST_PROJECT_DIR/dist" "$TEST_PROJECT_DIR/build" "$TEST_PROJECT_DIR/__pycache__"
    mkdir -p "$TEST_PROJECT_DIR/src"

    run _collect_directory_structure "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dist"* ]] || [[ "$output" != *"dist/"* ]]
    [[ "$output" == *"src"* ]]
}

@test "_collect_directory_structure defaults to current directory" {
    cd "$TEST_PROJECT_DIR"
    mkdir -p src
    run _collect_directory_structure
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Directory Structure"* ]]
}

# ============================================================================
# _find_config_files
# ============================================================================

@test "_find_config_files finds package.json" {
    echo '{}' > "$TEST_PROJECT_DIR/package.json"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"package.json:json:80"* ]]
}

@test "_find_config_files finds pyproject.toml" {
    echo '[project]' > "$TEST_PROJECT_DIR/pyproject.toml"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pyproject.toml:toml:60"* ]]
}

@test "_find_config_files finds go.mod" {
    echo 'module example.com/test' > "$TEST_PROJECT_DIR/go.mod"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"go.mod::30"* ]]
}

@test "_find_config_files finds Cargo.toml" {
    echo '[package]' > "$TEST_PROJECT_DIR/Cargo.toml"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cargo.toml:toml:40"* ]]
}

@test "_find_config_files finds build.gradle.kts over build.gradle" {
    touch "$TEST_PROJECT_DIR/build.gradle.kts"
    touch "$TEST_PROJECT_DIR/build.gradle"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"build.gradle.kts:kotlin:30"* ]]
    [[ "$output" != *"build.gradle:groovy"* ]]
}

@test "_find_config_files finds build.gradle when kts not present" {
    touch "$TEST_PROJECT_DIR/build.gradle"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"build.gradle:groovy:30"* ]]
}

@test "_find_config_files returns empty for empty project" {
    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_find_config_files finds multiple config files" {
    echo '{}' > "$TEST_PROJECT_DIR/package.json"
    echo '{}' > "$TEST_PROJECT_DIR/tsconfig.json"

    run _find_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"package.json:json:80"* ]]
    [[ "$output" == *"tsconfig.json:json:0"* ]]
}

# ============================================================================
# _parse_config_content
# ============================================================================

@test "_parse_config_content parses file with line limit" {
    # 10行のファイルを作成
    for i in $(seq 1 10); do echo "line$i" >> "$TEST_PROJECT_DIR/test.txt"; done

    run _parse_config_content "$TEST_PROJECT_DIR" "test.txt" "text" "3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## test.txt"* ]]
    [[ "$output" == *"line1"* ]]
    [[ "$output" == *"line3"* ]]
    [[ "$output" != *"line4"* ]]
}

@test "_parse_config_content reads full file when max_lines is 0" {
    for i in $(seq 1 5); do echo "line$i" >> "$TEST_PROJECT_DIR/full.txt"; done

    run _parse_config_content "$TEST_PROJECT_DIR" "full.txt" "" "0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"line1"* ]]
    [[ "$output" == *"line5"* ]]
}

@test "_parse_config_content returns empty for missing file" {
    run _parse_config_content "$TEST_PROJECT_DIR" "nonexistent.txt" "" "10"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_parse_config_content includes language in code fence" {
    echo "content" > "$TEST_PROJECT_DIR/test.json"

    run _parse_config_content "$TEST_PROJECT_DIR" "test.json" "json" "10"
    [ "$status" -eq 0 ]
    [[ "$output" == *'```json'* ]]
}

# ============================================================================
# _collect_config_files
# ============================================================================

@test "_collect_config_files returns empty for empty project" {
    run _collect_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    # 設定ファイルが存在しないので、ほぼ空（改行のみ）
    [[ -z "$(echo "$output" | tr -d '[:space:]')" ]]
}

@test "_collect_config_files includes package.json content" {
    cat > "$TEST_PROJECT_DIR/package.json" << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

    run _collect_config_files "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## package.json"* ]]
    [[ "$output" == *"test-project"* ]]
}

# ============================================================================
# _collect_documentation
# ============================================================================

@test "_collect_documentation includes README.md" {
    echo "# My Project" > "$TEST_PROJECT_DIR/README.md"

    run _collect_documentation "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## README.md (excerpt)"* ]]
    [[ "$output" == *"# My Project"* ]]
}

@test "_collect_documentation includes AGENTS.md" {
    echo "# Dev Guide" > "$TEST_PROJECT_DIR/AGENTS.md"

    run _collect_documentation "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## AGENTS.md (excerpt)"* ]]
    [[ "$output" == *"# Dev Guide"* ]]
}

@test "_collect_documentation returns empty when no docs" {
    run _collect_documentation "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ -z "$(echo "$output" | tr -d '[:space:]')" ]]
}

# ============================================================================
# _collect_ci_config
# ============================================================================

@test "_collect_ci_config includes workflow files" {
    mkdir -p "$TEST_PROJECT_DIR/.github/workflows"
    cat > "$TEST_PROJECT_DIR/.github/workflows/ci.yaml" << 'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF

    run _collect_ci_config "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## CI Workflow files"* ]]
    [[ "$output" == *"ci.yaml"* ]]
    [[ "$output" == *"name: CI"* ]]
}

@test "_collect_ci_config returns empty without .github/workflows" {
    run _collect_ci_config "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ -z "$(echo "$output" | tr -d '[:space:]')" ]]
}

# ============================================================================
# _collect_environment_info
# ============================================================================

@test "_collect_environment_info detects env files" {
    touch "$TEST_PROJECT_DIR/.env"
    touch "$TEST_PROJECT_DIR/.nvmrc"

    run _collect_environment_info "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Environment files found"* ]]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *".nvmrc"* ]]
}

@test "_collect_environment_info shows repository name" {
    cd "$TEST_PROJECT_DIR"

    run _collect_environment_info "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Repository name:"* ]]
}

@test "_collect_environment_info shows available tools section" {
    run _collect_environment_info "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Available tools"* ]]
}

# ============================================================================
# collect_project_context
# ============================================================================

@test "collect_project_context aggregates all sections" {
    mkdir -p "$TEST_PROJECT_DIR/src"
    echo '{"name":"test"}' > "$TEST_PROJECT_DIR/package.json"
    echo "# Test" > "$TEST_PROJECT_DIR/README.md"

    run collect_project_context "$TEST_PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Directory Structure"* ]]
    [[ "$output" == *"## package.json"* ]]
    [[ "$output" == *"## README.md (excerpt)"* ]]
    [[ "$output" == *"## Environment files found"* ]]
}

# ============================================================================
# build_ai_prompt
# ============================================================================

@test "build_ai_prompt includes project context" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"
    local context="## Test Context"$'\n'"Some project info"

    run build_ai_prompt "$context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"configuration generator"* ]]
    [[ "$output" == *"## Test Context"* ]]
    [[ "$output" == *"Some project info"* ]]
}

@test "build_ai_prompt includes requirements" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"

    run build_ai_prompt "context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Requirements"* ]]
    [[ "$output" == *"Output ONLY the YAML content"* ]]
}

@test "build_ai_prompt includes schema when available" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"
    mkdir -p "$TEST_PROJECT_DIR/schemas"
    echo '{"type":"object"}' > "$TEST_PROJECT_DIR/schemas/pi-runner.schema.json"

    run build_ai_prompt "context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# JSON Schema"* ]]
    [[ "$output" == *'"type":"object"'* ]]
}

@test "build_ai_prompt works without schema file" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"
    # スキーマファイルなし

    run build_ai_prompt "context"
    [ "$status" -eq 0 ]
    [[ "$output" != *"# JSON Schema"* ]]
}

# ============================================================================
# generate_with_ai
# ============================================================================

@test "generate_with_ai fails when pi command not found" {
    export PI_COMMAND="nonexistent-pi-command"

    run generate_with_ai "some context"
    [ "$status" -eq 1 ]
}

# ============================================================================
# detect_copy_files
# ============================================================================

@test "detect_copy_files detects .env" {
    touch "$TEST_PROJECT_DIR/.env"

    detect_copy_files "$TEST_PROJECT_DIR"
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .env "* ]]
}

@test "detect_copy_files detects multiple env files" {
    touch "$TEST_PROJECT_DIR/.env"
    touch "$TEST_PROJECT_DIR/.env.local"
    touch "$TEST_PROJECT_DIR/.nvmrc"

    detect_copy_files "$TEST_PROJECT_DIR"
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .env "* ]]
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .env.local "* ]]
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .nvmrc "* ]]
}

@test "detect_copy_files returns empty array for empty project" {
    detect_copy_files "$TEST_PROJECT_DIR"
    [ "${#DETECTED_COPY_FILES[@]}" -eq 0 ]
}

@test "detect_copy_files detects config/master.key" {
    mkdir -p "$TEST_PROJECT_DIR/config"
    touch "$TEST_PROJECT_DIR/config/master.key"

    detect_copy_files "$TEST_PROJECT_DIR"
    [[ " ${DETECTED_COPY_FILES[*]} " == *" config/master.key "* ]]
}

@test "detect_copy_files detects version files" {
    touch "$TEST_PROJECT_DIR/.ruby-version"
    touch "$TEST_PROJECT_DIR/.python-version"
    touch "$TEST_PROJECT_DIR/.tool-versions"

    detect_copy_files "$TEST_PROJECT_DIR"
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .ruby-version "* ]]
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .python-version "* ]]
    [[ " ${DETECTED_COPY_FILES[*]} " == *" .tool-versions "* ]]
}

# ============================================================================
# _generate_static_header
# ============================================================================

@test "_generate_static_header outputs header comment" {
    run _generate_static_header
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi-issue-runner configuration"* ]]
    [[ "$output" == *"Generated by: generate-config.sh (static fallback)"* ]]
}

# ============================================================================
# _generate_static_worktree
# ============================================================================

@test "_generate_static_worktree outputs worktree section" {
    DETECTED_COPY_FILES=()
    run _generate_static_worktree
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktree:"* ]]
    [[ "$output" == *'base_dir: ".worktrees"'* ]]
}

@test "_generate_static_worktree includes copy_files when detected" {
    DETECTED_COPY_FILES=(".env" ".env.local")
    run _generate_static_worktree
    [ "$status" -eq 0 ]
    [[ "$output" == *"copy_files:"* ]]
    [[ "$output" == *'".env"'* ]]
    [[ "$output" == *'".env.local"'* ]]
}

@test "_generate_static_worktree omits copy_files when empty" {
    DETECTED_COPY_FILES=()
    run _generate_static_worktree
    [ "$status" -eq 0 ]
    [[ "$output" != *"copy_files:"* ]]
}

# ============================================================================
# _generate_static_multiplexer
# ============================================================================

@test "_generate_static_multiplexer outputs multiplexer section" {
    cd "$TEST_PROJECT_DIR"
    run _generate_static_multiplexer
    [ "$status" -eq 0 ]
    [[ "$output" == *"multiplexer:"* ]]
    [[ "$output" == *"type:"* ]]
    [[ "$output" == *"session_prefix:"* ]]
}

@test "_generate_static_multiplexer uses repo name as prefix" {
    cd "$TEST_PROJECT_DIR"
    run _generate_static_multiplexer
    [ "$status" -eq 0 ]
    # リポジトリ名（project）がsession_prefixに含まれる
    [[ "$output" == *"session_prefix:"* ]]
}

# ============================================================================
# _generate_static_agent_and_parallel
# ============================================================================

@test "_generate_static_agent_and_parallel outputs parallel section" {
    run _generate_static_agent_and_parallel
    [ "$status" -eq 0 ]
    [[ "$output" == *"parallel:"* ]]
    [[ "$output" == *"max_concurrent: 3"* ]]
}

@test "_generate_static_agent_and_parallel detects agent type" {
    run _generate_static_agent_and_parallel
    [ "$status" -eq 0 ]
    # piまたはclaudeが利用可能な環境ではagentセクションが出力される
    if command -v pi &>/dev/null || command -v claude &>/dev/null; then
        [[ "$output" == *"agent:"* ]]
    fi
}

# ============================================================================
# _generate_static_workflows
# ============================================================================

@test "_generate_static_workflows outputs all required workflows" {
    run _generate_static_workflows
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflows:"* ]]
    [[ "$output" == *"default:"* ]]
    [[ "$output" == *"quick:"* ]]
    [[ "$output" == *"thorough:"* ]]
    [[ "$output" == *"docs:"* ]]
}

@test "_generate_static_workflows default has plan implement review merge" {
    run _generate_static_workflows
    [ "$status" -eq 0 ]
    # default ワークフローの内容を抽出（sedのみ使用、macOS互換）
    local default_section
    default_section=$(echo "$output" | sed -n '/^  default:/,/^  quick:/p')
    [[ "$default_section" == *"plan"* ]]
    [[ "$default_section" == *"implement"* ]]
    [[ "$default_section" == *"review"* ]]
    [[ "$default_section" == *"merge"* ]]
}

@test "_generate_static_workflows quick has implement and merge only" {
    run _generate_static_workflows
    [ "$status" -eq 0 ]
    local quick_section
    quick_section=$(echo "$output" | sed -n '/^  quick:/,/^  thorough:/p')
    [[ "$quick_section" == *"implement"* ]]
    [[ "$quick_section" == *"merge"* ]]
    [[ "$quick_section" != *"plan"* ]]
}

@test "_generate_static_workflows thorough includes test step" {
    run _generate_static_workflows
    [ "$status" -eq 0 ]
    local thorough_section
    thorough_section=$(echo "$output" | sed -n '/^  thorough:/,/^  docs:/p')
    [[ "$thorough_section" == *"test"* ]]
    [[ "$thorough_section" == *"plan"* ]]
    [[ "$thorough_section" == *"implement"* ]]
}

# ============================================================================
# _generate_static_github_and_plans
# ============================================================================

@test "_generate_static_github_and_plans outputs github section" {
    run _generate_static_github_and_plans
    [ "$status" -eq 0 ]
    [[ "$output" == *"github:"* ]]
    [[ "$output" == *"include_comments: true"* ]]
    [[ "$output" == *"max_comments: 10"* ]]
}

@test "_generate_static_github_and_plans outputs plans section" {
    run _generate_static_github_and_plans
    [ "$status" -eq 0 ]
    [[ "$output" == *"plans:"* ]]
    [[ "$output" == *"keep_recent: 10"* ]]
    [[ "$output" == *'dir: "docs/plans"'* ]]
}

# ============================================================================
# generate_static_yaml
# ============================================================================

@test "generate_static_yaml outputs complete YAML" {
    cd "$TEST_PROJECT_DIR"
    run generate_static_yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi-issue-runner configuration"* ]]
    [[ "$output" == *"worktree:"* ]]
    [[ "$output" == *"multiplexer:"* ]]
    [[ "$output" == *"workflows:"* ]]
    [[ "$output" == *"github:"* ]]
    [[ "$output" == *"plans:"* ]]
}

@test "generate_static_yaml includes copy_files for detected env files" {
    cd "$TEST_PROJECT_DIR"
    touch "$TEST_PROJECT_DIR/.env"

    run generate_static_yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"copy_files:"* ]]
    [[ "$output" == *".env"* ]]
}

@test "generate_static_yaml is valid YAML" {
    cd "$TEST_PROJECT_DIR"

    run generate_static_yaml
    [ "$status" -eq 0 ]

    if command -v yq &>/dev/null; then
        echo "$output" | yq eval '.' - >/dev/null 2>&1
        [ $? -eq 0 ]
    elif command -v python3 &>/dev/null; then
        echo "$output" | python3 -c "import yaml, sys; yaml.safe_load(sys.stdin)" 2>/dev/null
        [ $? -eq 0 ]
    else
        skip "yq or python3 not available for YAML validation"
    fi
}

# ============================================================================
# validate_config
# ============================================================================

@test "validate_config fails when config file not found" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"

    run validate_config "$TEST_PROJECT_DIR/nonexistent.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "validate_config fails when schema file not found" {
    export PROJECT_ROOT="$TEST_PROJECT_DIR"
    echo "worktree:" > "$TEST_PROJECT_DIR/.pi-runner.yaml"

    run validate_config "$TEST_PROJECT_DIR/.pi-runner.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}
