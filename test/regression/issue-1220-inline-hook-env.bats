#!/usr/bin/env bats
# test/regression/issue-1220-inline-hook-env.bats
# Regression test for Issue #1220: inline hook env var naming inconsistency
# Both PI_RUNNER_HOOKS_ALLOW_INLINE (standard) and PI_RUNNER_ALLOW_INLINE_HOOKS (legacy)
# should work for enabling inline hooks.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    export TEST_WORKDIR="$BATS_TEST_TMPDIR"
    export PI_RUNNER_CONFIG="$TEST_WORKDIR/.pi-runner.yaml"

    cat > "$PI_RUNNER_CONFIG" << 'EOF'
hooks:
  on_success: echo "INLINE_OK"
EOF

    # Override get_config to read from test config
    override_get_config() {
        get_config() {
            case "$1" in
                hooks_on_success) echo "echo \"INLINE_OK\"" ;;
                hooks_allow_inline) echo "false" ;;
                *) echo "" ;;
            esac
        }
        export -f get_config
    }
}

teardown() {
    unset PI_RUNNER_HOOKS_ALLOW_INLINE 2>/dev/null || true
    unset PI_RUNNER_ALLOW_INLINE_HOOKS 2>/dev/null || true
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "issue-1220: standard env var PI_RUNNER_HOOKS_ALLOW_INLINE enables inline hooks" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    # Mock notify to avoid side effects
    send_notification() { :; }
    export -f send_notification

    unset PI_RUNNER_ALLOW_INLINE_HOOKS
    export PI_RUNNER_HOOKS_ALLOW_INLINE=true

    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_OK"* ]]
}

@test "issue-1220: legacy env var PI_RUNNER_ALLOW_INLINE_HOOKS still works (backward compat)" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    send_notification() { :; }
    export -f send_notification

    unset PI_RUNNER_HOOKS_ALLOW_INLINE
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true

    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_OK"* ]]
}

@test "issue-1220: standard env var takes precedence over legacy" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    send_notification() { :; }
    export -f send_notification

    # Standard says true, legacy says false - standard should win
    export PI_RUNNER_HOOKS_ALLOW_INLINE=true
    export PI_RUNNER_ALLOW_INLINE_HOOKS=false

    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_OK"* ]]
}

@test "issue-1220: warn message suggests standard env var name" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    send_notification() { :; }
    export -f send_notification

    unset PI_RUNNER_HOOKS_ALLOW_INLINE
    unset PI_RUNNER_ALLOW_INLINE_HOOKS

    run run_hook "on_success" "42" "pi-42" "" "" "" "0" ""
    # Should suggest standard name in warning
    [[ "$output" == *"PI_RUNNER_HOOKS_ALLOW_INLINE"* ]]
}
