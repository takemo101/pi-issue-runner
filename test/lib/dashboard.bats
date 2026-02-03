#!/usr/bin/env bats
# dashboard.sh のユニットテスト

load '../test_helper'

# Bash 4.0+が必要（連想配列のサポート）
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    skip "Bash 4.0 or higher is required (current: ${BASH_VERSION})"
fi

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
    
    # ステータスディレクトリを作成
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
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
# Box Drawing Tests
# ====================

@test "draw_box_top creates box top border" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    run draw_box_top 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"╔"* ]]
    [[ "$output" == *"╗"* ]]
}

@test "draw_box_bottom creates box bottom border" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    run draw_box_bottom 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"╚"* ]]
    [[ "$output" == *"╝"* ]]
}

@test "draw_box_separator creates box separator" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    run draw_box_separator 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"╠"* ]]
    [[ "$output" == *"╣"* ]]
}

@test "draw_box_line creates padded line" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    run draw_box_line "Test" 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"║"* ]]
    [[ "$output" == *"Test"* ]]
}

# ====================
# Data Collection Tests
# ====================

@test "collect_github_issues returns JSON array" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue list"*)
        echo '[{"number":42,"title":"Test Issue","labels":[],"createdAt":"2024-01-01T00:00:00Z"}]'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    run collect_github_issues
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
}

@test "collect_github_issues handles gh CLI unavailable" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドが存在しない場合
    run collect_github_issues
    # エラーでも終了コード0または1で続行
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    # 空配列を返す
    [[ "$output" == "[]" || -z "$output" ]]
}

@test "collect_closed_issues_this_week returns JSON array" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue list --state closed"*)
        echo '[{"number":40,"closedAt":"'$(date -u +%Y-%m-%d)'T00:00:00Z"}]'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
# 入力をそのまま返す簡易モック
cat
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    enable_mocks
    
    run collect_closed_issues_this_week
    [ "$status" -eq 0 ]
}

@test "collect_local_statuses returns status list" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # テスト用ステータスを作成
    save_status 42 "running" "pi-test-42"
    save_status 43 "complete" "pi-test-43"
    
    run collect_local_statuses
    [ "$status" -eq 0 ]
    [[ "$output" == *"42"* ]]
}

@test "collect_session_info returns session list" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # tmuxのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "list-sessions"*)
        echo "pi-test-42"
        echo "pi-test-43"
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run collect_session_info
    [ "$status" -eq 0 ]
}

# ====================
# Categorization Tests
# ====================

@test "categorize_issues creates categories" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック（ブロッカーチェック用）
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
        ;;
    *"issue list --state closed"*)
        echo '[]'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
# 基本的なjq機能をエミュレート
if [[ "$*" == *"length"* ]]; then
    echo "2"
elif [[ "$*" == *".data."* ]]; then
    echo '[]'
elif [[ "$*" == *".[0].number"* ]]; then
    echo "42"
elif [[ "$*" == *".[1].number"* ]]; then
    echo "43"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    enable_mocks
    
    # テスト用ステータスを作成
    save_status 42 "running" "pi-test-42"
    
    local test_json='[{"number":42,"title":"Test 1"},{"number":43,"title":"Test 2"}]'
    
    categorize_issues "$test_json"
    
    # CATEGORIZED_ISSUESが作成されているか確認
    [[ -n "${CATEGORIZED_ISSUES[in_progress]:-}" ]] || [[ -n "${CATEGORIZED_ISSUES[ready]:-}" ]]
}

# ====================
# Display Function Tests
# ====================

@test "draw_summary_section displays summary" {
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # カテゴリを初期化
    declare -A CATEGORIZED_ISSUES
    CATEGORIZED_ISSUES[in_progress]="42 43"
    CATEGORIZED_ISSUES[blocked]="44"
    CATEGORIZED_ISSUES[ready]="45 46 47"
    CATEGORIZED_ISSUES[completed]="40 41"
    
    run draw_summary_section 60
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUMMARY"* ]]
    [[ "$output" == *"In Progress"* ]]
    [[ "$output" == *"2 issues"* ]]
}

@test "draw_in_progress_section displays issues" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue view"*)
        echo '{"number":42,"title":"Test Issue"}'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Test Issue"
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    # tmuxのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1  # セッションなし
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    
    enable_mocks
    
    # カテゴリを初期化
    declare -A CATEGORIZED_ISSUES
    CATEGORIZED_ISSUES[in_progress]="42"
    
    run draw_in_progress_section 60 false
    [ "$status" -eq 0 ]
    [[ "$output" == *"IN PROGRESS"* ]]
}

@test "draw_blocked_section displays blocked issues" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue view"*|*"repo view"*)
        echo '{"number":44,"title":"Blocked Issue","owner":{"login":"test"},"name":"repo"}'
        ;;
    *"api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"Blocker","state":"OPEN"}]}}}}}'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"owner.login"* ]]; then
    echo "test"
elif [[ "$*" == *".name"* ]]; then
    echo "repo"
elif [[ "$*" == *".title"* ]]; then
    echo "Blocked Issue"
elif [[ "$*" == *"blockedBy"* ]]; then
    echo '[{"number":38,"title":"Blocker","state":"OPEN"}]'
elif [[ "$*" == *'join(", ")'* ]]; then
    echo "38"
else
    cat
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    enable_mocks
    
    # カテゴリを初期化
    declare -A CATEGORIZED_ISSUES
    CATEGORIZED_ISSUES[blocked]="44"
    
    run draw_blocked_section 60 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "draw_ready_section displays ready issues" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # ghコマンドのモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue view"*)
        echo '{"number":45,"title":"Ready Issue"}'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # jqのモック
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Ready Issue"
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    
    enable_mocks
    
    # カテゴリを初期化
    declare -A CATEGORIZED_ISSUES
    CATEGORIZED_ISSUES[ready]="45"
    
    run draw_ready_section 60 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"READY"* ]]
}

# ====================
# JSON Output Tests
# ====================

@test "output_json produces valid JSON" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/dashboard.sh"
    
    # 必要なモックをセットアップ
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    *"issue list --state open"*)
        echo '[{"number":42,"title":"Test","labels":[],"createdAt":"2024-01-01T00:00:00Z"}]'
        ;;
    *"issue list --state closed"*)
        echo '[]'
        ;;
    *"repo view"*)
        echo '{"nameWithOwner":"test/repo"}'
        ;;
    *"api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
        ;;
    *"auth status"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    run output_json
    [ "$status" -eq 0 ]
    # JSONとして妥当か確認（jqでパースできるか）
    echo "$output" | jq . >/dev/null
}
