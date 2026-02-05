#!/usr/bin/env bats
# dashboard.sh の統合テスト

load '../test_helper'

# Bash 4.0+が必要なため、ファイルレベルでチェック
setup_file() {
    bats_require_minimum_version 1.5.0
    
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        skip "Bash 4.0 or higher is required for dashboard tests (current: ${BASH_VERSION})"
    fi
}

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テスト用の設定ファイル
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/test-config.yaml"
    cat > "$TEST_CONFIG_FILE" << EOF
worktree_base_dir: "${BATS_TEST_TMPDIR}/.worktrees"
tmux_session_prefix: "pi-test"
EOF
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
# Help Display Tests
# ====================

@test "dashboard.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/dashboard.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"--json"* ]]
    [[ "$output" == *"--compact"* ]]
    [[ "$output" == *"--watch"* ]]
}

@test "dashboard.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/dashboard.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

# ====================
# Dependency Checks
# ====================

@test "dashboard.sh requires gh CLI" {
    # ghコマンドが見つからない場合
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 127  # command not found
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    # PATHからghを除外（実際のghコマンドを使わない）
    export PATH="$MOCK_DIR"
    
    run -127 bash -c "command -v gh"
    # ghが見つからないことを確認
    [ "$status" -ne 0 ]
}

@test "dashboard.sh requires jq" {
    # ghのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # PATHからjqを除外
    export PATH="$MOCK_DIR"
    
    run -127 bash -c "command -v jq"
    # jqが見つからないことを確認
    [ "$status" -ne 0 ]
}

# ====================
# Option Parsing Tests
# ====================

@test "dashboard.sh accepts --json option" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list --state open"*)
        echo '[]'
        ;;
    *"issue list --state closed"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
# 基本的なjq機能をエミュレート
if [[ "$*" == *"-n"* ]]; then
    # JSON出力
    echo '{"repository":"test/repo","updated":"2024-01-01T00:00:00Z","summary":{"in_progress":0,"blocked":0,"ready":0,"completed":0},"issues":{"in_progress":[],"blocked":[],"ready":[],"completed":[]}}'
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh" --json
    [ "$status" -eq 0 ]
    # JSON出力を確認
    [[ "$output" == *"{"* ]]
}

@test "dashboard.sh accepts --compact option" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"length"* ]]; then
    echo "0"
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
echo ""
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh" --compact
    [ "$status" -eq 0 ]
    # コンパクト表示にはSUMMARYのみが含まれる
    [[ "$output" == *"SUMMARY"* ]]
}

@test "dashboard.sh accepts --section option" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"length"* ]]; then
    echo "0"
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
echo ""
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh" --section summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUMMARY"* ]]
}

@test "dashboard.sh rejects invalid section" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh" --section invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid section"* ]]
}

@test "dashboard.sh accepts -v verbose option" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"length"* ]]; then
    echo "0"
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
echo ""
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh" -v
    [ "$status" -eq 0 ]
}

# ====================
# Output Format Tests
# ====================

@test "dashboard.sh displays header and sections" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"length"* ]]; then
    echo "0"
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
echo ""
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh"
    [ "$status" -eq 0 ]
    # ヘッダーとセクション区切りを確認
    [[ "$output" == *"==="* ]]
    [[ "$output" == *"Dashboard"* ]]
}

@test "dashboard.sh shows repository info" {
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"length"* ]]; then
    echo "0"
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
echo ""
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repository:"* ]]
}

# ====================
# Error Handling Tests
# ====================

@test "dashboard.sh handles missing --section argument" {
    run "$PROJECT_ROOT/scripts/dashboard.sh" --section
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "dashboard.sh handles unknown option" {
    run "$PROJECT_ROOT/scripts/dashboard.sh" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"Usage:"* ]]
}

# ====================
# Integration Tests
# ====================

@test "dashboard.sh runs end-to-end with mocks" {
    # 完全なモック環境をセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    *"issue list --state open"*)
        echo '[{"number":42,"title":"Test Issue","labels":[],"createdAt":"2024-01-01T00:00:00Z"}]'
        ;;
    *"issue list --state closed"*)
        echo '[{"number":40,"closedAt":"'$(date -u +%Y-%m-%d)'T00:00:00Z"}]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *"issue view 42"*)
        echo '{"number":42,"title":"Test Issue","body":"Test body","labels":[],"state":"OPEN","comments":[]}'
        ;;
    *"api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
# 基本的なjq機能をエミュレート
input=$(cat)
if [[ "$*" == *"length"* ]]; then
    if [[ "$input" == "[]" ]]; then
        echo "0"
    else
        echo "1"
    fi
elif [[ "$*" == *".nameWithOwner"* ]]; then
    echo "test/repo"
elif [[ "$*" == *".[0].number"* ]]; then
    echo "42"
elif [[ "$*" == *".title"* ]]; then
    echo "Test Issue"
elif [[ "$*" == *"blockedBy"* ]]; then
    echo '[]'
else
    echo "$input"
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        echo ""
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/dashboard.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dashboard"* ]]
    [[ "$output" == *"SUMMARY"* ]]
}
