#!/usr/bin/env bats
# github.sh のテスト

setup() {
    load '../helpers/mocks'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/lib/github.sh"
}

@test "check_jq succeeds when jq is installed" {
    # jqがインストールされている前提
    if ! command -v jq &> /dev/null; then
        skip "jq is not installed"
    fi
    
    run check_jq
    [ "$status" -eq 0 ]
}

@test "check_gh_cli function exists" {
    run type check_gh_cli
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "issue_to_branch_name generates correct format" {
    setup_mocks
    mock_gh
    
    # jqが必要
    if ! command -v jq &> /dev/null; then
        skip "jq is not installed"
    fi
    
    run issue_to_branch_name 42
    [ "$status" -eq 0 ]
    [[ "$output" == issue-42* ]]
    
    cleanup_mocks
}

@test "issue_to_branch_name falls back without jq" {
    setup_mocks
    
    # jqを無効化するモック
    cat > "$MOCK_DIR/jq" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCK_DIR/jq"
    
    run issue_to_branch_name 42
    [ "$status" -eq 0 ]
    [ "$output" = "issue-42" ]
    
    cleanup_mocks
}

@test "get_issue_title returns fallback on error" {
    setup_mocks
    
    # ghが失敗するモック
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCK_DIR/gh"
    
    run get_issue_title 99
    [ "$output" = "Issue #99" ]
    
    cleanup_mocks
}
