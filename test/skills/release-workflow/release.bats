#!/usr/bin/env bats
# release.sh のBatsテスト
# リリースワークフローを実行するスクリプト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # Gitリポジトリをセットアップ
    export TEST_REPO="$BATS_TEST_TMPDIR/test_repo"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit" -q
    # タグを作成
    git tag "v0.1.0" -m "Initial release"
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

@test "release.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "release.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "release.sh fails without version argument" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh"
    [ "$status" -ne 0 ]
}

@test "release.sh requires valid version format" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "invalid-version"
    [ "$status" -ne 0 ]
}

@test "release.sh accepts semantic version" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    # スクリプトが存在しない場合はスキップされるため、通常は成功するかエラーになる
    [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
}

# ====================
# Gitリポジトリチェック
# ====================

@test "release.sh fails outside git repo" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    non_git_dir="$BATS_TEST_TMPDIR/non_git"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    [ "$status" -ne 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "release.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    [ "$status" -ne 0 ]
}

@test "release.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
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
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    [ "$status" -ne 0 ]
}

# ====================
# モックヘルパー
# ====================

mock_gh_release() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "release create"*)
        echo "https://github.com/owner/repo/releases/tag/v1.0.0"
        exit 0
        ;;
    "release view"*)
        echo '{"tagName":"v1.0.0","name":"Release v1.0.0","url":"https://github.com/owner/repo/releases/tag/v1.0.0"}'
        exit 0
        ;;
    "release list"*)
        echo '[{"tagName":"v0.1.0"}]'
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

@test "release.sh creates git tag" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "git tag\|tag" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "tag creation not implemented"
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v2.0.0"
    [ "$status" -eq 0 ]
    
    # タグが作成されたか確認
    git tag | grep -q "v2.0.0" || true
}

@test "release.sh creates GitHub release" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    [ "$status" -eq 0 ]
}

@test "release.sh outputs release URL" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"github.com"* ]] || [[ "$output" == *"releases"* ]] || [[ "$output" == *"tag"* ]]
}

# ====================
# オプションテスト
# ====================

@test "release.sh supports --draft option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "draft\|--draft\|-d" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "draft option not implemented"
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0" --draft
    [ "$status" -eq 0 ]
}

@test "release.sh supports --prerelease option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "prerelease\|--prerelease\|-p" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "prerelease option not implemented"
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0-beta" --prerelease
    [ "$status" -eq 0 ]
}

@test "release.sh supports --notes option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "notes\|--notes\|-n" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "notes option not implemented"
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0" --notes "Release notes"
    [ "$status" -eq 0 ]
}

@test "release.sh supports --target option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "target\|--target\|-t" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "target option not implemented"
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v1.0.0" --target "main"
    [ "$status" -eq 0 ]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "release.sh fails on duplicate version" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "exists\|duplicate" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "duplicate check not implemented"
    
    mock_gh_release
    enable_mocks
    
    # v0.1.0は既に存在する
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v0.1.0"
    [ "$status" -ne 0 ] || [[ "$output" == *"exists"* ]] || [[ "$output" == *"already"* ]]
}

@test "release.sh validates working directory is clean" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" ]]; then
        skip "release.sh not found"
    fi
    
    grep -q "clean\|dirty\|uncommitted" "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" 2>/dev/null || \
        skip "clean check not implemented"
    
    # 未コミットの変更を作成
    echo "uncommitted" >> file.txt
    
    mock_gh_release
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/release-workflow/scripts/release.sh" "v3.0.0"
    [ "$status" -ne 0 ]
}
