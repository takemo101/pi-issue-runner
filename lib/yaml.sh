#!/usr/bin/env bash
# yaml.sh - 統一YAMLパーサー（yq + フォールバック）
#
# yqが利用可能な場合はyqを使用し、そうでない場合は
# 簡易パーサーにフォールバックする。

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

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
        yq -e "$path" "$file" &>/dev/null
    else
        _simple_yaml_exists "$file" "$path"
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
    
    local value
    # パスが存在するか確認してから値を取得（falseも正しく取得するため）
    if yq -e "$path != null" "$file" &>/dev/null; then
        value=$(yq -r "$path" "$file" 2>/dev/null || echo "")
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
    
    yq -r "${path}[]" "$file" 2>/dev/null || true
}

# ===================
# 簡易パーサー実装（フォールバック）
# ===================

# 簡易パーサーで値を取得
# パス形式: .section.key または .section.subsection.key
_simple_yaml_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    
    # パスをセクションとキーに分解
    # 例: .worktree.base_dir -> section=worktree, key=base_dir
    local path_parts
    path_parts="${path#.}"  # 先頭のドットを除去
    
    local section=""
    local key=""
    
    if [[ "$path_parts" == *"."* ]]; then
        section="${path_parts%%.*}"
        key="${path_parts#*.}"
    else
        key="$path_parts"
    fi
    
    local current_section=""
    local found_value=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # セクションの検出 (例: worktree:)
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # セクションなしのトップレベルキー
        if [[ -z "$section" && "$line" =~ ^([a-z_]+):[[:space:]]*(.*) ]]; then
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
        
        # セクション内のキー検出
        if [[ -n "$section" && "$current_section" == "$section" ]]; then
            if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*) ]]; then
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
    done < "$file"
    
    if [[ -n "$found_value" ]]; then
        echo "$found_value"
    else
        echo "$default"
    fi
}

# 簡易パーサーで配列を取得
_simple_yaml_get_array() {
    local file="$1"
    local path="$2"
    
    # パスをセクションとキーに分解
    local path_parts
    path_parts="${path#.}"  # 先頭のドットを除去
    
    local section=""
    local key=""
    
    if [[ "$path_parts" == *"."* ]]; then
        section="${path_parts%%.*}"
        key="${path_parts#*.}"
    else
        key="$path_parts"
    fi
    
    local current_section=""
    local in_target_array=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # セクションの検出
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            in_target_array=false
            continue
        fi
        
        # セクション内のキー検出
        if [[ -n "$section" && "$current_section" == "$section" ]]; then
            # キーの開始を検出（値が空 = 配列の開始）
            if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                else
                    in_target_array=false
                fi
                continue
            fi
            
            # 別のキー（値付き）が来たら配列終了
            if [[ "$line" =~ ^[[:space:]]+[a-z_]+:[[:space:]]+[^[:space:]] ]]; then
                in_target_array=false
                continue
            fi
        fi
        
        # トップレベルの配列キー検出
        if [[ -z "$section" ]]; then
            if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    in_target_array=true
                else
                    in_target_array=false
                fi
                continue
            fi
        fi
        
        # 配列項目の検出
        if [[ "$in_target_array" == "true" && "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            # クォートを除去
            item="${item#\"}"
            item="${item%\"}"
            item="${item#\'}"
            item="${item%\'}"
            echo "$item"
        fi
    done < "$file"
}

# 簡易パーサーでパスの存在確認
_simple_yaml_exists() {
    local file="$1"
    local path="$2"
    
    # パスをセクションに分解
    local path_parts
    path_parts="${path#.}"  # 先頭のドットを除去
    
    local section=""
    local key=""
    
    if [[ "$path_parts" == *"."* ]]; then
        section="${path_parts%%.*}"
        key="${path_parts#*.}"
    else
        section="$path_parts"
        key=""
    fi
    
    local current_section=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # セクションの検出
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            # キーが空の場合はセクションの存在のみ確認
            if [[ -z "$key" && "$current_section" == "$section" ]]; then
                return 0
            fi
            continue
        fi
        
        # セクション内のキー検出
        if [[ -n "$section" && "$current_section" == "$section" && -n "$key" ]]; then
            if [[ "$line" =~ ^[[:space:]]+([a-z_]+): ]]; then
                local line_key="${BASH_REMATCH[1]}"
                if [[ "$line_key" == "$key" ]]; then
                    return 0
                fi
            fi
        fi
    done < "$file"
    
    return 1
}
