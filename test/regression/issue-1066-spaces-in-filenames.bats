#!/usr/bin/env bats
# Regression test for Issue #1066
# https://github.com/kawasakiisao/pi-issue-runner/issues/1066
#
# copy_files_to_worktree がスペースを含むファイルパスを正しく処理できない問題の回帰テスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export TEST_WORKTREE_BASE="$BATS_TEST_TMPDIR/worktrees"
    mkdir -p "$TEST_WORKTREE_BASE"
    
    # 設定をリセット
    unset _CONFIG_LOADED
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# Issue #1066: スペースを含むファイル名の処理
# ====================

@test "Issue #1066: copy_files_to_worktree handles single file with spaces" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    cd "$PROJECT_ROOT"
    
    # YAML設定ファイルを作成
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
worktree:
  copy_files:
    - "my config.yml"
EOF
    
    # スペースを含むファイルを作成
    echo "value: test" > "my config.yml"
    
    _CONFIG_LOADED=""
    load_config "$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/worktree"
    mkdir -p "$TEST_COPY_DIR"
    
    # コピー実行
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    # ファイルが正しくコピーされたことを確認
    [ -f "$TEST_COPY_DIR/my config.yml" ]
    
    # 内容も確認
    grep -q "value: test" "$TEST_COPY_DIR/my config.yml"
    
    # クリーンアップ
    rm -f "my config.yml"
}

@test "Issue #1066: copy_files_to_worktree handles multiple files with spaces" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    cd "$PROJECT_ROOT"
    
    # YAML設定ファイルを作成（複数ファイル、一部にスペース含む）
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
worktree:
  copy_files:
    - "config file 1.yml"
    - ".env.local"
    - "another config.json"
EOF
    
    # テストファイルを作成
    echo "file1" > "config file 1.yml"
    echo "file2" > ".env.local"
    echo "file3" > "another config.json"
    
    _CONFIG_LOADED=""
    load_config "$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/worktree2"
    mkdir -p "$TEST_COPY_DIR"
    
    # コピー実行
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    # 全てのファイルが正しくコピーされたことを確認
    [ -f "$TEST_COPY_DIR/config file 1.yml" ]
    [ -f "$TEST_COPY_DIR/.env.local" ]
    [ -f "$TEST_COPY_DIR/another config.json" ]
    
    # 内容も確認
    grep -q "file1" "$TEST_COPY_DIR/config file 1.yml"
    grep -q "file2" "$TEST_COPY_DIR/.env.local"
    grep -q "file3" "$TEST_COPY_DIR/another config.json"
    
    # クリーンアップ
    rm -f "config file 1.yml" ".env.local" "another config.json"
}

@test "Issue #1066: copy_files_to_worktree skips non-existent files with spaces" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    cd "$PROJECT_ROOT"
    
    # 存在しないファイルを含む設定
    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << 'EOF'
worktree:
  copy_files:
    - "non existent file.yml"
    - ".env.existing"
EOF
    
    # 1つだけ存在するファイルを作成
    echo "exists" > ".env.existing"
    
    _CONFIG_LOADED=""
    load_config "$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/worktree3"
    mkdir -p "$TEST_COPY_DIR"
    
    # コピー実行（エラーなく完了すべき）
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    # 存在するファイルのみがコピーされたことを確認
    [ ! -f "$TEST_COPY_DIR/non existent file.yml" ]
    [ -f "$TEST_COPY_DIR/.env.existing" ]
    
    grep -q "exists" "$TEST_COPY_DIR/.env.existing"
    
    # クリーンアップ
    rm -f ".env.existing"
}

@test "Issue #1066: fallback to default when no config file" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # 設定ファイルが見つからない環境でテスト
    # 一時ディレクトリに移動して実行
    cd "$BATS_TEST_TMPDIR"
    
    # 設定ファイルを指定せず、環境変数でデフォルト値を設定
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_COPY_FILES=".env .envrc"
    
    # 設定ファイルなしで読み込み
    load_config
    
    # デフォルトファイルを作成
    echo "env" > ".env"
    echo "envrc" > ".envrc"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/worktree4"
    mkdir -p "$TEST_COPY_DIR"
    
    # デフォルト動作を確認
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    [ -f "$TEST_COPY_DIR/.env" ]
    [ -f "$TEST_COPY_DIR/.envrc" ]
    
    # クリーンアップ
    rm -f ".env" ".envrc"
    unset PI_RUNNER_WORKTREE_COPY_FILES
}
