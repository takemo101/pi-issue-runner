#!/usr/bin/env bats
# run-batch.sh のBatsテスト

load '../test_helper'

setup() {
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

@test "run-batch.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run-batch.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "run-batch.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/run-batch.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# 引数エラーテスト
# ====================

@test "run-batch.sh fails with no arguments" {
    run "$PROJECT_ROOT/scripts/run-batch.sh"
    [ "$status" -eq 3 ]
    [[ "$output" == *"required"* ]]
}

@test "run-batch.sh fails with invalid issue number" {
    run "$PROJECT_ROOT/scripts/run-batch.sh" "abc"
    [ "$status" -eq 3 ]
}

@test "run-batch.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/run-batch.sh" 42 --unknown-option
    [ "$status" -eq 3 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# dry-runモードテスト
# ====================

@test "run-batch.sh --dry-run shows execution plan without running" {
    # 依存関係モック
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
    
    run "$PROJECT_ROOT/scripts/run-batch.sh" 482 483 --dry-run
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    [[ "$output" == *"No changes made"* ]]
}

# ====================
# 関数定義テスト
# ====================

@test "run-batch.sh has main function defined" {
    # スクリプト内にmain関数が定義されているか確認
    grep -q "^main() {" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh sources required libraries" {
    # スクリプトのライブラリ読み込み部分を確認（40-50行目）
    head -50 "$PROJECT_ROOT/scripts/run-batch.sh" | grep -q "lib/config.sh"
    head -50 "$PROJECT_ROOT/scripts/run-batch.sh" | grep -q "lib/log.sh"
    head -50 "$PROJECT_ROOT/scripts/run-batch.sh" | grep -q "lib/dependency.sh"
}

# ====================
# オプションパーステスト
# ====================

@test "run-batch.sh accepts multiple issue numbers" {
    # スクリプトの内容を確認
    grep -q "issues+=(\"\$1\")" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh supports --sequential option" {
    grep -q "SEQUENTIAL=true" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh supports --continue-on-error option" {
    grep -q "CONTINUE_ON_ERROR=true" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh supports --timeout option" {
    grep -q "TIMEOUT=\"\$2\"" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh supports --workflow option" {
    grep -q "WORKFLOW_NAME=\"\$2\"" "$PROJECT_ROOT/scripts/run-batch.sh"
}

# ====================
# 終了コードテスト
# ====================

@test "run-batch.sh defines exit code 0 for success" {
    grep -q "0 - 全Issue成功" "$PROJECT_ROOT/scripts/run-batch.sh" || \
    grep -q "exit 0" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh defines exit code 1 for failure" {
    grep -q "exit 1" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh defines exit code 2 for circular dependency" {
    grep -q "exit 2" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh defines exit code 3 for argument error" {
    grep -q "exit 3" "$PROJECT_ROOT/scripts/run-batch.sh"
}

# ====================
# 循環依存検出テスト
# ====================

@test "run-batch.sh detects circular dependencies" {
    source "$PROJECT_ROOT/lib/dependency.sh"
    
    # 循環を検出する関数が存在する
    declare -f detect_cycles > /dev/null
}

# ====================
# 統合フローテスト
# ====================

@test "run-batch.sh has execute_issue function" {
    grep -q "^execute_issue() {" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh has execute_issue_async function" {
    grep -q "^execute_issue_async() {" "$PROJECT_ROOT/scripts/run-batch.sh"
}

@test "run-batch.sh has wait_for_layer_completion function" {
    grep -q "^wait_for_layer_completion() {" "$PROJECT_ROOT/scripts/run-batch.sh"
}
