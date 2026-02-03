#!/usr/bin/env bats
# issue-state.sh のBatsテスト
# GitHub Issueの状態を管理するスクリプト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
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

@test "issue-state.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "issue-state.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "issue-state.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh"
    [ "$status" -ne 0 ]
}

@test "issue-state.sh requires valid command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" "invalid-cmd"
    [ "$status" -ne 0 ]
}

@test "issue-state.sh requires issue number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "open\|close\|reopen" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "state commands not implemented"
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" "close"
    [ "$status" -ne 0 ]
}

# ====================
# サブコマンドテスト
# ====================

@test "issue-state.sh supports open command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "open\|\"open\"\|'open'" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "open command not implemented"
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" open "100"
    [ "$status" -eq 0 ]
}

@test "issue-state.sh supports close command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "close\|\"close\"\|'close'" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "close command not implemented"
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "100"
    [ "$status" -eq 0 ]
}

@test "issue-state.sh supports reopen command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "reopen\|\"reopen\"\|'reopen'" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "reopen command not implemented"
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" reopen "100"
    [ "$status" -eq 0 ]
}

@test "issue-state.sh supports status command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "status\|\"status\"\|'status'" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "status command not implemented"
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" status "100"
    [ "$status" -eq 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "issue-state.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "100"
    [ "$status" -ne 0 ]
}

@test "issue-state.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        echo "not authenticated" >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "100"
    [ "$status" -ne 0 ]
}

# ====================
# モックヘルパー
# ====================

mock_gh_issue_state() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "issue view"*)
        echo '{"number":100,"title":"Test Issue","state":"OPEN","stateReason":null}'
        exit 0
        ;;
    "issue close"*)
        echo '{"number":100,"title":"Test Issue","state":"CLOSED","stateReason":"COMPLETED"}'
        exit 0
        ;;
    "issue reopen"*)
        echo '{"number":100,"title":"Test Issue","state":"OPEN","stateReason":null}'
        exit 0
        ;;
    *)
        echo "Mock gh: $*" >&2
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# ====================
# 機能テスト
# ====================

@test "issue-state.sh close validates issue number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "invalid"
    [ "$status" -ne 0 ]
}

@test "issue-state.sh outputs current state" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" status "100"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPEN"* ]] || [[ "$output" == *"CLOSED"* ]] || [[ "$output" == *"state"* ]]
}

@test "issue-state.sh close adds comment when specified" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    grep -q "comment\|--comment\|-c" "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" 2>/dev/null || \
        skip "comment option not implemented"
    
    mock_gh_issue_state
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "100" --comment "Closing this issue"
    [ "$status" -eq 0 ]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "issue-state.sh handles non-existent issue" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" ]]; then
        skip "issue-state.sh not found"
    fi
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "issue view"*|"issue close"*)
        echo "issue not found" >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-state-management/scripts/issue-state.sh" close "999"
    [ "$status" -ne 0 ]
}
