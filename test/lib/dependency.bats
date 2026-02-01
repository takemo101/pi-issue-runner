#!/usr/bin/env bats
# dependency.sh のBatsテスト

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
# get_issue_blockers_numbers テスト
# ====================

@test "get_issue_blockers_numbers returns blocker numbers" {
    # GraphQL APIモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status"*)
        exit 0
        ;;
    "repo view --json owner,name"*)
        echo '{"owner":{"login":"testowner"},"name":"testrepo"}}'
        ;;
    "api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"基盤機能","state":"OPEN"},{"number":39,"title":"依存タスク","state":"CLOSED"}]}}}}}'
        ;;
    *)
        echo "Mock gh: unknown command: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    result="$(get_issue_blockers_numbers 42)"
    
    # ブロッカー番号が含まれる
    [[ "$result" == *"38"* ]]
    [[ "$result" == *"39"* ]]
}

@test "get_issue_blockers_numbers returns empty when no blockers" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status"*)
        exit 0
        ;;
    "repo view --json owner,name"*)
        echo '{"owner":{"login":"testowner"},"name":"testrepo"}}'
        ;;
    "api graphql"*)
        echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    result="$(get_issue_blockers_numbers 42)"
    
    [ -z "$result" ]
}

# ====================
# build_dependency_graph テスト
# ====================

@test "build_dependency_graph outputs tsort format" {
    # モック: 各Issueのブロッカーを返す
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status"*)
        exit 0
        ;;
    "repo view --json owner,name"*)
        echo '{"owner":{"login":"testowner"},"name":"testrepo"}}'
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    # get_issue_blockers_numbersをモック
    cat > "$MOCK_DIR/get_issue_blockers_numbers" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    483|484) echo "482" ;;
    485|486) echo "484" ;;
    *) echo "" ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/get_issue_blockers_numbers"
    
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # モック関数で上書き
    get_issue_blockers_numbers() {
        "$MOCK_DIR/get_issue_blockers_numbers" "$@"
    }
    
    result="$(build_dependency_graph 482 483 484 485 486)"
    
    # tsort形式で出力される
    [[ "$result" == *"482 483"* ]]
    [[ "$result" == *"482 484"* ]]
    [[ "$result" == *"484 485"* ]]
    [[ "$result" == *"484 486"* ]]
}

@test "build_dependency_graph handles issues without dependencies" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # get_issue_blockers_numbersをスタブ
    get_issue_blockers_numbers() {
        echo ""
    }
    
    result="$(build_dependency_graph 482 483)"
    
    # 依存がないIssueも出力（孤立点として）
    [[ "$result" == *"482 482"* ]]
    [[ "$result" == *"483 483"* ]]
}

# ====================
# detect_cycles テスト
# ====================

@test "detect_cycles returns 0 when no cycles" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # get_issue_blockers_numbersをスタブ
    get_issue_blockers_numbers() {
        case "$1" in
            483) echo "482" ;;
            484) echo "482" ;;
            *) echo "" ;;
esac
    }
    
    run detect_cycles 482 483 484
    
    # 循環なし
    [ "$status" -eq 0 ]
}

@test "detect_cycles returns 1 when cycle exists" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # 循環: 482 → 483 → 484 → 482
    get_issue_blockers_numbers() {
        case "$1" in
            483) echo "482" ;;
            484) echo "483" ;;
            482) echo "484" ;;
            *) echo "" ;;
esac
    }
    
    run detect_cycles 482 483 484
    
    # 循環あり
    [ "$status" -eq 1 ]
}

# ====================
# compute_layers テスト
# ====================

@test "compute_layers assigns correct depth" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # 依存関係: 482 → 483, 482 → 484 → 485
    get_issue_blockers_numbers() {
        case "$1" in
            483) echo "482" ;;
            484) echo "482" ;;
            485) echo "484" ;;
            *) echo "" ;;
esac
    }
    
    result="$(compute_layers 482 483 484 485)"
    
    # Layer 0: 482 (依存なし)
    [[ "$result" == *"0 482"* ]]
    
    # Layer 1: 483, 484 (482に依存)
    [[ "$result" == *"1 483"* ]]
    [[ "$result" == *"1 484"* ]]
    
    # Layer 2: 485 (484に依存)
    [[ "$result" == *"2 485"* ]]
}

@test "compute_layers handles independent issues" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    get_issue_blockers_numbers() {
        echo ""
    }
    
    result="$(compute_layers 482 483 484)"
    
    # 全てLayer 0
    [[ "$result" == *"0 482"* ]]
    [[ "$result" == *"0 483"* ]]
    [[ "$result" == *"0 484"* ]]
}

# ====================
# group_layers テスト
# ====================

@test "group_layers formats layer output" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    input="0 482
1 483
1 484
2 485"
    
    result="$(echo "$input" | group_layers)"
    
    [[ "$result" == *"Layer 0: #482"* ]]
    [[ "$result" == *"Layer 1: #483 #484"* ]]
    [[ "$result" == *"Layer 2: #485"* ]]
}

# ====================
# get_issues_in_layer テスト
# ====================

@test "get_issues_in_layer returns issues for specific layer" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    input="0 482
1 483
1 484
2 485"
    
    result="$(get_issues_in_layer 1 "$input")"
    
    [[ "$result" == *"483"* ]]
    [[ "$result" == *"484"* ]]
    [[ "$result" != *"482"* ]]
    [[ "$result" != *"485"* ]]
}

# ====================
# get_max_layer テスト
# ====================

@test "get_max_layer returns maximum layer number" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    input="0 482
1 483
2 484
2 485"
    
    result="$(echo "$input" | get_max_layer)"
    
    [ "$result" -eq 2 ]
}

@test "get_max_layer returns 0 for single layer" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    input="0 482
0 483"
    
    result="$(echo "$input" | get_max_layer)"
    
    [ "$result" -eq 0 ]
}
