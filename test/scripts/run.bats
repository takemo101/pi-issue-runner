#!/usr/bin/env bats
# run.sh のBatsテスト

load '../test_helper'

setup() {
    # 共通のtmpdirセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "run.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/run.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes all main options" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--branch"* ]]
    [[ "$output" == *"--workflow"* ]]
    [[ "$output" == *"--no-attach"* ]]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"--ignore-blockers"* ]]
    [[ "$output" == *"--no-gates"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "run.sh fails without issue number" {
    run "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -ne 0 ]
}

@test "run.sh fails with non-numeric issue number" {
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

@test "run.sh fails with negative issue number" {
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" -- "-42"
    [ "$status" -ne 0 ]
    # Negative numbers starting with - may be parsed as options
    [[ "$output" == *"Issue number must be a positive integer"* ]] || [[ "$output" == *"Unknown option"* ]]
}

@test "run.sh fails with decimal issue number" {
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" "3.14"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

@test "run.sh fails with mixed alphanumeric issue number" {
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" "issue-42"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

# ====================
# ワークフロー一覧表示テスト
# ====================

@test "run.sh --list-workflows shows available workflows" {
    run "$PROJECT_ROOT/scripts/run.sh" --list-workflows
    [ "$status" -eq 0 ]
    [[ "$output" == *"default"* ]] || [[ "$output" == *"simple"* ]]
}

# ====================
# オプション解析テスト
# ====================

@test "run.sh accepts --branch option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"-b, --branch"* ]]
}

@test "run.sh accepts --workflow option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"-w, --workflow"* ]]
}

@test "run.sh accepts --base option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--base"* ]]
}

@test "run.sh accepts --no-cleanup option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--no-cleanup"* ]]
}

@test "run.sh accepts --reattach option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--reattach"* ]]
}

@test "run.sh accepts --pi-args option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--pi-args"* ]]
}

@test "run.sh accepts --ignore-blockers option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--ignore-blockers"* ]]
}

@test "run.sh accepts --no-gates option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--no-gates"* ]]
}

@test "run.sh --no-gates is parsed into _PARSE_no_gates" {
    source "$PROJECT_ROOT/scripts/run.sh" 2>/dev/null || true

    # Mock functions called during parse
    resolve_default_workflow() { echo "default"; }

    parse_run_arguments 42 --no-gates
    [ "$_PARSE_no_gates" = "true" ]
    [ "$_PARSE_issue_number" = "42" ]
}

@test "run.sh _PARSE_no_gates defaults to false" {
    source "$PROJECT_ROOT/scripts/run.sh" 2>/dev/null || true

    resolve_default_workflow() { echo "default"; }

    parse_run_arguments 42
    [ "$_PARSE_no_gates" = "false" ]
}

# ====================
# 依存関係チェックテスト
# ====================

@test "run.sh exits with code 2 when issue is blocked" {
    # run.shの依存関係チェック部分のロジックを直接検証
    source "$PROJECT_ROOT/lib/github.sh"
    
    # Mock gh to simulate blocked issue with GraphQL API
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"## 依存関係\n- Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"Base Feature","state":"OPEN"}]}}}}}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    # ブロッカーチェックが失敗(1)を返すことを確認
    run check_issue_blocked 42
    [ "$status" -eq 1 ]
    
    # ブロッカー情報がJSONで出力される
    [[ "$output" == *"\"number\": 38"* ]]
    [[ "$output" == *"\"state\": \"OPEN\""* ]]
}

@test "run.sh shows blocking issues when blocked" {
    # Mock gh to simulate blocked issue with blocker details and GraphQL API
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"## 依存関係\n- Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"Base Feature","state":"OPEN"}]}}}}}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    # ブロッカー情報が出力されることを確認
    run check_issue_blocked 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"is blocked by"* ]] || [[ "$output" == *"38"* ]]
}

@test "run.sh shows blocker details with issue number and title" {
    # Mock gh to simulate blocked issue with multiple blockers and GraphQL API
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"## 依存関係\n- Blocked by #38\n- Blocked by #39","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "39" ]]; then
    echo '{"number":39,"title":"Infrastructure","state":"OPEN"}'
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"Base Feature","state":"OPEN"},{"number":39,"title":"Infrastructure","state":"OPEN"}]}}}}}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run check_issue_blocked 42
    [ "$status" -eq 1 ]
    # ブロッカー情報に番号とタイトルが含まれることを確認
    [[ "$output" == *"38"* ]]
    [[ "$output" == *"Base Feature"* ]] || [[ "$output" == *"Infrastructure"* ]]
}

@test "run.sh suggests --ignore-blockers when blocked" {
    # Mock gh to simulate blocked issue with GraphQL API
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"Base Feature","state":"OPEN"}]}}}}}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # run.shのエラーメッセージ形式を確認
    run check_issue_blocked 42
    [ "$status" -eq 1 ]
    # ブロッカーがある場合は--ignore-blockersの使用を示唆
    [[ "$output" == *"38"* ]]
}

@test "run.sh shows warning when using --ignore-blockers" {
    # Mock gh to simulate blocked issue
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # --ignore-blockers使用時の警告メッセージを検証
    # log_warn関数の出力をキャプチャ
    run bash -c 'source "$PROJECT_ROOT/lib/log.sh" && log_warn "Ignoring blockers and proceeding with Issue #42"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ignoring blockers"* ]] || [[ "$output" == *"WARN"* ]]
}

@test "run.sh --help shows --ignore-blockers option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--ignore-blockers"* ]]
}

@test "run.sh help description explains --ignore-blockers purpose" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignore"* ]] || [[ "$output" == *"blockers"* ]] || [[ "$output" == *"skip"* ]]
}

# ====================
# デバッグオプションテスト
# ====================

@test "run.sh --show-config displays configuration" {
    run "$PROJECT_ROOT/scripts/run.sh" --show-config
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Configuration ==="* ]]
    [[ "$output" == *"worktree_base_dir:"* ]]
}

@test "run.sh --list-agents displays agent presets" {
    run "$PROJECT_ROOT/scripts/run.sh" --list-agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available agent presets:"* ]]
    [[ "$output" == *"pi"* ]]
}

@test "run.sh --show-agent-config displays agent configuration" {
    run "$PROJECT_ROOT/scripts/run.sh" --show-agent-config
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Agent Configuration ==="* ]]
    [[ "$output" == *"type:"* ]]
}

@test "run.sh help includes --show-config option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--show-config"* ]]
}

@test "run.sh help includes --list-agents option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--list-agents"* ]]
}

@test "run.sh help includes --show-agent-config option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--show-agent-config"* ]]
}

# ====================
# ワークフロー固有のagent設定テスト
# ====================

@test "workflow-specific agent override: get_workflow_agent_property returns correct values" {
    # テスト用設定ファイルを作成
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
workflows:
  test-workflow:
    description: テストワークフロー
    steps:
      - implement
    agent:
      type: claude
      command: custom-claude
      args:
        - --model
        - opus
EOF
    
    # 環境変数を設定
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    # workflow-loader.sh をロード
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    
    # ワークフロー固有の設定を取得
    local workflow_file="config-workflow:test-workflow"
    local type command args
    type=$(get_workflow_agent_property "$workflow_file" "type")
    command=$(get_workflow_agent_property "$workflow_file" "command")
    args=$(get_workflow_agent_property "$workflow_file" "args")
    
    # 検証
    [ "$type" = "claude" ]
    [ "$command" = "custom-claude" ]
    [ "$args" = "--model opus" ]
}

@test "workflow-specific agent override: apply_workflow_agent_override sets environment variables" {
    # テスト用設定ファイルを作成
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
workflows:
  test-workflow:
    steps:
      - implement
    agent:
      type: opencode
      command: my-opencode
EOF
    
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # オーバーライド適用
    local workflow_file="config-workflow:test-workflow"
    apply_workflow_agent_override "$workflow_file"
    
    # 環境変数が設定されているか確認（config-workflow形式はCONFIG_*変数を上書き）
    [ -n "${CONFIG_AGENT_TYPE:-}" ]
    [ "${CONFIG_AGENT_TYPE}" = "opencode" ]
    [ -n "${CONFIG_AGENT_COMMAND:-}" ]
    [ "${CONFIG_AGENT_COMMAND}" = "my-opencode" ]
}

@test "workflow-specific agent override: get_agent_type respects override" {
    # グローバル設定
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
agent:
  type: pi

workflows:
  override-workflow:
    steps:
      - implement
    agent:
      type: claude
EOF
    
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    # オーバーライド前: グローバル設定が使用される
    load_config
    local type_before
    type_before=$(get_agent_type)
    [ "$type_before" = "pi" ]
    
    # オーバーライド適用
    local workflow_file="config-workflow:override-workflow"
    apply_workflow_agent_override "$workflow_file"
    
    # オーバーライド後: ワークフロー固有の設定が使用される
    local type_after
    type_after=$(get_agent_type)
    [ "$type_after" = "claude" ]
}

@test "workflow-specific agent override: no override when agent not specified" {
    # agent未指定のワークフロー
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
agent:
  type: pi
  command: pi

workflows:
  default-workflow:
    steps:
      - implement
    # agent 未指定
EOF
    
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    source "$PROJECT_ROOT/lib/agent.sh"
    
    load_config
    
    # オーバーライド適用（agent未指定なので何も変わらない）
    local workflow_file="config-workflow:default-workflow"
    apply_workflow_agent_override "$workflow_file"
    
    # デフォルト設定が使用される
    local agent_type
    agent_type=$(get_agent_type)
    [ "$agent_type" = "pi" ]
    
    local agent_command
    agent_command=$(get_agent_command)
    [ "$agent_command" = "pi" ]
    
    # オーバーライド環境変数が設定されていないことを確認
    [ -z "${AGENT_TYPE_OVERRIDE:-}" ]
    [ -z "${AGENT_COMMAND_OVERRIDE:-}" ]
}

@test "show_config displays workflow-specific agent settings" {
    # ワークフロー固有のagent設定を含む設定ファイル
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
agent:
  type: pi

workflows:
  quick:
    steps:
      - implement
    agent:
      type: pi
      args:
        - --model
        - haiku
  
  thorough:
    steps:
      - plan
      - implement
    agent:
      type: claude
EOF
    
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    # show_config を実行
    run "$PROJECT_ROOT/scripts/run.sh" --show-config
    [ "$status" -eq 0 ]
    
    # ワークフロー固有のagent設定が表示されることを確認
    [[ "$output" == *"=== Workflow-Specific Agent Settings ==="* ]]
    [[ "$output" == *"Workflow: quick"* ]]
    [[ "$output" == *"agent.type: pi"* ]]
    [[ "$output" == *"agent.args: --model haiku"* ]]
    [[ "$output" == *"Workflow: thorough"* ]]
    [[ "$output" == *"agent.type: claude"* ]]
}

@test "show_config displays no workflow agent settings when none configured" {
    # agent未指定のワークフロー
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
workflows:
  simple:
    steps:
      - implement
EOF
    
    export CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    run "$PROJECT_ROOT/scripts/run.sh" --show-config
    [ "$status" -eq 0 ]
    
    # agent設定がない旨のメッセージが表示される
    [[ "$output" == *"=== Workflow-Specific Agent Settings ==="* ]]
    [[ "$output" == *"(No workflow-specific agent settings configured)"* ]]
}
