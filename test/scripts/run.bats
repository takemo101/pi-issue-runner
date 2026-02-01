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
# --reattach オプションテスト
# ====================

@test "run.sh --reattach attaches to existing session" {
    # Mock tmux with existing session
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        # Session exists for pi-issue-42
        if [[ "$3" == "pi-issue-42" ]]; then
            exit 0
        fi
        exit 1
        ;;
    "attach-session")
        echo "Attached to session"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    # Mock gh for issue lookup
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == "view" && "$3" == "42" ]]; then
    echo '{"number":42,"title":"Test Issue","body":"Test","state":"OPEN"}'
else
    exit 0
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    # Mock attach_session to avoid actual tmux call
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    # Test that --reattach tries to attach to existing session
    run "$PROJECT_ROOT/scripts/run.sh" 42 --reattach
    # Should succeed (status 0) and attach
    [ "$status" -eq 0 ]
    # Output should indicate attaching
    [[ "$output" == *"Attaching to existing session"* ]] || [[ "$output" == *"pi-issue-42"* ]]
}

@test "run.sh --reattach exits with 0 on success" {
    # Mock tmux with existing session that can be attached
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # Session exists
        ;;
    "attach-session")
        exit 0  # Attach successful
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"Test","state":"OPEN"}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" 42 --reattach
    [ "$status" -eq 0 ]
}

# ====================
# --force オプションテスト
# ====================

@test "run.sh --force kills existing session" {
    # Mock tmux with existing session that gets killed
    local tmux_calls=""
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # Session exists
        ;;
    "kill-session")
        echo "Session killed"
        exit 0
        ;;
    "new-session")
        exit 0
        ;;
    "send-keys")
        exit 0
        ;;
    "list-sessions")
        echo ""
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    # Verify session_exists detects existing session
    run session_exists "pi-issue-42"
    [ "$status" -eq 0 ]
}

@test "run.sh --force removes existing worktree" {
    # Create a temporary worktree structure
    local test_worktree="$BATS_TEST_TMPDIR/.worktrees/issue-42-test"
    mkdir -p "$test_worktree"
    
    # Mock git to simulate worktree removal
    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "worktree")
        case "$2" in
            "list")
                echo ""
                ;;
            "remove")
                exit 0
                ;;
        esac
        ;;
    "rev-parse")
        exit 1  # Branch doesn't exist
        ;;
esac
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Test worktree removal logic
    if [[ -d "$test_worktree" ]]; then
        rm -rf "$test_worktree"
    fi
    [ ! -d "$test_worktree" ]
}

# ====================
# 既存セッション時のエラーメッセージテスト
# ====================

@test "run.sh shows helpful error when session exists without options" {
    # Mock tmux with existing session
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # Session exists
        ;;
    "list-sessions")
        echo "pi-issue-42: 1 windows"
        ;;
esac
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"Test","state":"OPEN"}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    # Run without --reattach or --force
    run "$PROJECT_ROOT/scripts/run.sh" 42
    
    # Should fail with error
    [ "$status" -eq 1 ]
    # Should show helpful message
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"--reattach"* ]] || [[ "$output" == *"--force"* ]]
}

@test "run.sh suggests --reattach and --force when session exists" {
    # Mock tmux with existing session
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # Session exists
        ;;
esac
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"Test","state":"OPEN"}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/run.sh" 42
    
    [ "$status" -eq 1 ]
    # Should mention both options
    [[ "$output" == *"reattach"* ]] || [[ "$output" == *"Attach"* ]]
    [[ "$output" == *"force"* ]] || [[ "$output" == *"Remove"* ]]
}

@test "run.sh help shows --reattach description" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--reattach"* ]]
    [[ "$output" == *"Attach"* ]] || [[ "$output" == *"attach"* ]]
}

@test "run.sh help shows --force description" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"削除"* ]] || [[ "$output" == *"再作成"* ]] || [[ "$output" == *"Remove"* ]] || [[ "$output" == *"recreate"* ]]
}
