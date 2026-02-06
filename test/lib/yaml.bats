#!/usr/bin/env bats
# yaml.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    source "$PROJECT_ROOT/lib/yaml.sh"
    
    # YAMLファイルキャッシュをリセット
    reset_yaml_cache
    
    # テスト用設定ファイルを作成
    export TEST_YAML="${BATS_TEST_TMPDIR}/test.yaml"
    cat > "$TEST_YAML" << 'EOF'
# テスト用YAML
name: test-config

worktree:
  base_dir: ".custom-worktrees"
  copy_files:
    - ".env"
    - ".env.local"
    - ".envrc"

tmux:
  session_prefix: "test-prefix"
  start_in_session: false

pi:
  command: "/usr/local/bin/pi"
  args:
    - "--verbose"
    - "--model"
    - "gpt-4"

workflow:
  name: default
  steps:
    - plan
    - implement
    - review
    - merge
EOF
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# check_yq テスト
# ====================

@test "check_yq returns correct status" {
    _YQ_CHECK_RESULT=""
    if command -v yq &>/dev/null; then
        run check_yq
        [ "$status" -eq 0 ]
    else
        run check_yq
        [ "$status" -eq 1 ]
    fi
}

@test "check_yq caches result" {
    _YQ_CHECK_RESULT=""
    check_yq || true
    [ -n "$_YQ_CHECK_RESULT" ]
}

@test "reset_yq_cache clears cache" {
    _YQ_CHECK_RESULT="1"
    reset_yq_cache
    [ -z "$_YQ_CHECK_RESULT" ]
}

# ====================
# ファイルキャッシュテスト
# ====================

@test "yaml_get caches file content" {
    # 最初の呼び出しでキャッシュ
    yaml_get "$TEST_YAML" ".worktree.base_dir"
    [ -n "$_YAML_CACHE_FILE" ]
    [ "$_YAML_CACHE_FILE" = "$TEST_YAML" ]
    [ -n "$_YAML_CACHE_CONTENT" ]
}

@test "yaml_get reuses cache for same file" {
    # 最初の呼び出し
    yaml_get "$TEST_YAML" ".worktree.base_dir"
    first_content="$_YAML_CACHE_CONTENT"
    
    # 2回目の呼び出し（異なるパス）
    yaml_get "$TEST_YAML" ".tmux.session_prefix"
    [ "$_YAML_CACHE_FILE" = "$TEST_YAML" ]
    [ "$_YAML_CACHE_CONTENT" = "$first_content" ]
}

@test "yaml_get clears cache on different file" {
    yaml_get "$TEST_YAML" ".worktree.base_dir"
    first_cache="$_YAML_CACHE_FILE"
    
    # 別ファイル（存在しない場合はデフォルト値を返す）
    local other_yaml="${BATS_TEST_TMPDIR}/other.yaml"
    cat > "$other_yaml" << 'EOF'
other:
  key: value
EOF
    
    yaml_get "$other_yaml" ".other.key"
    [ "$_YAML_CACHE_FILE" = "$other_yaml" ]
    [ "$_YAML_CACHE_FILE" != "$first_cache" ]
}

@test "reset_yaml_cache clears file cache" {
    yaml_get "$TEST_YAML" ".worktree.base_dir"
    [ -n "$_YAML_CACHE_FILE" ]
    [ -n "$_YAML_CACHE_CONTENT" ]
    
    reset_yaml_cache
    [ -z "$_YAML_CACHE_FILE" ]
    [ -z "$_YAML_CACHE_CONTENT" ]
}

@test "yaml_get_array uses cache" {
    # 配列取得でもキャッシュを使用
    yaml_get_array "$TEST_YAML" ".worktree.copy_files"
    [ -n "$_YAML_CACHE_FILE" ]
    [ "$_YAML_CACHE_FILE" = "$TEST_YAML" ]
}

@test "yaml_exists uses cache" {
    # 存在確認でもキャッシュを使用
    yaml_exists "$TEST_YAML" ".workflow"
    [ -n "$_YAML_CACHE_FILE" ]
    [ "$_YAML_CACHE_FILE" = "$TEST_YAML" ]
}

# ====================
# yaml_get テスト
# ====================

@test "yaml_get returns value for simple path" {
    result="$(yaml_get "$TEST_YAML" ".worktree.base_dir")"
    [ "$result" = ".custom-worktrees" ]
}

@test "yaml_get returns value for nested path" {
    result="$(yaml_get "$TEST_YAML" ".tmux.session_prefix")"
    [ "$result" = "test-prefix" ]
}

@test "yaml_get returns default for missing path" {
    result="$(yaml_get "$TEST_YAML" ".nonexistent.key" "default-value")"
    [ "$result" = "default-value" ]
}

@test "yaml_get returns default for missing file" {
    result="$(yaml_get "/nonexistent/file.yaml" ".key" "default")"
    [ "$result" = "default" ]
}

@test "yaml_get returns empty for missing path without default" {
    result="$(yaml_get "$TEST_YAML" ".nonexistent")"
    [ -z "$result" ]
}

@test "yaml_get handles top-level key" {
    result="$(yaml_get "$TEST_YAML" ".name")"
    [ "$result" = "test-config" ]
}

# ====================
# yaml_get_array テスト
# ====================

@test "yaml_get_array returns array items" {
    result="$(yaml_get_array "$TEST_YAML" ".worktree.copy_files" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = ".env .env.local .envrc" ]
}

@test "yaml_get_array returns workflow steps" {
    result="$(yaml_get_array "$TEST_YAML" ".workflow.steps" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = "plan implement review merge" ]
}

@test "yaml_get_array returns pi args" {
    result="$(yaml_get_array "$TEST_YAML" ".pi.args" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = "--verbose --model gpt-4" ]
}

@test "yaml_get_array returns empty for missing path" {
    result="$(yaml_get_array "$TEST_YAML" ".nonexistent.array")"
    [ -z "$result" ]
}

@test "yaml_get_array returns empty for missing file" {
    result="$(yaml_get_array "/nonexistent/file.yaml" ".array")"
    [ -z "$result" ]
}

@test "yaml_get_array counts correct number of items" {
    count="$(yaml_get_array "$TEST_YAML" ".worktree.copy_files" | wc -l | tr -d ' ')"
    [ "$count" = "3" ]
}

# ====================
# yaml_exists テスト
# ====================

@test "yaml_exists returns true for existing section" {
    run yaml_exists "$TEST_YAML" ".workflow"
    [ "$status" -eq 0 ]
}

@test "yaml_exists returns true for existing nested key" {
    run yaml_exists "$TEST_YAML" ".worktree.base_dir"
    [ "$status" -eq 0 ]
}

@test "yaml_exists returns false for missing section" {
    run yaml_exists "$TEST_YAML" ".nonexistent"
    [ "$status" -eq 1 ]
}

@test "yaml_exists returns false for missing file" {
    run yaml_exists "/nonexistent/file.yaml" ".key"
    [ "$status" -eq 1 ]
}

# ====================
# フォールバックパーサー直接テスト
# ====================

@test "_simple_yaml_get parses value correctly" {
    result="$(_simple_yaml_get "$TEST_YAML" ".worktree.base_dir")"
    [ "$result" = ".custom-worktrees" ]
}

@test "_simple_yaml_get returns default for missing" {
    result="$(_simple_yaml_get "$TEST_YAML" ".missing" "fallback")"
    [ "$result" = "fallback" ]
}

@test "_simple_yaml_get_array parses array correctly" {
    result="$(_simple_yaml_get_array "$TEST_YAML" ".worktree.copy_files" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = ".env .env.local .envrc" ]
}

@test "_simple_yaml_exists detects existing section" {
    run _simple_yaml_exists "$TEST_YAML" ".workflow"
    [ "$status" -eq 0 ]
}

@test "_simple_yaml_exists returns false for missing" {
    run _simple_yaml_exists "$TEST_YAML" ".missing"
    [ "$status" -eq 1 ]
}

# ====================
# クォート処理テスト
# ====================

@test "yaml_get handles quoted values" {
    local quoted_yaml="${BATS_TEST_TMPDIR}/quoted.yaml"
    cat > "$quoted_yaml" << 'EOF'
section:
  single_quoted: 'value with spaces'
  double_quoted: "another value"
  unquoted: plain_value
EOF
    
    result="$(yaml_get "$quoted_yaml" ".section.unquoted")"
    [ "$result" = "plain_value" ]
}

# ====================
# エッジケーステスト
# ====================

@test "yaml_get handles empty file" {
    local empty_yaml="${BATS_TEST_TMPDIR}/empty.yaml"
    touch "$empty_yaml"
    
    result="$(yaml_get "$empty_yaml" ".key" "default")"
    [ "$result" = "default" ]
}

@test "yaml_get_array handles empty array section" {
    local no_array_yaml="${BATS_TEST_TMPDIR}/no-array.yaml"
    cat > "$no_array_yaml" << 'EOF'
section:
  key: value
EOF
    
    result="$(yaml_get_array "$no_array_yaml" ".section.items")"
    [ -z "$result" ]
}

# ====================
# ハイフン含むキーのテスト (Issue #902)
# ====================

@test "yaml_get parses hyphenated key" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen.yaml"
    cat > "$hyphen_yaml" << 'EOF'
agents:
  ci-fix: custom/ci-fix.md
  test-agent: custom/test.md
EOF
    
    result="$(yaml_get "$hyphen_yaml" ".agents.ci-fix")"
    [ "$result" = "custom/ci-fix.md" ]
}

@test "yaml_get parses multiple hyphenated sections" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-sections.yaml"
    cat > "$hyphen_yaml" << 'EOF'
multi-word-section:
  nested-key: test-value-123
  another-key: value2
EOF
    
    result="$(yaml_get "$hyphen_yaml" ".multi-word-section.nested-key")"
    [ "$result" = "test-value-123" ]
}

@test "yaml_get parses keys with numbers and hyphens" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-numbers.yaml"
    cat > "$hyphen_yaml" << 'EOF'
section:
  key-with-123: value123
  test2-key: another-value
EOF
    
    result="$(yaml_get "$hyphen_yaml" ".section.key-with-123")"
    [ "$result" = "value123" ]
}

@test "yaml_get_array parses hyphenated array key" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-array.yaml"
    cat > "$hyphen_yaml" << 'EOF'
copy-files:
  - file-1.txt
  - file-2.txt
  - test-file-3.md
EOF
    
    result="$(yaml_get_array "$hyphen_yaml" ".copy-files" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = "file-1.txt file-2.txt test-file-3.md" ]
}

@test "yaml_get_array parses nested hyphenated array" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-nested-array.yaml"
    cat > "$hyphen_yaml" << 'EOF'
workflow-config:
  step-names:
    - plan-step
    - implement-step
    - review-step
EOF
    
    result="$(yaml_get_array "$hyphen_yaml" ".workflow-config.step-names" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = "plan-step implement-step review-step" ]
}

@test "yaml_exists detects hyphenated section" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-exists.yaml"
    cat > "$hyphen_yaml" << 'EOF'
ci-config:
  enabled: true
EOF
    
    run yaml_exists "$hyphen_yaml" ".ci-config"
    [ "$status" -eq 0 ]
}

@test "yaml_exists detects hyphenated nested key" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/hyphen-nested-exists.yaml"
    cat > "$hyphen_yaml" << 'EOF'
agents:
  ci-fix: template.md
EOF
    
    run yaml_exists "$hyphen_yaml" ".agents.ci-fix"
    [ "$status" -eq 0 ]
}

@test "_simple_yaml_get directly parses hyphenated keys" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/simple-hyphen.yaml"
    cat > "$hyphen_yaml" << 'EOF'
test-section:
  nested-key: direct-value
EOF
    
    result="$(_simple_yaml_get "$hyphen_yaml" ".test-section.nested-key")"
    [ "$result" = "direct-value" ]
}

@test "_simple_yaml_get_array directly parses hyphenated array" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/simple-hyphen-array.yaml"
    cat > "$hyphen_yaml" << 'EOF'
test-section:
  test-array:
    - item-1
    - item-2
EOF
    
    result="$(_simple_yaml_get_array "$hyphen_yaml" ".test-section.test-array" | tr '\n' ' ' | sed 's/ $//')"
    [ "$result" = "item-1 item-2" ]
}

@test "_simple_yaml_exists directly detects hyphenated keys" {
    local hyphen_yaml="${BATS_TEST_TMPDIR}/simple-exists-hyphen.yaml"
    cat > "$hyphen_yaml" << 'EOF'
ci-config:
  retry-count: 3
EOF
    
    run _simple_yaml_exists "$hyphen_yaml" ".ci-config.retry-count"
    [ "$status" -eq 0 ]
}
