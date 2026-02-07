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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/log.sh" ]]; then
    # shellcheck source=lib/log.sh
    source "${SCRIPT_DIR}/log.sh"
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
# yq 実装
# ===================

# yq で値を取得
_yq_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    _yaml_ensure_cached "$file"
    
    local value
    # パスが存在するか確認してから値を取得（falseも正しく取得するため）
    if echo "$_YAML_CACHE_CONTENT" | yq -e "$path != null" - &>/dev/null; then
        value=$(echo "$_YAML_CACHE_CONTENT" | yq -r "$path" - 2>/dev/null || echo "")
        if [[ "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    echo "$default"
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
# 簡易パーサー実装（フォールバック）
# ===================

# 簡易パーサーで値を取得
# パス形式: .key, .section.key, .section.subsection.key（最大3階層）
_simple_yaml_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    # パス階層数を検証（簡易パーサーは最大3階層まで対応）
    local path_parts="${path#.}"  # 先頭のドットを除去
    local depth
    depth=$(echo "$path_parts" | tr "." "\n" | wc -l | tr -d ' ')
    if [[ "$depth" -gt 3 ]]; then
        log_warn "Simple YAML parser only supports up to 3 levels of nesting: $path"
        log_warn "Install yq for full YAML support: brew install yq"
        echo "$default"
        return 0
    fi
    
    # パスを最大3階層に分解（path_partsは既に定義済み）
    local section=""
    local subsection=""
    local key=""
    
    if [[ "$path_parts" =~ ^([^.]+)\.([^.]+)\.([^.]+)$ ]]; then
        # 3階層: workflows.quick.description
        section="${BASH_REMATCH[1]}"
        subsection="${BASH_REMATCH[2]}"
        key="${BASH_REMATCH[3]}"
    elif [[ "$path_parts" =~ ^([^.]+)\.([^.]+)$ ]]; then
        # 2階層: worktree.base_dir
        section="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
    else
        # 1階層: name
        key="$path_parts"
    fi
    
    local current_section=""
    local current_subsection=""
    local found_value=""
    local in_literal_block=false
    local literal_content=""
    local literal_indent=0
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 複数行リテラルブロックの継続処理
        if [[ "$in_literal_block" == "true" ]]; then
            # 同レベル以上のキーが来たら終了
            if [[ "$line" =~ ^[[:space:]]{0,$literal_indent}[a-z0-9_-]+: ]]; then
                found_value="$literal_content"
                break
            fi
            
            # 空行やコメントは除外せず追加
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]]; then
                # インデント部分を削除して追加
                literal_content+="${line:$((literal_indent + 2))}"$'\n'
            else
                literal_content+=$'\n'
            fi
            continue
        fi
        
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # レベル1: トップレベルセクション (例: worktree:, workflows:)
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            continue
        fi
        
        # レベル1: トップレベルキー（値あり）
        if [[ -z "$section" && "$line" =~ ^([a-z0-9_-]+):[[:space:]]*(.*) ]]; then
            local line_key="${BASH_REMATCH[1]}"
            local line_value="${BASH_REMATCH[2]}"
            
            if [[ "$line_key" == "$key" && -n "$line_value" ]]; then
                # クォートを除去
                line_value="${line_value#\"}"
                line_value="${line_value%\"}"
                line_value="${line_value#\'}"
                line_value="${line_value%\'}"
                found_value="$line_value"
                break
            fi
            continue
        fi
        
        # レベル2: セクション内のサブセクション (例: workflows: の下の quick:)
        if [[ -n "$section" && "$current_section" == "$section" ]]; then
            # サブセクションの検出（常に実行）
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                current_subsection="${BASH_REMATCH[1]}"
                continue
            fi
            
            # レベル2: セクション内のキー（値あり、サブセクションなし）
            if [[ -z "$subsection" && "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]+(.*) ]]; then
                local line_key="${BASH_REMATCH[1]}"
                local line_value="${BASH_REMATCH[2]}"
                
                if [[ "$line_key" == "$key" && -n "$line_value" ]]; then
                    # クォートを除去
                    line_value="${line_value#\"}"
                    line_value="${line_value%\"}"
                    line_value="${line_value#\'}"
                    line_value="${line_value%\'}"
                    found_value="$line_value"
                    break
                fi
            fi
        fi
        
        # レベル3: サブセクション内のキー (例: workflows.quick.description)
        if [[ -n "$section" && -n "$subsection" && "$current_section" == "$section" && "$current_subsection" == "$subsection" ]]; then
            # リテラルブロック（複数行テキスト）の検出
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]*\|[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_literal_block=true
                    literal_indent=4
                    literal_content=""
                fi
                continue
            fi
            
            # レベル3: サブセクション内のキー（値あり）
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]+(.*) ]]; then
                local line_key="${BASH_REMATCH[1]}"
                local line_value="${BASH_REMATCH[2]}"
                
                if [[ "$line_key" == "$key" && -n "$line_value" ]]; then
                    # クォートを除去
                    line_value="${line_value#\"}"
                    line_value="${line_value%\"}"
                    line_value="${line_value#\'}"
                    line_value="${line_value%\'}"
                    found_value="$line_value"
                    break
                fi
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
    
    if [[ -n "$found_value" ]]; then
        # 末尾の改行を除去（リテラルブロックの場合）
        if [[ "$in_literal_block" == "true" ]]; then
            echo -n "$found_value"
        else
            echo "$found_value"
        fi
    else
        echo "$default"
    fi
}

# 簡易パーサーで配列を取得
_simple_yaml_get_array() {
    local file="$1"
    local path="$2"
    
    # パス階層数を検証（簡易パーサーは最大3階層まで対応）
    local path_parts="${path#.}"  # 先頭のドットを除去
    local depth
    depth=$(echo "$path_parts" | tr "." "\n" | wc -l | tr -d ' ')
    if [[ "$depth" -gt 3 ]]; then
        log_warn "Simple YAML parser only supports up to 3 levels of nesting: $path"
        log_warn "Install yq for full YAML support: brew install yq"
        return 0
    fi
    
    # パスを最大3階層に分解（path_partsは既に定義済み）
    local section=""
    local subsection=""
    local key=""
    
    if [[ "$path_parts" =~ ^([^.]+)\.([^.]+)\.([^.]+)$ ]]; then
        # 3階層: workflows.quick.steps
        section="${BASH_REMATCH[1]}"
        subsection="${BASH_REMATCH[2]}"
        key="${BASH_REMATCH[3]}"
    elif [[ "$path_parts" =~ ^([^.]+)\.([^.]+)$ ]]; then
        # 2階層: worktree.copy_files
        section="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
    else
        # 1階層: steps
        key="$path_parts"
    fi
    
    local current_section=""
    local current_subsection=""
    local in_target_array=false
    local array_indent=0
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # レベル1: トップレベルセクション
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            in_target_array=false
            continue
        fi
        
        # レベル2: セクション内のキー（サブセクションまたは配列）
        if [[ -n "$section" && -z "$subsection" && "$current_section" == "$section" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                # まず、ターゲットの配列キーかチェック
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                    array_indent=2
                else
                    # ターゲットでなければサブセクションとして扱う
                    current_subsection="$line_key"
                    in_target_array=false
                fi
                continue
            fi
            
            # 別のキー（値付き）が来たら配列終了
            if [[ "$line" =~ ^[[:space:]]{2}[a-z0-9_-]+:[[:space:]]+[^[:space:]] ]]; then
                in_target_array=false
                continue
            fi
        fi
        
        # レベル3: サブセクション内のキー（配列）
        if [[ -n "$section" && -n "$subsection" && "$current_section" == "$section" && "$current_subsection" == "$subsection" ]]; then
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                    array_indent=4
                else
                    in_target_array=false
                fi
                continue
            fi
            
            # 別のキー（値付き）が来たら配列終了
            if [[ "$line" =~ ^[[:space:]]{4}[a-z0-9_-]+:[[:space:]]+[^[:space:]] ]]; then
                in_target_array=false
                continue
            fi
        fi
        
        # トップレベルの配列キー検出（サブセクションなし）
        if [[ -z "$section" ]]; then
            if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                    array_indent=0
                else
                    in_target_array=false
                fi
                continue
            fi
        fi
        
        # 配列項目の検出（インデントレベルに応じて）
        if [[ "$in_target_array" == "true" ]]; then
            local expected_indent=$((array_indent + 2))
            if [[ "$line" =~ ^[[:space:]]{$expected_indent}-[[:space:]]+(.*) ]]; then
                local item="${BASH_REMATCH[1]}"
                # クォートを除去
                item="${item#\"}"
                item="${item%\"}"
                item="${item#\'}"
                item="${item%\'}"
                echo "$item"
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
}

# 簡易パーサーでパスの存在確認
_simple_yaml_exists() {
    local file="$1"
    local path="$2"
    
    # パス階層数を検証（簡易パーサーは最大3階層まで対応）
    local path_parts="${path#.}"  # 先頭のドットを除去
    local depth
    depth=$(echo "$path_parts" | tr "." "\n" | wc -l | tr -d ' ')
    if [[ "$depth" -gt 3 ]]; then
        log_warn "Simple YAML parser only supports up to 3 levels of nesting: $path"
        log_warn "Install yq for full YAML support: brew install yq"
        return 1
    fi
    
    # パスを最大3階層に分解（path_partsは既に定義済み）
    local section=""
    local subsection=""
    local key=""
    
    if [[ "$path_parts" =~ ^([^.]+)\.([^.]+)\.([^.]+)$ ]]; then
        # 3階層: workflows.quick.steps
        section="${BASH_REMATCH[1]}"
        subsection="${BASH_REMATCH[2]}"
        key="${BASH_REMATCH[3]}"
    elif [[ "$path_parts" =~ ^([^.]+)\.([^.]+)$ ]]; then
        # 2階層: worktree.base_dir
        section="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
    else
        # 1階層: workflow
        section="$path_parts"
        key=""
    fi
    
    local current_section=""
    local current_subsection=""
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # レベル1: トップレベルセクション
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            current_subsection=""
            # 1階層のみのパス (例: .workflows)
            if [[ -z "$subsection" && -z "$key" && "$current_section" == "$section" ]]; then
                return 0
            fi
            continue
        fi
        
        # レベル2: セクション内のサブセクションまたはキー
        if [[ -n "$section" && "$current_section" == "$section" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+): ]]; then
                local line_key="${BASH_REMATCH[1]}"
                
                # 2階層のパス (例: .workflows.quick)
                if [[ -z "$subsection" && -n "$key" && "$line_key" == "$key" ]]; then
                    return 0
                fi
                
                # サブセクションの開始
                if [[ -n "$subsection" && -z "$key" && "$line_key" == "$subsection" ]]; then
                    # .workflows.quick の確認（keyなし）
                    return 0
                fi
                
                if [[ -n "$subsection" && "$line_key" == "$subsection" ]]; then
                    current_subsection="$subsection"
                fi
            fi
        fi
        
        # レベル3: サブセクション内のキー
        if [[ -n "$section" && -n "$subsection" && -n "$key" && "$current_section" == "$section" && "$current_subsection" == "$subsection" ]]; then
            if [[ "$line" =~ ^[[:space:]]{4}([a-z0-9_-]+): ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    return 0
                fi
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
    
    return 1
}

# 簡易パーサーでキー一覧を取得
_simple_yaml_get_keys() {
    local file="$1"
    local path="$2"
    
    # パスからセクションを抽出（例: .workflows → workflows）
    local section="${path#.}"
    local current_section=""
    local in_target_section=false
    
    _yaml_ensure_cached "$file"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # セクション検出（workflows:）
        if [[ "$line" =~ ^([a-z0-9_-]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ "$current_section" == "$section" ]]; then
                in_target_section=true
            else
                in_target_section=false
            fi
            continue
        fi
        
        # セクション内のキー検出（2スペースインデント）
        if [[ "$in_target_section" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z0-9_-]+): ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[a-z0-9_-]+: ]]; then
                # インデントなし = 別セクション開始
                break
            fi
        fi
    done <<< "$_YAML_CACHE_CONTENT"
}
