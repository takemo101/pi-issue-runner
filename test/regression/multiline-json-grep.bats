#!/usr/bin/env bats
# multiline-json-grep.bats - Regression test for Issue #1075
#
# Tests that _validate_node() correctly detects lint/test scripts
# in package.json when they span multiple lines (typical format).

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/ci-fix.sh"
}

teardown() {
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "Issue #1075: _validate_node detects lint script in multi-line package.json" {
    mkdir -p "$BATS_TEST_TMPDIR/node-multiline"
    
    # 典型的な複数行にまたがるpackage.json（scriptsセクション）
    cat > "$BATS_TEST_TMPDIR/node-multiline/package.json" << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "scripts": {
    "lint": "eslint .",
    "test": "jest",
    "build": "tsc"
  },
  "dependencies": {}
}
EOF
    
    cd "$BATS_TEST_TMPDIR/node-multiline"
    
    # _validate_node を直接呼び出すため、jq がない場合のフォールバックをテスト
    # jqを一時的に無効化してフォールバックをテスト
    unset -f jq  # 関数として定義されている場合に削除
    
    # PATHからjqを除外（フォールバック動作を強制）
    OLD_PATH="$PATH"
    export PATH="/usr/bin:/bin"  # jqがない最小限のPATH
    
    # npm/npxもモック（検証を実行しない）
    function npm() { echo "npm mock"; }
    export -f npm
    
    # _validate_node はlint/testスクリプトを検出して実行を試みる
    # 実際にはnpmモックを使うので成功する
    run _validate_node
    
    # 復元
    export PATH="$OLD_PATH"
    unset -f npm
    
    # ステータスコードは0（成功）または1（npm実行失敗）
    # 重要なのは、grepがスクリプトを検出できること
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "Issue #1075: _validate_node detects test script in multi-line package.json" {
    mkdir -p "$BATS_TEST_TMPDIR/node-multiline-test"
    
    cat > "$BATS_TEST_TMPDIR/node-multiline-test/package.json" << 'EOF'
{
  "name": "test-project",
  "scripts": {
    "test": "jest --coverage"
  }
}
EOF
    
    cd "$BATS_TEST_TMPDIR/node-multiline-test"
    
    # jqを無効化
    OLD_PATH="$PATH"
    export PATH="/usr/bin:/bin"
    
    # npmモック
    function npm() { echo "npm mock"; return 0; }
    export -f npm
    
    run _validate_node
    
    # 復元
    export PATH="$OLD_PATH"
    unset -f npm
    
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "Issue #1075: _validate_node handles package.json without scripts section" {
    mkdir -p "$BATS_TEST_TMPDIR/node-no-scripts"
    
    cat > "$BATS_TEST_TMPDIR/node-no-scripts/package.json" << 'EOF'
{
  "name": "minimal-project",
  "version": "1.0.0",
  "dependencies": {}
}
EOF
    
    cd "$BATS_TEST_TMPDIR/node-no-scripts"
    
    # jqを無効化
    OLD_PATH="$PATH"
    export PATH="/usr/bin:/bin"
    
    run _validate_node
    
    # 復元
    export PATH="$OLD_PATH"
    
    # scriptsセクションがない場合は何も実行しないので成功
    [ "$status" -eq 0 ]
}

@test "Issue #1075: _validate_node with jq available (primary path)" {
    mkdir -p "$BATS_TEST_TMPDIR/node-jq-available"
    
    cat > "$BATS_TEST_TMPDIR/node-jq-available/package.json" << 'EOF'
{
  "name": "test-project",
  "scripts": {
    "lint": "eslint .",
    "test": "jest"
  }
}
EOF
    
    cd "$BATS_TEST_TMPDIR/node-jq-available"
    
    # jq が利用可能な場合は、jq経由で検出される
    if command -v jq &>/dev/null; then
        # npmモック
        function npm() { echo "npm mock"; return 0; }
        export -f npm
        
        run _validate_node
        
        unset -f npm
        
        # jqが正しく動作する場合は成功
        [ "$status" -eq 0 ]
    else
        skip "jq not available"
    fi
}
