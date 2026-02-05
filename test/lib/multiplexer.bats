#!/usr/bin/env bats
# multiplexer.sh のBatsテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    export _CONFIG_LOADED=""
    unset _MUX_TYPE
    export CONFIG_MULTIPLEXER_TYPE="tmux"
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# get_multiplexer_type テスト
# ====================

@test "get_multiplexer_type returns default value (tmux)" {
    # テスト用ディレクトリに移動（.pi-runner.yamlを回避）
    local test_dir="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # 空の設定ファイル
    touch ".pi-runner.yaml"
    
    # モックtmuxを作成
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    result="$(get_multiplexer_type)"
    [ "$result" = "tmux" ]
}

@test "get_multiplexer_type respects config value" {
    # 設定ファイルでzellij指定
    cat > "$TEST_CONFIG_FILE" << EOF
multiplexer_type: zellij
EOF
    
    # モックzellijを作成
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/zellij"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    result="$(get_multiplexer_type)"
    [ "$result" = "zellij" ]
}

@test "get_multiplexer_type caches the result" {
    # テスト用ディレクトリに移動
    local test_dir="$BATS_TEST_TMPDIR/test-cache"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # 空の設定ファイル
    touch ".pi-runner.yaml"
    
    # モックtmuxを作成
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    # 初回呼び出し
    first_result="$(get_multiplexer_type)"
    [ "$first_result" = "tmux" ]
    
    # 2回目の呼び出し - 同じ結果が返るはず（キャッシュ機能のテスト）
    second_result="$(get_multiplexer_type)"
    [ "$second_result" = "tmux" ]
    [ "$first_result" = "$second_result" ]
}

# ====================
# _load_multiplexer_impl テスト
# ====================

@test "_load_multiplexer_impl loads tmux implementation" {
    # モックtmuxを作成
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # multiplexer.shをソース（tmux実装がロードされる）
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    # tmux実装の関数が存在することを確認
    declare -f mux_check > /dev/null
}

@test "_load_multiplexer_impl loads zellij implementation" {
    # zellij設定でmultiplexer.shをロード
    cat > "$TEST_CONFIG_FILE" << EOF
multiplexer_type: zellij
EOF
    
    # モックzellijを作成
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/zellij"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # multiplexer.shをソース（zellij実装がロードされる）
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    # zellij実装の関数が存在することを確認
    declare -f mux_check > /dev/null
}

@test "_load_multiplexer_impl fails on unknown type" {
    # テスト用ディレクトリに移動
    local test_dir="$BATS_TEST_TMPDIR/test-unknown"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # 未対応のタイプを指定
    cat > ".pi-runner.yaml" << EOF
multiplexer:
  type: screen
EOF
    
    # サブシェルでテスト実行（set -e で失敗するはず）
    run bash -euo pipefail -c "
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/multiplexer.sh' 2>&1
    "
    
    # 実装がロードに失敗したことを確認
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown multiplexer"* ]]
    [[ "$output" == *"screen"* ]]
}

# ====================
# 統合テスト
# ====================

@test "multiplexer.sh provides common interface with tmux" {
    # モックtmuxを作成
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # multiplexer.shをロード
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    # 共通インターフェースの関数が存在することを確認
    declare -f mux_check > /dev/null
    declare -f mux_generate_session_name > /dev/null
    declare -f mux_extract_issue_number > /dev/null
    declare -f mux_create_session > /dev/null
    declare -f mux_session_exists > /dev/null
    declare -f mux_list_sessions > /dev/null
}

@test "multiplexer.sh provides common interface with zellij" {
    cat > "$TEST_CONFIG_FILE" << EOF
multiplexer_type: zellij
EOF
    
    # モックzellijを作成
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/zellij"
    
    # モックnohup, scriptも作成
    cat > "$MOCK_DIR/nohup" << 'EOF'
#!/usr/bin/env bash
exec "$@" &
EOF
    chmod +x "$MOCK_DIR/nohup"
    
    cat > "$MOCK_DIR/script" << 'EOF'
#!/usr/bin/env bash
shift 3
exec "$@"
EOF
    chmod +x "$MOCK_DIR/script"
    
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
    
    # multiplexer.shをロード
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    
    # 共通インターフェースの関数が存在することを確認
    declare -f mux_check > /dev/null
    declare -f mux_generate_session_name > /dev/null
    declare -f mux_extract_issue_number > /dev/null
    declare -f mux_create_session > /dev/null
    declare -f mux_session_exists > /dev/null
    declare -f mux_list_sessions > /dev/null
}
