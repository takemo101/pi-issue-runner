#!/usr/bin/env bash
# yaml.sh - 統一YAMLパーサー（yq + フォールバック）
#
# yqが利用可能な場合はyqを使用し、そうでない場合は
# 簡易パーサーにフォールバックする。

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_YAML_SH_SOURCED:-}" ]]; then
    return 0
fi
_YAML_SH_SOURCED="true"

# ロギング機能を読み込み（条件付き）
_YAML_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_YAML_LIB_DIR}/log.sh" ]]; then
    # shellcheck source=lib/log.sh
    source "${_YAML_LIB_DIR}/log.sh"
fi

# log_warn が定義されていない場合のフォールバック
if ! declare -f log_warn > /dev/null 2>&1; then
    log_warn() {
        echo "[WARN] $*" >&2
    }
fi

# ===================
# yq チェック
# ===================

# yq チェック結果のキャッシュ（空: 未チェック、"1": 存在、"0": 不在）
_YQ_CHECK_RESULT="${_YQ_CHECK_RESULT:-}"

# yq の存在確認（結果をキャッシュ）
check_yq() {
    # キャッシュがある場合はそれを返す
    if [[ -n "$_YQ_CHECK_RESULT" ]]; then
        [[ "$_YQ_CHECK_RESULT" == "1" ]]
        return
    fi
    
    # 初回のみ実際にチェック
    if command -v yq &> /dev/null; then
        _YQ_CHECK_RESULT="1"
        return 0
    else
        _YQ_CHECK_RESULT="0"
        return 1
    fi
}

# yq キャッシュをリセット（テスト用）
reset_yq_cache() {
    _YQ_CHECK_RESULT=""
}

# ===================
# ファイルキャッシュ
# ===================

# キャッシュされたファイルパス
_YAML_CACHE_FILE="${_YAML_CACHE_FILE:-}"

# キャッシュされたファイル内容
_YAML_CACHE_CONTENT="${_YAML_CACHE_CONTENT:-}"

# ファイルをキャッシュに読み込む（キャッシュミス時のみ）
# Usage: _yaml_ensure_cached <file>
# Note: キャッシュ変数を直接設定（出力なし）
_yaml_ensure_cached() {
    local file="$1"
    
    # キャッシュヒット
    if [[ "$file" == "$_YAML_CACHE_FILE" && -n "$_YAML_CACHE_CONTENT" ]]; then
        return 0
    fi
    
    # ファイル読み込み＆キャッシュ
    _YAML_CACHE_FILE="$file"
    _YAML_CACHE_CONTENT="$(cat "$file")"
}

# YAMLキャッシュをクリア
reset_yaml_cache() {
    _YAML_CACHE_FILE=""
    _YAML_CACHE_CONTENT=""
}

# ===================
# メイン関数
# ===================

# YAML から単一値を取得
# Usage: yaml_get <file> <path> [default]
# Example: yaml_get config.yaml ".worktree.base_dir" ".worktrees"
yaml_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    if [[ ! -f "$file" ]]; then
        echo "$default"
        return 0
    fi
    
    if check_yq; then
        _yq_get "$file" "$path" "$default"
    else
        _simple_yaml_get "$file" "$path" "$default"
    fi
}

# YAML から配列値を取得（各要素を1行ずつ出力）
# Usage: yaml_get_array <file> <path>
# Example: yaml_get_array config.yaml ".worktree.copy_files"
yaml_get_array() {
    local file="$1"
    local path="$2"
    
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    if check_yq; then
        _yq_get_array "$file" "$path"
    else
        _simple_yaml_get_array "$file" "$path"
    fi
}

# YAML パスが存在するか確認
# Usage: yaml_exists <file> <path>
# Example: yaml_exists config.yaml ".workflow"
yaml_exists() {
    local file="$1"
    local path="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if check_yq; then
        _yaml_ensure_cached "$file"
        echo "$_YAML_CACHE_CONTENT" | yq -e "$path" - &>/dev/null
    else
        _simple_yaml_exists "$file" "$path"
    fi
}

# YAML セクション直下のキー一覧を取得
# Usage: yaml_get_keys <file> <path>
# Example: yaml_get_keys config.yaml ".workflows"
yaml_get_keys() {
    local file="$1"
    local path="$2"
    
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    if check_yq; then
        _yq_get_keys "$file" "$path"
    else
        _simple_yaml_get_keys "$file" "$path"
    fi
}

# ===================
# バルク取得（複数パス一括）
# ===================

# YAML から複数パスの値を一括取得（yqを1回だけ呼ぶ）
# Usage: yaml_get_bulk <file> <path1> <path2> ...
# Output: 1行ずつ値を出力（nullの場合は空行）
# Note: yqが利用可能な場合のみバルク最適化。なければ個別フォールバック
yaml_get_bulk() {
    local file="$1"
    shift
    local paths=("$@")
    
    if [[ ! -f "$file" || ${#paths[@]} -eq 0 ]]; then
        for _ in "${paths[@]}"; do
            echo ""
        done
        return 0
    fi
    
    if check_yq; then
        _yq_get_bulk "$file" "${paths[@]}"
    else
        # フォールバック: 個別取得
        for path in "${paths[@]}"; do
            _simple_yaml_get "$file" "$path" ""
        done
    fi
}

# yq バルク取得実装
_yq_get_bulk() {
    local file="$1"
    shift
    local paths=("$@")
    
    _yaml_ensure_cached "$file"
    
    # 空コンテンツの場合は全て空行
    if [[ -z "$_YAML_CACHE_CONTENT" ]]; then
        for _ in "${paths[@]}"; do
            echo ""
        done
        return 0
    fi
    
    # yqの式を構築: 各pathを文字列にキャストして出力
    # (path | . tag = "!!str") で null → "null", false → "false" を保持
    # 各pathが必ず1行出力されるため、行数がpaths数と一致する
    local yq_expr=""
    for path in "${paths[@]}"; do
        if [[ -n "$yq_expr" ]]; then
            yq_expr="${yq_expr}, "
        fi
        yq_expr="${yq_expr}(${path} | . tag = \"!!str\")"
    done
    
    # 単一のyq呼び出しで全パスの値を取得
    local result
    result=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${yq_expr}" - 2>/dev/null) || {
        # yq失敗時はフォールバック
        for path in "${paths[@]}"; do
            yaml_get "$file" "$path" ""
        done
        return 0
    }
    
    echo "$result"
}

# ===================
# yq 実装
# ===================

# yq で値を取得
_yq_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    _yaml_ensure_cached "$file"
    
    # 単一のyq呼び出しで値を取得
    # . tag = "!!str" でfalseも文字列として取得し、nullはそのまま
    local value
    value=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${path} | . tag = \"!!str\"" - 2>/dev/null || echo "null")
    
    if [[ "$value" != "null" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# yq で配列を取得
_yq_get_array() {
    local file="$1"
    local path="$2"
    
    _yaml_ensure_cached "$file"
    
    echo "$_YAML_CACHE_CONTENT" | yq -r "${path}[]" - 2>/dev/null || true
}

# yq でキー一覧を取得
_yq_get_keys() {
    local file="$1"
    local path="$2"
    
    _yaml_ensure_cached "$file"
    
    # keys[] may fail in some yq versions; fall back to simple parser
    local result
    result=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${path} | keys | .[]" - 2>/dev/null) || true
    if [[ -n "$result" ]]; then
        echo "$result"
    else
        # yq failed or returned empty; fall back to simple parser
        _simple_yaml_get_keys "$file" "$path"
    fi
}

# ===================
# 簡易パーサー - ヘルパー関数
# ===================

# パス階層を検証（最大3階層）
_yaml_validate_depth() {
    local path="$1"
    local default="${2:-}"
    local path_parts="${path#.}"
    local depth
    depth=$(echo "$path_parts" | tr "." "\n" | wc -l | tr -d ' ')
    
    if [[ "$depth" -gt 3 ]]; then
        log_warn "Simple YAML parser only supports up to 3 levels of nesting: $path"
        log_warn "Install yq for full YAML support: brew install yq"
        echo "$default"
        return 1
    fi
    return 0
}

# パスをパース
_yaml_parse_path() {
    local path="$1"
    local path_parts="${path#.}"
    local section="" subsection="" key=""
    
    if [[ "$path_parts" =~ ^([^.]+)\.([^.]+)\.([^.]+)$ ]]; then
        section="${BASH_REMATCH[1]}"
        subsection="${BASH_REMATCH[2]}"
        key="${BASH_REMATCH[3]}"
    elif [[ "$path_parts" =~ ^([^.]+)\.([^.]+)$ ]]; then
        section="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
    else
        key="$path_parts"
    fi
    
    echo "$section|$subsection|$key"
}

# クォート除去
_yaml_strip_quotes() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    echo "$value"
}

# コメント・空行チェック
_yaml_is_comment_or_blank() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*# ]] && return 0
    [[ -z "${line// /}" ]] && return 0
    return 1
}

# リテラルブロック処理
_yaml_process_literal_block() {
    local -n _content_ref="$1"
    local line="$2"
    local literal_indent="$3"
    
    # 同レベル以上のキーで終了
    if [[ "$line" =~ ^[[:space:]]{0,$literal_indent}[a-z0-9_-]+: ]]; then
        return 1
    fi
    
    # 内容追加
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]]; then
        _content_ref+="${line:$((literal_indent + 2))}"$'\n'
    else
        _content_ref+=$'\n'
    fi
    return 0
}

# トップレベルキー処理
_yaml_process_level1() {
    local line="$1"
    local target_key="$2"
    
    if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*(.*) ]]; then
        local line_key="${BASH_REMATCH[1]}" line_value="${BASH_REMATCH[2]}"
        if [[ "$line_key" == "$target_key" && -n "$line_value" ]]; then
            _yaml_strip_quotes "$line_value"
            return 0
        fi
    fi
    return 1
}

# セクション内キー処理（レベル2）
_yaml_process_level2() {
    local line="$1"
    local target_key="$2"
    
    if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]+(.*) ]]; then
        local line_key="${BASH_REMATCH[1]}" line_value="${BASH_REMATCH[2]}"
        if [[ "$line_key" == "$target_key" && -n "$line_value" ]]; then
            _yaml_strip_quotes "$line_value"
            return 0
        fi
    fi
    return 1
}

# サブセクション内キー処理（レベル3）
_yaml_process_level3() {
    local line="$1"
    local target_key="$2"
    
    if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]+(.*) ]]; then
        local line_key="${BASH_REMATCH[1]}" line_value="${BASH_REMATCH[2]}"
        if [[ "$line_key" == "$target_key" && -n "$line_value" ]]; then
            _yaml_strip_quotes "$line_value"
            return 0
        fi
    fi
    return 1
}

# ===================
# 簡易パーサー - メイン関数
# ===================

# 値取得
_simple_yaml_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    _yaml_validate_depth "$path" "$default" || return 0
    
    local parsed section subsection key
    parsed="$(_yaml_parse_path "$path")"
    IFS='|' read -r section subsection key <<< "$parsed"
    
    local current_section="" current_subsection=""
    local found_value="" in_literal_block=false
    local literal_content="" literal_indent=0
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # リテラルブロック継続
        if [[ "$in_literal_block" == "true" ]]; then
            if ! _yaml_process_literal_block literal_content "$line" "$literal_indent"; then
                found_value="$literal_content"
                break
            fi
            continue
        fi
        
        _yaml_is_comment_or_blank "$line" && continue
        
        # セクション検出
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            continue
        fi
        
        # レベル1処理
        if [[ -z "$section" ]] && found_value="$(_yaml_process_level1 "$line" "$key")"; then
            break
        fi
        
        # レベル2処理
        if [[ -n "$section" && "$current_section" == "$section" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                current_subsection="${BASH_REMATCH[1]}"
                continue
            fi
            if [[ -z "$subsection" ]] && found_value="$(_yaml_process_level2 "$line" "$key")"; then
                break
            fi
        fi
        
        # レベル3処理
        if [[ -n "$section" && -n "$subsection" && "$current_section" == "$section" && "$current_subsection" == "$subsection" ]]; then
            # リテラルブロック開始
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]*\|[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_literal_block=true
                    literal_indent=4
                    literal_content=""
                fi
                continue
            fi
            if found_value="$(_yaml_process_level3 "$line" "$key")"; then
                break
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
    
    # 結果出力
    if [[ -n "$found_value" ]]; then
        if [[ "$in_literal_block" == "true" ]]; then
            echo -n "$found_value"
        else
            echo "$found_value"
        fi
    else
        echo "$default"
    fi
}

# 配列取得
_simple_yaml_get_array() {
    local file="$1"
    local path="$2"
    
    _yaml_validate_depth "$path" "" || return 0
    
    local parsed section subsection key
    parsed="$(_yaml_parse_path "$path")"
    IFS='|' read -r section subsection key <<< "$parsed"
    
    local current_section="" current_subsection=""
    local in_target_array=false array_indent=0
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        _yaml_is_comment_or_blank "$line" && continue
        
        # セクション検出
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            in_target_array=false
            continue
        fi
        
        # レベル2配列検出
        if [[ -n "$section" && -z "$subsection" && "$current_section" == "$section" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                    array_indent=2
                else
                    current_subsection="$line_key"
                    in_target_array=false
                fi
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]{2}[a-z0-9_-]+:[[:space:]]+[^[:space:]] ]]; then
                in_target_array=false
                continue
            fi
        fi
        
        # レベル3配列検出
        if [[ -n "$section" && -n "$subsection" && "$current_section" == "$section" && "$current_subsection" == "$subsection" ]]; then
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                [[ "$line_key" == "$key" ]] && in_target_array=true array_indent=4 || in_target_array=false
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]{4}[a-z0-9_-]+:[[:space:]]+[^[:space:]] ]]; then
                in_target_array=false
                continue
            fi
        fi
        
        # トップレベル配列検出
        if [[ -z "$section" && "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            local line_key="${BASH_REMATCH[1]}"
            [[ "$line_key" == "$key" ]] && in_target_array=true array_indent=0 || in_target_array=false
            continue
        fi
        
        # 配列項目出力
        if [[ "$in_target_array" == "true" ]]; then
            local expected_indent=$((array_indent + 2))
            if [[ "$line" =~ ^[[:space:]]{$expected_indent}-[[:space:]]+(.*) ]]; then
                _yaml_strip_quotes "${BASH_REMATCH[1]}"
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
}

# 存在確認
_simple_yaml_exists() {
    local file="$1"
    local path="$2"
    
    _yaml_validate_depth "$path" "" || return 1
    
    local parsed section subsection key
    parsed="$(_yaml_parse_path "$path")"
    IFS='|' read -r section subsection key <<< "$parsed"
    
    local current_section="" current_subsection=""
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        _yaml_is_comment_or_blank "$line" && continue
        
        # セクション検出
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            # 1階層のみ: .workflow → section='' key='workflow'
            [[ -z "$section" && -z "$subsection" && "$current_section" == "$key" ]] && return 0
            # または 2階層セクション: .section.subsection → section='section' subsection='subsection' key=''
            [[ -z "$subsection" && -z "$key" && "$current_section" == "$section" ]] && return 0
            continue
        fi
        
        # レベル2確認
        if [[ -n "$section" && "$current_section" == "$section" && "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+): ]]; then
            local line_key="${BASH_REMATCH[1]}"
            # 2階層
            [[ -z "$subsection" && -n "$key" && "$line_key" == "$key" ]] && return 0
            # サブセクション
            [[ -n "$subsection" && -z "$key" && "$line_key" == "$subsection" ]] && return 0
            [[ -n "$subsection" && "$line_key" == "$subsection" ]] && current_subsection="$subsection"
        fi
        
        # レベル3確認
        if [[ -n "$section" && -n "$subsection" && -n "$key" && "$current_section" == "$section" && "$current_subsection" == "$subsection" && "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+): ]]; then
            [[ "${BASH_REMATCH[1]}" == "$key" ]] && return 0
        fi
    done <<< "$_YAML_CACHE_CONTENT"
    
    return 1
}

# キー一覧取得
_simple_yaml_get_keys() {
    local file="$1"
    local path="$2"
    
    local section="${path#.}"
    local current_section="" in_target_section=false
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        _yaml_is_comment_or_blank "$line" && continue
        
        # セクション検出
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            in_target_section=$([[ "$current_section" == "$section" ]] && echo "true" || echo "false")
            continue
        fi
        
        # キー出力
        if [[ "$in_target_section" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+): ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[a-z0-9_-]+: ]]; then
                break
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
}
