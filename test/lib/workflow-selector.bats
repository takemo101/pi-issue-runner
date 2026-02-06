#!/usr/bin/env bats
# workflow-selector.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
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
    run _select_workflow_by_rules "feat: add command" "$valid"
    [ "$status" -ne 0 ]
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

@test "_get_ai_provider returns env var when set" {
    PI_RUNNER_AI_PROVIDER="openai" run _get_ai_provider
    [ "$output" = "openai" ]
}

@test "_get_ai_provider returns anthropic as default" {
    unset PI_RUNNER_AI_PROVIDER 2>/dev/null || true
    result=$(_get_ai_provider)
    [ "$result" = "anthropic" ]
}

@test "_get_ai_model returns env var when set" {
    PI_RUNNER_AUTO_MODEL="gpt-4" run _get_ai_model
    [ "$output" = "gpt-4" ]
}

@test "_get_ai_model returns haiku as default" {
    unset PI_RUNNER_AUTO_MODEL 2>/dev/null || true
    result=$(_get_ai_model)
    [ "$result" = "claude-3-5-haiku-20241022" ]
}
