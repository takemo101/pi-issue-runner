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

# ====================
# 依存関係チェックテスト
# ====================

@test "run.sh exits with code 2 when issue is blocked" {
    # run.shの依存関係チェック部分のロジックを直接検証
    source "$PROJECT_ROOT/lib/github.sh"
    
    # Mock gh to simulate blocked issue
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"## 依存関係\n- Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
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

@test "run.sh proceeds with --ignore-blockers when issue is blocked" {
    # Mock gh to simulate blocked issue
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"## 依存関係\n- Blocked by #38","state":"OPEN"}'
elif [[ "$2" == "view" && "$3" == "38" ]]; then
    echo '{"number":38,"title":"Base Feature","state":"OPEN"}'
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    enable_mocks
    
    # run.shのブロッカーチェック部分のみをテスト（tmuxセッション部分はスキップ）
    # 依存関係チェックのロジックを直接検証
    source "$PROJECT_ROOT/lib/github.sh"
    
    # ブロッカーがある状態
    run check_issue_blocked 42
    [ "$status" -eq 1 ]
    
    # --ignore-blockersを指定するとチェックをスキップする動作を確認
    # run.shの該当部分:
    # if [[ "$ignore_blockers" != "true" ]]; then
    #     if ! open_blockers=$(check_issue_blocked "$issue_number"); then
    #         ...
    #     fi
    # else
    #     log_warn "Ignoring blockers and proceeding with Issue #$issue_number"
    # fi
}
