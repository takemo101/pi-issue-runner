#!/usr/bin/env bash
# init_test.sh - scripts/init.sh のテスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="$SCRIPT_DIR/../scripts/init.sh"

TESTS_PASSED=0
TESTS_FAILED=0

# テスト用一時ディレクトリ
TEST_DIR=""

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    git init -q
}

teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

assert_file_exists() {
    local description="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  File not found: $file"
        ((TESTS_FAILED++)) || true
    fi
}

assert_dir_exists() {
    local description="$1"
    local dir="$2"
    if [[ -d "$dir" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Directory not found: $dir"
        ((TESTS_FAILED++)) || true
    fi
}

assert_file_contains() {
    local description="$1"
    local file="$2"
    local pattern="$3"
    if [[ -f "$file" ]] && grep -q "$pattern" "$file"; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Pattern '$pattern' not found in $file"
        ((TESTS_FAILED++)) || true
    fi
}

assert_file_not_exists() {
    local description="$1"
    local file="$2"
    if [[ ! -f "$file" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  File should not exist: $file"
        ((TESTS_FAILED++)) || true
    fi
}

assert_output_contains() {
    local description="$1"
    local output="$2"
    local pattern="$3"
    if echo "$output" | grep -qF -- "$pattern"; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Pattern '$pattern' not found in output"
        ((TESTS_FAILED++)) || true
    fi
}

# === Tests ===

echo "=== init.sh tests ==="
echo ""

# Test 1: 標準モードでの初期化
echo "--- Test: Standard mode ---"
setup
output=$("$INIT_SCRIPT" 2>&1)
assert_file_exists "Creates .pi-runner.yaml" ".pi-runner.yaml"
assert_dir_exists "Creates .worktrees/ directory" ".worktrees"
assert_file_exists "Creates .worktrees/.gitkeep" ".worktrees/.gitkeep"
assert_file_exists "Creates/updates .gitignore" ".gitignore"
assert_file_contains ".gitignore contains .worktrees/" ".gitignore" "\.worktrees/"
assert_file_contains ".pi-runner.yaml contains worktree section" ".pi-runner.yaml" "worktree:"
assert_output_contains "Output shows success message" "$output" "初期化完了"
teardown

# Test 2: --minimal モードでの初期化
echo ""
echo "--- Test: Minimal mode ---"
setup
output=$("$INIT_SCRIPT" --minimal 2>&1)
assert_file_exists "Creates .pi-runner.yaml in minimal mode" ".pi-runner.yaml"
assert_file_not_exists ".worktrees/.gitkeep not created in minimal mode" ".worktrees/.gitkeep"
assert_output_contains "Output shows minimal completion message" "$output" "最小初期化完了"
teardown

# Test 3: --full モードでの初期化
echo ""
echo "--- Test: Full mode ---"
setup
output=$("$INIT_SCRIPT" --full 2>&1)
assert_file_exists "Creates .pi-runner.yaml in full mode" ".pi-runner.yaml"
assert_dir_exists "Creates .worktrees/ in full mode" ".worktrees"
assert_file_exists "Creates agents/custom.md in full mode" "agents/custom.md"
assert_file_exists "Creates workflows/custom.yaml in full mode" "workflows/custom.yaml"
assert_file_contains "agents/custom.md contains template variables" "agents/custom.md" "{{issue_number}}"
assert_file_contains "workflows/custom.yaml contains steps" "workflows/custom.yaml" "steps:"
teardown

# Test 4: 既存ファイルがある場合の警告
echo ""
echo "--- Test: Existing files warning ---"
setup
echo "existing content" > ".pi-runner.yaml"
output=$("$INIT_SCRIPT" 2>&1) || true  # エラーでも続行
assert_output_contains "Shows warning for existing file" "$output" "既に存在します"
# 内容が変わっていないことを確認
assert_file_contains "Existing file not overwritten" ".pi-runner.yaml" "existing content"
teardown

# Test 5: --force による上書き
echo ""
echo "--- Test: Force overwrite ---"
setup
echo "existing content" > ".pi-runner.yaml"
output=$("$INIT_SCRIPT" --force 2>&1)
assert_file_contains ".pi-runner.yaml overwritten with --force" ".pi-runner.yaml" "worktree:"
assert_output_contains "Output shows overwrite message" "$output" "上書き"
teardown

# Test 6: Git リポジトリ外でのエラー
echo ""
echo "--- Test: Error outside git repo ---"
TEST_DIR="$(mktemp -d)"
cd "$TEST_DIR"
# git init しない
output=$("$INIT_SCRIPT" 2>&1) || true
assert_output_contains "Shows error for non-git directory" "$output" "Git リポジトリではありません"
rm -rf "$TEST_DIR"

# Test 7: .gitignore の重複エントリ防止
echo ""
echo "--- Test: No duplicate gitignore entries ---"
setup
echo ".worktrees/" > ".gitignore"
"$INIT_SCRIPT" > /dev/null 2>&1 || true
# .worktrees/ が1回だけ存在することを確認
count=$(grep -c "^\.worktrees/$" ".gitignore" || echo "0")
if [[ "$count" == "1" ]]; then
    echo "✓ No duplicate .worktrees/ entry in .gitignore"
    ((TESTS_PASSED++)) || true
else
    echo "✗ Duplicate .worktrees/ entries in .gitignore (count: $count)"
    ((TESTS_FAILED++)) || true
fi
teardown

# Test 8: ヘルプ表示
echo ""
echo "--- Test: Help display ---"
output=$("$INIT_SCRIPT" --help 2>&1)
assert_output_contains "Help shows --full option" "$output" "--full"
assert_output_contains "Help shows --minimal option" "$output" "--minimal"
assert_output_contains "Help shows --force option" "$output" "--force"

echo ""
echo "=== Results ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

exit $TESTS_FAILED
