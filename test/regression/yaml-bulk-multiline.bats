#!/usr/bin/env bats
# 回帰テスト: yaml_get_bulk がリテラルブロック（| 記法）で値がずれる問題
#
# 問題: yq のリテラルブロック値は末尾に改行を含む。
# yaml_get_bulk のバルク出力で各値の後に空行が入り、
# _parse_simple_configs の行カウンタがずれて全hookの値が1つずつシフトした。
#
# 例: on_improve_start に on_error の値が入り、
# improve実行時にエラー通知（Bassoサウンド）が発火。

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/yaml.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "yaml_get_bulk: multiline literal block values do not shift subsequent values" {
    local yaml_file="${BATS_TEST_TMPDIR}/hooks.yaml"
    cat > "$yaml_file" << 'EOF'
hooks:
  on_success: |
    echo "success"
  on_error: |
    echo "error"
  on_start: |
    echo "start"
EOF

    _YAML_CACHE_FILE=""
    _YAML_CACHE_CONTENT=""

    local result
    result="$(yaml_get_bulk "$yaml_file" ".hooks.on_success" ".hooks.on_error" ".hooks.on_start")"

    local line1 line2 line3
    line1="$(echo "$result" | sed -n '1p')"
    line2="$(echo "$result" | sed -n '2p')"
    line3="$(echo "$result" | sed -n '3p')"

    [[ "$line1" == *"success"* ]]
    [[ "$line2" == *"error"* ]]
    [[ "$line3" == *"start"* ]]
}

@test "yaml_get_bulk: exactly N lines for N paths with multiline values" {
    local yaml_file="${BATS_TEST_TMPDIR}/hooks.yaml"
    cat > "$yaml_file" << 'EOF'
hooks:
  key_a: |
    value_a
  key_b: |
    value_b
  key_c: simple_value
  key_d: |
    value_d
EOF

    _YAML_CACHE_FILE=""
    _YAML_CACHE_CONTENT=""

    local result
    result="$(yaml_get_bulk "$yaml_file" ".hooks.key_a" ".hooks.key_b" ".hooks.key_c" ".hooks.key_d")"

    local line_count
    line_count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 4 ]
}

@test "yaml_get_bulk: mixed inline and literal block values maintain correct mapping" {
    local yaml_file="${BATS_TEST_TMPDIR}/mixed.yaml"
    cat > "$yaml_file" << 'EOF'
hooks:
  allow_inline: true
  on_success: |
    osascript -e 'display notification "done" sound name "Glass"'
  on_error: |
    osascript -e 'display notification "fail" sound name "Basso"'
  on_start: simple_command
  on_improve_start: |
    osascript -e 'display notification "improve" sound name "Pop"'
EOF

    _YAML_CACHE_FILE=""
    _YAML_CACHE_CONTENT=""

    local result
    result="$(yaml_get_bulk "$yaml_file" \
        ".hooks.allow_inline" \
        ".hooks.on_success" \
        ".hooks.on_error" \
        ".hooks.on_start" \
        ".hooks.on_improve_start")"

    local line1 line2 line3 line4 line5
    line1="$(echo "$result" | sed -n '1p')"
    line2="$(echo "$result" | sed -n '2p')"
    line3="$(echo "$result" | sed -n '3p')"
    line4="$(echo "$result" | sed -n '4p')"
    line5="$(echo "$result" | sed -n '5p')"

    [ "$line1" = "true" ]
    [[ "$line2" == *"Glass"* ]]
    [[ "$line3" == *"Basso"* ]]
    [[ "$line4" == *"simple_command"* ]]
    [[ "$line5" == *"Pop"* ]]
}

@test "config load_config: hook values are correctly mapped with literal blocks" {
    local yaml_file="${BATS_TEST_TMPDIR}/config.yaml"
    cat > "$yaml_file" << 'EOF'
hooks:
  allow_inline: true
  on_success: |
    echo "SUCCESS_MARKER"
  on_error: |
    echo "ERROR_MARKER"
  on_improve_start: |
    echo "IMPROVE_START_MARKER"
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    _CONFIG_LOADED=""
    _YAML_CACHE_FILE=""
    _YAML_CACHE_CONTENT=""

    load_config "$yaml_file"

    local success_hook error_hook improve_hook
    success_hook="$(get_config hooks_on_success)"
    error_hook="$(get_config hooks_on_error)"
    improve_hook="$(get_config hooks_on_improve_start)"

    [[ "$success_hook" == *"SUCCESS_MARKER"* ]]
    [[ "$error_hook" == *"ERROR_MARKER"* ]]
    [[ "$improve_hook" == *"IMPROVE_START_MARKER"* ]]

    # Ensure no cross-contamination
    [[ "$success_hook" != *"ERROR_MARKER"* ]]
    [[ "$error_hook" != *"SUCCESS_MARKER"* ]]
    [[ "$improve_hook" != *"ERROR_MARKER"* ]]
}
