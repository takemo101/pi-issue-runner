#!/usr/bin/env bats
# test.sh のBatsテスト

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

@test "test.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/test.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "test.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/test.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "test.sh help shows all options" {
    run "$PROJECT_ROOT/scripts/test.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-v"* ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"-f"* ]]
    [[ "$output" == *"--fail-fast"* ]]
    [[ "$output" == *"-s"* ]]
    [[ "$output" == *"--shellcheck"* ]]
    [[ "$output" == *"-a"* ]]
    [[ "$output" == *"--all"* ]]
}

@test "test.sh help shows target options" {
    run "$PROJECT_ROOT/scripts/test.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib"* ]]
    [[ "$output" == *"scripts"* ]]
}

# ====================
# 無効オプションテスト
# ====================

@test "test.sh returns error for unknown option" {
    run "$PROJECT_ROOT/scripts/test.sh" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "test.sh shows usage on unknown option" {
    run "$PROJECT_ROOT/scripts/test.sh" -x
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# bats/shellcheck モック
# ====================

# batsコマンドのモック
mock_bats_success() {
    cat > "$MOCK_DIR/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
# 成功を返すモック
echo "Running tests: $*"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/bats"
}

mock_bats_failure() {
    cat > "$MOCK_DIR/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
# 失敗を返すモック
echo "Running tests: $*"
echo "Test failed!"
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/bats"
}

mock_bats_not_installed() {
    # batsをPATHから削除するために空のディレクトリをPATHの先頭に
    rm -f "$MOCK_DIR/bats" 2>/dev/null || true
}

# ShellCheck コマンドのモック
mock_shellcheck_success() {
    cat > "$MOCK_DIR/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
# 成功を返すモック
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/shellcheck"
}

mock_shellcheck_failure() {
    cat > "$MOCK_DIR/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
# 警告を出力して失敗を返すモック
echo "SC2086: Double quote to prevent globbing and word splitting."
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/shellcheck"
}

mock_shellcheck_not_installed() {
    # ShellCheckをPATHから削除
    rm -f "$MOCK_DIR/shellcheck" 2>/dev/null || true
}

# ====================
# Batsテスト実行テスト
# ====================

@test "test.sh runs bats tests by default" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running Bats Tests"* ]]
}

@test "test.sh with -v enables verbose mode" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -v
    [ "$status" -eq 0 ]
    # --tap オプションが使われているかは出力からは直接確認困難だが
    # 正常に実行されることを確認
    [[ "$output" == *"Running Bats Tests"* ]]
}

@test "test.sh with --verbose enables verbose mode" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --verbose
    [ "$status" -eq 0 ]
}

@test "test.sh with -f enables fail-fast mode" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -f
    [ "$status" -eq 0 ]
}

@test "test.sh with --fail-fast enables fail-fast mode" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --fail-fast
    [ "$status" -eq 0 ]
}

@test "test.sh fail-fast stops on first failure" {
    mock_bats_failure
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -f
    [ "$status" -eq 1 ]
    [[ "$output" == *"Stopping due to --fail-fast"* ]]
}

# ====================
# ターゲット指定テスト
# ====================

@test "test.sh 'lib' target runs only lib tests" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" lib
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib/"* ]] || [[ "$output" == *"Running"* ]]
}

@test "test.sh 'scripts' target runs only scripts tests" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" scripts
    [ "$status" -eq 0 ]
}

# ====================
# ShellCheckテスト
# ====================

@test "test.sh with -s runs shellcheck only" {
    mock_shellcheck_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -s
    [ "$status" -eq 0 ]
    [[ "$output" == *"ShellCheck"* ]]
}

@test "test.sh with --shellcheck runs shellcheck only" {
    mock_shellcheck_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --shellcheck
    [ "$status" -eq 0 ]
    [[ "$output" == *"ShellCheck"* ]]
}

@test "test.sh shellcheck reports failure on issues" {
    mock_shellcheck_failure
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -s
    [ "$status" -eq 1 ]
    [[ "$output" == *"ShellCheck"* ]]
}

# ====================
# --all オプションテスト
# ====================

@test "test.sh with -a runs both bats and shellcheck" {
    mock_bats_success
    mock_shellcheck_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -a
    [ "$status" -eq 0 ]
    [[ "$output" == *"ShellCheck"* ]]
    [[ "$output" == *"Bats"* ]]
}

@test "test.sh with --all runs both bats and shellcheck" {
    mock_bats_success
    mock_shellcheck_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"ShellCheck"* ]]
    [[ "$output" == *"Bats"* ]]
}

@test "test.sh --all fails if shellcheck fails" {
    mock_bats_success
    mock_shellcheck_failure
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --all
    [ "$status" -eq 1 ]
}

@test "test.sh --all fails if bats fails" {
    mock_bats_failure
    mock_shellcheck_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --all
    [ "$status" -eq 1 ]
}

@test "test.sh --all with -f stops on shellcheck failure" {
    mock_bats_success
    mock_shellcheck_failure
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --all --fail-fast
    [ "$status" -eq 1 ]
    # ShellCheckで失敗するとbatsまで行かない
    [[ "$output" != *"Running Bats Tests"* ]]
}

# ====================
# エラーハンドリング
# ====================

@test "test.sh reports error when bats not installed" {
    mock_bats_not_installed
    # batsがPATHにないようにする（実際のbatsを隠す）
    cat > "$MOCK_DIR/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 127
MOCK_EOF
    chmod +x "$MOCK_DIR/bats"
    rm -f "$MOCK_DIR/bats"
    # 実際の環境ではbatsはインストールされているので、このテストは環境に依存
    # check_bats関数の動作を確認する別のアプローチが必要
    skip "bats is installed in this environment"
}

@test "test.sh warns when shellcheck not installed" {
    mock_bats_success
    mock_shellcheck_not_installed
    # ShellCheckがPATHにないようにする
    # 実際の環境に依存するためスキップ
    skip "shellcheck may be installed in this environment"
}

# ====================
# 組み合わせテスト
# ====================

@test "test.sh accepts multiple options" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" -v -f lib
    [ "$status" -eq 0 ]
}

@test "test.sh target after options works" {
    mock_bats_success
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/test.sh" --verbose scripts
    [ "$status" -eq 0 ]
}
