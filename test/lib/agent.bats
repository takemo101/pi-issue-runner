#!/usr/bin/env bats
# agent.sh のBatsテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    # YAMLキャッシュをリセット（並列テストでのキャッシュ汚染防止）
    source "$PROJECT_ROOT/lib/yaml.sh"
    reset_yaml_cache
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_AGENT_TYPE
    unset CONFIG_AGENT_COMMAND
    unset CONFIG_AGENT_ARGS
    unset CONFIG_AGENT_TEMPLATE
    unset CONFIG_PI_COMMAND
    unset CONFIG_PI_ARGS
    unset PI_RUNNER_AGENT_TYPE
    unset PI_RUNNER_AGENT_COMMAND
    unset PI_RUNNER_AGENT_ARGS
    unset PI_RUNNER_AGENT_TEMPLATE
    
    # テスト用ディレクトリ構造を作成
    export TEST_DIR="$BATS_TEST_TMPDIR/agent_test"
    mkdir -p "$TEST_DIR"
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# プリセット取得テスト
# ====================

@test "get_agent_preset returns pi command" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "pi" "command")"
    [ "$result" = "pi" ]
}

@test "get_agent_preset returns pi template" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "pi" "template")"
    [[ "$result" == *'@"{{prompt_file}}"'* ]]
}

@test "get_agent_preset returns claude command" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "claude" "command")"
    [ "$result" = "claude" ]
}

@test "get_agent_preset returns claude template with --print" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "claude" "template")"
    [[ "$result" == *'--print'* ]]
}

@test "get_agent_preset returns opencode command" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "opencode" "command")"
    [ "$result" = "opencode" ]
}

@test "get_agent_preset returns opencode template with stdin" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "opencode" "template")"
    [[ "$result" == *'cat'* ]]
}

@test "get_agent_preset returns empty for unknown preset" {
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_preset "unknown" "command")"
    [ -z "$result" ]
}

# ====================
# preset_exists テスト
# ====================

@test "preset_exists returns 0 for pi" {
    source "$PROJECT_ROOT/lib/agent.sh"
    preset_exists "pi"
}

@test "preset_exists returns 0 for claude" {
    source "$PROJECT_ROOT/lib/agent.sh"
    preset_exists "claude"
}

@test "preset_exists returns 0 for opencode" {
    source "$PROJECT_ROOT/lib/agent.sh"
    preset_exists "opencode"
}

@test "preset_exists returns 1 for unknown" {
    source "$PROJECT_ROOT/lib/agent.sh"
    ! preset_exists "unknown"
}

# ====================
# get_agent_type テスト
# ====================

@test "get_agent_type returns pi as default" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_type)"
    [ "$result" = "pi" ]
}

@test "get_agent_type returns configured type" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: claude
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_type)"
    [ "$result" = "claude" ]
}

# ====================
# get_agent_command テスト
# ====================

@test "get_agent_command returns pi for default" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_command)"
    [ "$result" = "pi" ]
}

@test "get_agent_command returns claude preset command" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: claude
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_command)"
    [ "$result" = "claude" ]
}

@test "get_agent_command returns custom command" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: custom
  command: my-agent
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_command)"
    [ "$result" = "my-agent" ]
}

@test "get_agent_command falls back to pi.command" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
pi:
  command: /usr/local/bin/pi
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_command)"
    [ "$result" = "/usr/local/bin/pi" ]
}

# ====================
# get_agent_template テスト
# ====================

@test "get_agent_template returns pi template by default" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_template)"
    [[ "$result" == *'@"{{prompt_file}}"'* ]]
}

@test "get_agent_template returns claude template" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: claude
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_template)"
    [[ "$result" == *'--print'* ]]
}

@test "get_agent_template returns custom template" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: custom
  template: '{{command}} --custom {{prompt_file}}'
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_template)"
    [[ "$result" == *'--custom'* ]]
}

# ====================
# build_agent_command テスト
# ====================

@test "build_agent_command generates pi command" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(build_agent_command "/path/to/prompt.md" "")"
    [[ "$result" == *'pi'* ]]
    [[ "$result" == *'@"/path/to/prompt.md"'* ]]
}

@test "build_agent_command generates claude command" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: claude
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(build_agent_command "/path/to/prompt.md" "")"
    [[ "$result" == *'claude'* ]]
    [[ "$result" == *'--print'* ]]
}

@test "build_agent_command generates opencode command" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: opencode
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(build_agent_command "/path/to/prompt.md" "")"
    [[ "$result" == *'cat'* ]]
    [[ "$result" == *'opencode'* ]]
}

@test "build_agent_command includes extra args" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(build_agent_command "/path/to/prompt.md" "--verbose")"
    [[ "$result" == *'--verbose'* ]]
}

@test "build_agent_command includes config args and extra args" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--model"
    - "gpt-4"
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(build_agent_command "/path/to/prompt.md" "--verbose")"
    [[ "$result" == *'--model'* ]]
    [[ "$result" == *'gpt-4'* ]]
    [[ "$result" == *'--verbose'* ]]
}

# ====================
# 後方互換性テスト
# ====================

@test "pi.command is used when agent section is not configured" {
    local test_config="${BATS_TEST_TMPDIR}/pi-only-config.yaml"
    cat > "$test_config" << 'EOF'
pi:
  command: /custom/pi
  args:
    - "--custom-arg"
EOF
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # コマンドがpi.commandにフォールバックする
    result="$(get_agent_command)"
    [ "$result" = "/custom/pi" ]
    
    # 引数がpi.argsにフォールバックする
    args="$(get_agent_args)"
    [ "$args" = "--custom-arg" ]
}

# ====================
# 環境変数オーバーライドテスト
# ====================

@test "environment variable overrides agent_type" {
    export PI_RUNNER_AGENT_TYPE="opencode"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_type)"
    [ "$result" = "opencode" ]
}

@test "environment variable overrides agent_command" {
    export PI_RUNNER_AGENT_COMMAND="/custom/agent"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    result="$(get_agent_command)"
    [ "$result" = "/custom/agent" ]
}

# ========================================
# apply_workflow_agent_override テスト
# ========================================

@test "apply_workflow_agent_override sets CONFIG_AGENT_TYPE from workflow config" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: claude
      args:
        - --model
        - claude-sonnet-4-5
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Before override
    result="$(get_agent_type)"
    [ "$result" = "pi" ]
    
    # Apply override
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override
    result="$(get_agent_type)"
    [ "$result" = "claude" ]
}

@test "apply_workflow_agent_override sets CONFIG_AGENT_COMMAND from workflow config" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: custom
      command: my-custom-agent
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Apply override
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override
    result="$(get_agent_command)"
    [ "$result" = "my-custom-agent" ]
}

@test "apply_workflow_agent_override sets CONFIG_AGENT_ARGS from workflow config" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  args:
    - --model
    - claude-haiku-4-5
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: pi
      args:
        - --model
        - claude-sonnet-4-5
        - --provider
        - anthropic
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Apply override
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override
    result="$(get_agent_args)"
    [ "$result" = "--model claude-sonnet-4-5 --provider anthropic" ]
}

@test "apply_workflow_agent_override sets CONFIG_AGENT_TEMPLATE from workflow config" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: custom
      command: my-agent
      template: "cat {{prompt_file}} | {{command}} {{args}}"
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Apply override
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override
    result="$(get_agent_template)"
    [ "$result" = "cat {{prompt_file}} | {{command}} {{args}}" ]
}

@test "apply_workflow_agent_override preserves default when workflow has no agent config" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  args:
    - --model
    - claude-haiku-4-5
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Before override
    original_type="$(get_agent_type)"
    original_args="$(get_agent_args)"
    
    # Apply override (should do nothing)
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override (should be unchanged)
    result_type="$(get_agent_type)"
    result_args="$(get_agent_args)"
    
    [ "$result_type" = "$original_type" ]
    [ "$result_args" = "$original_args" ]
}

@test "apply_workflow_agent_override skips non-config-workflow identifiers" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Before override
    original_type="$(get_agent_type)"
    
    # Apply override with non-config-workflow identifier (should do nothing)
    apply_workflow_agent_override "builtin:default"
    
    # After override (should be unchanged)
    result_type="$(get_agent_type)"
    [ "$result_type" = "$original_type" ]
}

@test "workflow agent override has higher priority than top-level" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
agent:
  type: pi
  command: pi
  args:
    - --model
    - claude-haiku-4-5
  
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: claude
      args:
        - --model
        - claude-sonnet-4-5
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$CONFIG_FILE"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # Before override - should use top-level config
    type_before="$(get_agent_type)"
    args_before="$(get_agent_args)"
    [ "$type_before" = "pi" ]
    [ "$args_before" = "--model claude-haiku-4-5" ]
    
    # Apply workflow override
    apply_workflow_agent_override "config-workflow:feature"
    
    # After override - should use workflow-specific config
    type_after="$(get_agent_type)"
    args_after="$(get_agent_args)"
    [ "$type_after" = "claude" ]
    [ "$args_after" = "--model claude-sonnet-4-5" ]
}
