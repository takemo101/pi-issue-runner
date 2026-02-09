#!/usr/bin/env bats
# Regression test for Issue #1145
# Ensures apply_workflow_agent_override() handles both config-workflow:NAME
# and YAML file path formats (previously the YAML file path handler was
# shadowed by a duplicate function definition)

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    export TEST_DIR="$BATS_TEST_TMPDIR"

    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/yaml.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    source "$PROJECT_ROOT/lib/agent.sh"

    reset_yaml_cache
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "issue-1145: YAML file workflow agent override sets AGENT_TYPE_OVERRIDE" {
    # Create a workflow YAML file with agent section
    cat > "$TEST_DIR/test-workflow.yaml" << 'YAML_EOF'
name: test-workflow
description: Test workflow
steps:
  - implement
agent:
  type: claude
  command: claude-code
  args:
    - "--model"
    - "opus"
  template: custom-agent.md
YAML_EOF

    # Apply override with YAML file path
    apply_workflow_agent_override "$TEST_DIR/test-workflow.yaml"

    # YAML file path format should set AGENT_*_OVERRIDE variables
    [ "${AGENT_TYPE_OVERRIDE:-}" = "claude" ]
    [ "${AGENT_COMMAND_OVERRIDE:-}" = "claude-code" ]
    [ "${AGENT_ARGS_OVERRIDE:-}" = "--model opus" ]
    [ "${AGENT_TEMPLATE_OVERRIDE:-}" = "custom-agent.md" ]
}

@test "issue-1145: config-workflow format sets CONFIG_AGENT_* variables" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  my-workflow:
    steps:
      - implement
    agent:
      type: opencode
      command: my-opencode
YAML_EOF

    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    load_config "$CONFIG_FILE"

    apply_workflow_agent_override "config-workflow:my-workflow"

    [ "${CONFIG_AGENT_TYPE:-}" = "opencode" ]
    [ "${CONFIG_AGENT_COMMAND:-}" = "my-opencode" ]
}

@test "issue-1145: non-file non-config-workflow identifier is skipped gracefully" {
    apply_workflow_agent_override "builtin:default"

    # No variables should be set
    [ -z "${AGENT_TYPE_OVERRIDE:-}" ]
    [ -z "${CONFIG_AGENT_TYPE:-}" ]
}
