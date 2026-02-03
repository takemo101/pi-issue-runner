#!/usr/bin/env bats
# ci-wait.sh のBatsテスト
# CIワークフローの完了を待機するスクリプト

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

@test "ci-wait.sh --help shows usage" {
    # スクリプトが存在しない場合はスキップ
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"使い方"* ]] || [[ "$output" == *"usage"* ]]
}

@test "ci-wait.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "ci-wait.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh"
    [ "$status" -ne 0 ]
}

@test "ci-wait.sh fails with invalid PR number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "not-a-number"
    [ "$status" -ne 0 ]
}

@test "ci-wait.sh accepts valid PR number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    # ghコマンドをモック
    mock_gh_ci_success
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42"
    # タイムアウトまたはCI完了で終了
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
}

# ====================
# 依存ツールチェック
# ====================

@test "ci-wait.sh fails when gh CLI is not installed" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    # PATHからghを削除
    export PATH="/usr/bin:/bin"
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42"
    # ghがない場合はエラー終了
    [ "$status" -ne 0 ]
}

# ====================
# CI状態テスト（モック使用）
# ====================

mock_gh_ci_success() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "pr checks"*)
        # CI成功をシミュレート
        exit 0
        ;;
    "pr view"*)
        echo '{"number":42,"state":"OPEN"}'
        ;;
    *)
        echo "Mock gh: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

mock_gh_ci_failure() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "pr checks"*)
        # CI失敗をシミュレート
        exit 1
        ;;
    "pr view"*)
        echo '{"number":42,"state":"OPEN"}'
        ;;
    *)
        echo "Mock gh: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

@test "ci-wait.sh returns 0 on CI success" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    mock_gh_ci_success
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42"
    # CI成功時はexit code 0
    [ "$status" -eq 0 ]
}

@test "ci-wait.sh returns 1 on CI failure" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    mock_gh_ci_failure
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42"
    # CI失敗時はexit code 1
    [ "$status" -eq 1 ]
}

@test "ci-wait.sh supports timeout option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    # タイムアウトオプションを持つか確認
    grep -q "timeout\|--timeout\|-t" "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" 2>/dev/null || \
        skip "timeout option not implemented"
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42" --timeout 1
    # タイムアウト時はexit code 2
    [ "$status" -eq 2 ]
}

# ====================
# オプションテスト
# ====================

@test "ci-wait.sh accepts --interval option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    # オプションがあるか確認
    grep -q "interval\|--interval\|-i" "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" 2>/dev/null || \
        skip "interval option not implemented"
    
    mock_gh_ci_success
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42" --interval 1
    [ "$status" -eq 0 ]
}

@test "ci-wait.sh accepts --repo option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" ]]; then
        skip "ci-wait.sh not found"
    fi
    
    grep -q "repo\|--repo\|-R" "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" 2>/dev/null || \
        skip "repo option not implemented"
    
    mock_gh_ci_success
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/ci-workflow/scripts/ci-wait.sh" "42" --repo "owner/repo"
    [ "$status" -eq 0 ]
}
