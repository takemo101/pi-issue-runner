#!/usr/bin/env bats
# workflow-selector.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定キャッシュをリセット
    unset _CONFIG_SH_SOURCED
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    # YAMLキャッシュをリセット
    _YQ_CHECK_RESULT=""
    reset_yaml_cache
    
    # テスト用ディレクトリ
    export TEST_DIR="$BATS_TEST_TMPDIR/selector_test"
    mkdir -p "$TEST_DIR"
    
    # PI_COMMANDをモック化（AI呼び出しを無効化）
    export PI_COMMAND="false"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# _select_workflow_by_rules テスト
# ===================

@test "rules: feat: prefix selects feature workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "feat: add new command" "$valid")
    [ "$result" = "feature" ]
}

@test "rules: fix: prefix selects fix workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "fix: resolve crash on startup" "$valid")
    [ "$result" = "fix" ]
}

@test "rules: bug: prefix selects fix workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "bug: cleanup-orphans.sh のバグ" "$valid")
    [ "$result" = "fix" ]
}

@test "rules: refactor: prefix selects fix workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "refactor: simplify config loading" "$valid")
    [ "$result" = "fix" ]
}

@test "rules: security: prefix selects fix workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "security: sanitize input" "$valid")
    [ "$result" = "fix" ]
}

@test "rules: docs: prefix selects docs workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "docs: update README" "$valid")
    [ "$result" = "docs" ]
}

@test "rules: test: prefix selects test workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "test: add edge case tests" "$valid")
    [ "$result" = "test" ]
}

@test "rules: chore: prefix selects quickfix workflow" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "chore: update dependencies" "$valid")
    [ "$result" = "quickfix" ]
}

@test "rules: unknown prefix returns empty" {
    local valid="feature
fix
docs
test
quickfix"
    run _select_workflow_by_rules "implement something" "$valid"
    [ "$status" -ne 0 ]
}

@test "rules: case insensitive matching" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "FEAT: uppercase prefix" "$valid")
    [ "$result" = "feature" ]
}

@test "rules: feat(scope) conventional commit format" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "feat(workflow): add auto mode" "$valid")
    [ "$result" = "feature" ]
}

@test "rules: fix(scope) conventional commit format" {
    local valid="feature
fix
docs
test
quickfix"
    result=$(_select_workflow_by_rules "fix(yaml): parser bug" "$valid")
    [ "$result" = "fix" ]
}

@test "rules: selected workflow must be in valid names" {
    local valid="default
simple"
    # feat: would normally map to "feature" but it's not in valid_names
    # With the fix, it should fall back to "default" which IS in valid_names
    result=$(_select_workflow_by_rules "feat: add command" "$valid")
    [ "$result" = "default" ]
}

# ===================
# resolve_auto_workflow_name テスト（AI無効化、ルールベースのみ）
# ===================

@test "resolve_auto_workflow_name falls back to rules when AI unavailable" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  feature:
    description: New feature
    steps:
      - plan
      - implement
  fix:
    description: Bug fix
    steps:
      - implement
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result=$(resolve_auto_workflow_name "fix: some bug" "bug description" "$TEST_DIR")
    [ "$result" = "fix" ]
}

@test "resolve_auto_workflow_name returns default for unknown prefix" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  feature:
    description: New feature
    steps:
      - implement
  fix:
    description: Bug fix
    steps:
      - implement
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result=$(resolve_auto_workflow_name "something unusual" "body" "$TEST_DIR")
    [ "$result" = "default" ]
}

@test "resolve_auto_workflow_name returns default when no workflows defined" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  steps:
    - implement
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result=$(resolve_auto_workflow_name "feat: add feature" "body" "$TEST_DIR")
    [ "$result" = "default" ]
}

# ===================
# _get_ai_provider / _get_ai_model テスト
# ===================

@test "_get_ai_provider returns config value from .pi-runner.yaml" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
auto:
  provider: google
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    unset _CONFIG_SH_SOURCED
    source "$PROJECT_ROOT/lib/config.sh"
    _CONFIG_LOADED=""
    CONFIG_AUTO_PROVIDER=""
    load_config "$CONFIG_FILE"
    
    result=$(_get_ai_provider)
    [ "$result" = "google" ]
}

@test "_get_ai_provider returns anthropic as default" {
    _CONFIG_LOADED=""
    CONFIG_AUTO_PROVIDER=""
    result=$(_get_ai_provider)
    [ "$result" = "anthropic" ]
}

@test "_get_ai_model returns config value from .pi-runner.yaml" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
auto:
  model: claude-3-haiku-20240307
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    unset _CONFIG_SH_SOURCED
    source "$PROJECT_ROOT/lib/config.sh"
    _CONFIG_LOADED=""
    CONFIG_AUTO_MODEL=""
    load_config "$CONFIG_FILE"
    
    result=$(_get_ai_model)
    [ "$result" = "claude-3-haiku-20240307" ]
}

@test "_get_ai_model returns haiku as default" {
    _CONFIG_LOADED=""
    CONFIG_AUTO_MODEL=""
    result=$(_get_ai_model)
    [ "$result" = "claude-haiku-4-5" ]
}

# ===================
# 回帰テスト: Issue #1016
# ===================

@test "Issue #1016: feat: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "feat: add new command" "$valid")
    [ "$result" = "default" ]
}

@test "Issue #1016: fix: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "fix: resolve bug" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: bug: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "bug: crash on startup" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: docs: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "docs: update README" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: test: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "test: add edge cases" "$valid")
    [ "$result" = "thorough" ]
}

@test "Issue #1016: chore: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "chore: update deps" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: refactor: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "refactor: simplify code" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: security: prefix works with real built-in workflows" {
    local valid="default
simple
thorough
ci-fix"
    result=$(_select_workflow_by_rules "security: sanitize input" "$valid")
    [ "$result" = "simple" ]
}

@test "Issue #1016: falls back to default when only ci-fix is available" {
    local valid="ci-fix
default"
    result=$(_select_workflow_by_rules "feat: new feature" "$valid")
    [ "$result" = "default" ]
}

@test "Issue #1016: unknown prefix with built-in workflows falls back to default" {
    local valid="default
simple"
    result=$(resolve_auto_workflow_name "something unusual" "body" "$TEST_DIR")
    [ "$result" = "default" ]
}
