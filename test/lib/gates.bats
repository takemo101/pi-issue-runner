#!/usr/bin/env bats

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    # Reset source guards
    unset _GATES_SH_SOURCED
    unset _COMPAT_SH_SOURCED
    unset _LOG_SH_SOURCED
    unset _YAML_SH_SOURCED
    unset _CONFIG_SH_SOURCED
    unset _MARKER_SH_SOURCED

    # Reset yaml cache
    unset _YAML_CACHE_FILE
    unset _YAML_CACHE_CONTENT
    unset _YQ_CHECK_RESULT

    # Reset gate defaults
    unset GATE_DEFAULT_TIMEOUT
    unset GATE_DEFAULT_MAX_RETRY
    unset GATE_DEFAULT_RETRY_INTERVAL

    # Reset env vars
    unset PI_ISSUE_NUMBER
    unset PI_PR_NUMBER
    unset PI_BRANCH_NAME
    unset PI_WORKTREE_PATH

    export LOG_LEVEL="QUIET"

    source "$PROJECT_ROOT/lib/gates.sh"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# parse_gate_config: シンプル形式
# ====================

@test "parse_gate_config: returns empty for nonexistent file" {
    run parse_gate_config "/nonexistent/file.yaml"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_gate_config: returns empty for missing gates section" {
    local config="$BATS_TEST_TMPDIR/no-gates.yaml"
    cat > "$config" << 'EOF'
worktree:
  base_dir: .worktrees
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_gate_config: parses global simple gates" {
    local config="$BATS_TEST_TMPDIR/simple.yaml"
    cat > "$config" << 'EOF'
gates:
  - "shellcheck -x scripts/*.sh"
  - "bats test/"
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"simple"* ]]
    [[ "$output" == *"shellcheck -x scripts/*.sh"* ]]
    [[ "$output" == *"bats test/"* ]]
}

@test "parse_gate_config: parses workflow-specific simple gates" {
    local config="$BATS_TEST_TMPDIR/workflow-gates.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    description: test
    steps:
      - implement
    gates:
      - "echo hello"
      - "echo world"
EOF
    reset_yaml_cache
    run parse_gate_config "$config" "default"
    [ "$status" -eq 0 ]
    [[ "$output" == *"simple"* ]]
    [[ "$output" == *"echo hello"* ]]
    [[ "$output" == *"echo world"* ]]
}

@test "parse_gate_config: workflow gates override global gates" {
    local config="$BATS_TEST_TMPDIR/override.yaml"
    cat > "$config" << 'EOF'
gates:
  - "global-check"
workflows:
  default:
    gates:
      - "workflow-check"
EOF
    reset_yaml_cache
    run parse_gate_config "$config" "default"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow-check"* ]]
    [[ "$output" != *"global-check"* ]]
}

# ====================
# parse_gate_config: 詳細形式（yq必須）
# ====================

@test "parse_gate_config: parses command format with yq" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/command.yaml"
    cat > "$config" << 'EOF'
gates:
  - command: "gh pr checks ${pr_number} --watch"
    timeout: 600
    max_retry: 3
    retry_interval: 30
    continue_on_fail: false
    description: "CI通過待ち"
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"command"* ]]
    [[ "$output" == *'gh pr checks ${pr_number} --watch'* ]]
    [[ "$output" == *"600"* ]]
    [[ "$output" == *"CI通過待ち"* ]]
}

@test "parse_gate_config: parses call format with yq" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/call.yaml"
    cat > "$config" << 'EOF'
gates:
  - call: code-review
    max_retry: 2
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"call"* ]]
    [[ "$output" == *"code-review"* ]]
}

@test "parse_gate_config: parses mixed formats with yq" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/mixed.yaml"
    cat > "$config" << 'EOF'
gates:
  - "shellcheck -x scripts/*.sh"
  - command: "bats test/"
    timeout: 120
  - call: code-review
    max_retry: 2
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    local lines
    lines=$(echo "$output" | wc -l | tr -d ' ')
    [ "$lines" -eq 3 ]
    [[ "$output" == *"simple"* ]]
    [[ "$output" == *"command"* ]]
    [[ "$output" == *"call"* ]]
}

@test "parse_gate_config: uses default values for missing fields with yq" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/defaults.yaml"
    cat > "$config" << 'EOF'
gates:
  - command: "echo test"
EOF
    reset_yaml_cache
    run parse_gate_config "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"command"* ]]
    [[ "$output" == *"300"* ]]
    [[ "$output" == *"false"* ]]
}

# ====================
# expand_gate_variables
# ====================

@test "expand_gate_variables: expands issue_number" {
    run expand_gate_variables 'echo ${issue_number}' "42"
    [ "$status" -eq 0 ]
    [ "$output" = "echo 42" ]
}

@test "expand_gate_variables: expands pr_number" {
    run expand_gate_variables 'gh pr checks ${pr_number}' "" "123"
    [ "$status" -eq 0 ]
    [ "$output" = "gh pr checks 123" ]
}

@test "expand_gate_variables: expands branch_name" {
    run expand_gate_variables 'echo ${branch_name}' "" "" "feature/test"
    [ "$status" -eq 0 ]
    [ "$output" = "echo feature/test" ]
}

@test "expand_gate_variables: expands worktree_path" {
    run expand_gate_variables 'cd ${worktree_path}' "" "" "" "/tmp/wt"
    [ "$status" -eq 0 ]
    [ "$output" = "cd /tmp/wt" ]
}

@test "expand_gate_variables: expands multiple variables" {
    run expand_gate_variables 'Issue #${issue_number} PR #${pr_number}' "42" "99"
    [ "$status" -eq 0 ]
    [ "$output" = "Issue #42 PR #99" ]
}

@test "expand_gate_variables: uses PI_ISSUE_NUMBER env var as fallback" {
    export PI_ISSUE_NUMBER="55"
    run expand_gate_variables 'echo ${issue_number}'
    [ "$status" -eq 0 ]
    [ "$output" = "echo 55" ]
}

@test "expand_gate_variables: explicit args override env vars" {
    export PI_ISSUE_NUMBER="55"
    run expand_gate_variables 'echo ${issue_number}' "99"
    [ "$status" -eq 0 ]
    [ "$output" = "echo 99" ]
}

@test "expand_gate_variables: leaves unknown variables untouched" {
    run expand_gate_variables 'echo ${unknown_var}'
    [ "$status" -eq 0 ]
    [ "$output" = 'echo ${unknown_var}' ]
}

@test "expand_gate_variables: handles empty input" {
    run expand_gate_variables ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ====================
# run_single_gate: 成功/失敗
# ====================

@test "run_single_gate: passes on successful command" {
    run run_single_gate "true" 10 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "run_single_gate: fails on failed command" {
    run run_single_gate "false" 10 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

@test "run_single_gate: captures stdout" {
    run run_single_gate "echo hello_world" 10 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello_world"* ]]
}

@test "run_single_gate: captures stderr" {
    run run_single_gate "echo error_msg >&2" 10 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"error_msg"* ]]
}

@test "run_single_gate: runs in specified cwd" {
    mkdir -p "$BATS_TEST_TMPDIR/subdir"
    run run_single_gate "pwd" 10 "$BATS_TEST_TMPDIR/subdir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"subdir"* ]]
}

@test "run_single_gate: captures output on failure" {
    run run_single_gate "echo 'failure output' && exit 1" 10 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failure output"* ]]
}

# ====================
# run_single_gate: タイムアウト
# ====================

@test "run_single_gate: times out slow command" {
    local timeout_cmd
    timeout_cmd=$(get_timeout_cmd)
    if [[ -z "$timeout_cmd" ]]; then
        skip "timeout command not available"
    fi

    run run_single_gate "sleep 30" 1 "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

# ====================
# run_gates: 全通過/途中失敗
# ====================

@test "run_gates: returns 0 when all gates pass" {
    local gates
    gates=$(printf "simple\ttrue\t10\t0\t1\tfalse\t\nsimple\ttrue\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "run_gates: returns 1 on first failure" {
    local gates
    gates=$(printf "simple\ttrue\t10\t0\t1\tfalse\t\nsimple\tfalse\t10\t0\t1\tfalse\t\nsimple\ttrue\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

@test "run_gates: returns 0 for empty definitions" {
    run run_gates "" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

@test "run_gates: outputs failure details" {
    local gates
    gates=$(printf "simple\techo fail_output && exit 1\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fail_output"* ]]
}

# ====================
# run_gates: continue_on_fail
# ====================

@test "run_gates: continues on fail when continue_on_fail is true" {
    local gates
    gates=$(printf "simple\tfalse\t10\t0\t1\ttrue\t\nsimple\ttrue\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

@test "run_gates: stops on fail when continue_on_fail is false" {
    local gates
    # First gate fails (continue_on_fail=false), second gate should not run
    local marker="$BATS_TEST_TMPDIR/gate2_ran"
    local gates
    gates=$(printf "simple\tfalse\t10\t0\t1\tfalse\t\nsimple\ttouch ${marker}\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [ ! -f "$marker" ]
}

# ====================
# run_call_gate: 正常完了
# ====================

@test "run_call_gate: passes when agent outputs COMPLETE marker" {
    local config="$BATS_TEST_TMPDIR/call-pass.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Reviewing code..."
echo "###TASK_COMPLETE_42###"
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  code-review:
    description: code review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    export PI_ISSUE_NUMBER=42
    run run_call_gate "code-review" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMPLETE"* ]]
}

# ====================
# run_call_gate: ERROR マーカー
# ====================

@test "run_call_gate: fails when agent outputs ERROR marker" {
    local config="$BATS_TEST_TMPDIR/call-fail.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-err"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Found issues in code"
echo "###TASK_ERROR_42###"
echo "Missing error handling"
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  code-review:
    description: code review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    run run_call_gate "code-review" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

# ====================
# run_call_gate: タイムアウト
# ====================

@test "run_call_gate: fails on timeout" {
    local timeout_cmd
    timeout_cmd=$(get_timeout_cmd)
    if [[ -z "$timeout_cmd" ]]; then
        skip "timeout command not available"
    fi

    local config="$BATS_TEST_TMPDIR/call-timeout.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-slow"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
sleep 30
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  slow-review:
    description: slow review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    run run_call_gate "slow-review" 1 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 1 ]
}

# ====================
# run_call_gate: 循環呼び出し
# ====================

@test "run_call_gate: fails on cycle detection" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/call-cycle.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    steps:
      - implement
    gates:
      - call: default
EOF
    reset_yaml_cache

    run run_call_gate "default" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main" "default"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cycle"* ]]
}

# ====================
# run_call_gate: 存在しないワークフロー
# ====================

@test "run_call_gate: fails for nonexistent workflow" {
    local config="$BATS_TEST_TMPDIR/call-noexist.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    steps:
      - implement
EOF
    reset_yaml_cache

    run run_call_gate "nonexistent" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ====================
# run_call_gate: exit 0 マーカーなし → 通過
# ====================

@test "run_call_gate: passes with exit 0 and no marker" {
    local config="$BATS_TEST_TMPDIR/call-nomarker.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-ok"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "All good"
exit 0
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  quick-review:
    description: quick review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    run run_call_gate "quick-review" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All good"* ]]
}

# ====================
# run_call_gate: exit 1 マーカーなし → 失敗
# ====================

@test "run_call_gate: fails with non-zero exit and no marker" {
    local config="$BATS_TEST_TMPDIR/call-exit1.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-fail"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Something went wrong"
exit 1
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  broken-review:
    description: broken review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    run run_call_gate "broken-review" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 1 ]
}

# ====================
# run_call_gate: agent設定のフォールバック
# ====================

@test "run_call_gate: falls back to global agent config" {
    local config="$BATS_TEST_TMPDIR/call-fallback.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-global"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Global agent reviewing"
echo "###TASK_COMPLETE_42###"
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
agent:
  type: custom
  command: $mock_agent
  template: '{{command}}'
workflows:
  code-review:
    description: code review
    steps:
      - review
EOF
    reset_yaml_cache

    run run_call_gate "code-review" 30 "$BATS_TEST_TMPDIR" "$config" "42" "main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Global agent reviewing"* ]]
}

# ====================
# run_gates: call形式実行
# ====================

@test "run_gates: executes call gates" {
    local config="$BATS_TEST_TMPDIR/gates-call.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-gates"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "###TASK_COMPLETE_42###"
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  code-review:
    description: code review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    local gates
    gates=$(printf "call\tcode-review\t30\t0\t1\tfalse\t\nsimple\ttrue\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "42" "" "" "$BATS_TEST_TMPDIR" "$config"
    [ "$status" -eq 0 ]
}

@test "run_gates: call gate failure stops execution" {
    local config="$BATS_TEST_TMPDIR/gates-call-fail.yaml"
    local mock_agent="$BATS_TEST_TMPDIR/mock-agent-fail2"

    cat > "$mock_agent" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "###TASK_ERROR_42###"
echo "Bad code"
MOCK_EOF
    chmod +x "$mock_agent"

    cat > "$config" << EOF
workflows:
  code-review:
    description: code review
    steps:
      - review
    agent:
      type: custom
      command: $mock_agent
      template: '{{command}}'
EOF
    reset_yaml_cache

    local marker="$BATS_TEST_TMPDIR/gate2_ran_after_call"
    local gates
    gates=$(printf "call\tcode-review\t30\t0\t1\tfalse\t\nsimple\ttouch ${marker}\t10\t0\t1\tfalse\t")
    run run_gates "$gates" "42" "" "" "$BATS_TEST_TMPDIR" "$config"
    [ "$status" -eq 1 ]
    [ ! -f "$marker" ]
}

# ====================
# run_gates: 変数展開
# ====================

@test "run_gates: expands variables in commands" {
    local marker="$BATS_TEST_TMPDIR/expanded_var"
    local gates
    gates=$(printf 'simple\techo ${issue_number} > %s\t10\t0\t1\tfalse\t' "$marker")
    run run_gates "$gates" "42" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$marker" ]
    [[ "$(cat "$marker")" == *"42"* ]]
}

# ====================
# detect_call_cycle: 循環なし
# ====================

@test "detect_call_cycle: no cycle with simple gates" {
    local config="$BATS_TEST_TMPDIR/no-cycle.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    gates:
      - "echo test"
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "default"
    [ "$status" -eq 0 ]
}

@test "detect_call_cycle: no cycle with unrelated call" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/no-cycle-call.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    gates:
      - call: review
  review:
    gates:
      - "echo reviewing"
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "default"
    [ "$status" -eq 0 ]
}

# ====================
# detect_call_cycle: 直接循環
# ====================

@test "detect_call_cycle: detects direct cycle" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/direct-cycle.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    gates:
      - call: default
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "default"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cycle"* ]]
}

# ====================
# detect_call_cycle: 間接循環
# ====================

@test "detect_call_cycle: detects indirect cycle" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/indirect-cycle.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    gates:
      - call: review
  review:
    gates:
      - call: default
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "default"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cycle"* ]]
}

@test "detect_call_cycle: detects 3-level indirect cycle" {
    if ! check_yq; then
        skip "yq not available"
    fi

    local config="$BATS_TEST_TMPDIR/3level-cycle.yaml"
    cat > "$config" << 'EOF'
workflows:
  a:
    gates:
      - call: b
  b:
    gates:
      - call: c
  c:
    gates:
      - call: a
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "a"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cycle"* ]]
}

# ====================
# detect_call_cycle: ワークフロー未定義
# ====================

@test "detect_call_cycle: returns 0 for nonexistent workflow" {
    local config="$BATS_TEST_TMPDIR/empty.yaml"
    cat > "$config" << 'EOF'
workflows:
  default:
    steps:
      - implement
EOF
    reset_yaml_cache
    run detect_call_cycle "$config" "nonexistent"
    [ "$status" -eq 0 ]
}

# ====================
# 統合テスト: parse → expand → run
# ====================

@test "integration: parse, expand, and run simple gates" {
    local config="$BATS_TEST_TMPDIR/integration.yaml"
    local marker1="$BATS_TEST_TMPDIR/gate1_ran"
    local marker2="$BATS_TEST_TMPDIR/gate2_ran"
    cat > "$config" << EOF
gates:
  - "touch ${marker1}"
  - "touch ${marker2}"
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")
    [ -n "$gates" ]

    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ -f "$marker1" ]
    [ -f "$marker2" ]
}

@test "integration: parse and run with failure" {
    local config="$BATS_TEST_TMPDIR/integration-fail.yaml"
    cat > "$config" << 'EOF'
gates:
  - "echo pass_gate"
  - "echo fail_gate && exit 1"
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")

    run run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fail_gate"* ]]
}

# ====================
# GATE_RESULTS_JSON
# ====================

@test "run_gates sets GATE_RESULTS_JSON on success" {
    local config="$BATS_TEST_TMPDIR/results-success.yaml"
    cat > "$config" << 'EOF'
gates:
  - "true"
  - "true"
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")
    run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"

    [ -n "$GATE_RESULTS_JSON" ]
    local total_retries
    total_retries="$(printf '%s' "$GATE_RESULTS_JSON" | jq '.total_gate_retries')"
    [ "$total_retries" = "0" ]
}

@test "run_gates GATE_RESULTS_JSON contains gate entries" {
    local config="$BATS_TEST_TMPDIR/results-entries.yaml"
    cat > "$config" << 'EOF'
gates:
  - "echo hello"
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")
    run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"

    [ -n "$GATE_RESULTS_JSON" ]
    local gate_count
    gate_count="$(printf '%s' "$GATE_RESULTS_JSON" | jq '.gates | length')"
    [ "$gate_count" = "1" ]
}

@test "run_gates GATE_RESULTS_JSON records pass result" {
    local config="$BATS_TEST_TMPDIR/results-pass.yaml"
    cat > "$config" << 'EOF'
gates:
  - command: "true"
    description: "mygate"
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")
    run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR"

    [ -n "$GATE_RESULTS_JSON" ]
    local result
    result="$(printf '%s' "$GATE_RESULTS_JSON" | jq -r '.gates.mygate.result')"
    [ "$result" = "pass" ]
}

@test "run_gates GATE_RESULTS_JSON records fail result" {
    local config="$BATS_TEST_TMPDIR/results-fail.yaml"
    cat > "$config" << 'EOF'
gates:
  - command: "false"
    description: "badgate"
    continue_on_fail: true
EOF
    reset_yaml_cache

    local gates
    gates=$(parse_gate_config "$config")
    run_gates "$gates" "" "" "" "$BATS_TEST_TMPDIR" || true

    [ -n "$GATE_RESULTS_JSON" ]
    local result
    result="$(printf '%s' "$GATE_RESULTS_JSON" | jq -r '.gates.badgate.result')"
    [ "$result" = "fail" ]
}

@test "run_gates GATE_RESULTS_JSON is empty when no gates" {
    GATE_RESULTS_JSON="leftover"
    run_gates "" "" "" "" "$BATS_TEST_TMPDIR"
    [ -z "$GATE_RESULTS_JSON" ]
}
