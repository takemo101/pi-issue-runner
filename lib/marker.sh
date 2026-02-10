#!/usr/bin/env bash
# marker.sh - マーカー検出ユーティリティ

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_MARKER_SH_SOURCED:-}" ]]; then
    return 0
fi
_MARKER_SH_SOURCED="true"

# コードブロック外のマーカー数をカウント
# コードブロック内のマーカーは除外（フェンス状態を追跡）
# Usage: count_markers_outside_codeblock <output> <marker>
# Returns: コードブロック外のマーカー数
count_markers_outside_codeblock() {
    local output="$1"
    local marker="$2"
    local count=0
    local in_codeblock=false
    local line_num=0
    
    # 行を順にスキャンし、コードブロックの開始/終了を追跡
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # コードブロックフェンスの検出（行頭の```）
        if [[ "$line" =~ ^[[:space:]]*\`\`\` ]]; then
            if [[ "$in_codeblock" == "false" ]]; then
                in_codeblock=true
            else
                in_codeblock=false
            fi
            continue
        fi
        
        # マーカー行の検出（前後の空白を除去してから完全一致を確認）
        # 正規表現ではなくglobパターンマッチを使用（正規表現メタ文字のエスケープ不要）
        local trimmed_line
        trimmed_line="${line#"${line%%[![:space:]]*}"}"  # 先頭の空白を除去
        trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"  # 末尾の空白を除去
        if [[ "$trimmed_line" == "$marker" ]]; then
            # コードブロック外の場合のみカウント
            if [[ "$in_codeblock" == "false" ]]; then
                count=$((count + 1))
            fi
        fi
    done <<< "$output"
    
    echo "$count"
}

# 複数マーカーのいずれかにマッチするコードブロック外の出現数を合計カウント
# Usage: count_any_markers_outside_codeblock <output> <marker1> [marker2] [marker3] ...
# Returns: コードブロック外のマーカー合計数
count_any_markers_outside_codeblock() {
    local output="$1"
    shift
    local markers=("$@")
    local total=0
    
    for marker in "${markers[@]}"; do
        local count
        count=$(count_markers_outside_codeblock "$output" "$marker")
        total=$((total + count))
    done
    
    echo "$total"
}

# ANSI エスケープシーケンスを除去するフィルタ
# Usage: echo "$text" | strip_ansi
#    or: strip_ansi < file
strip_ansi() {
    perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g; s/\r//g'
}

# ファイル内のマーカー行数を grep で高速カウント
# Usage: grep_marker_count_in_file <file> <marker1> [marker2] ...
# Returns: total count of lines matching any marker (0 if file doesn't exist)
grep_marker_count_in_file() {
    local file="$1"
    shift
    local total=0

    if [[ ! -f "$file" ]]; then
        echo 0
        return
    fi

    for m in "$@"; do
        local c
        c=$(grep -cF "$m" "$file" 2>/dev/null) || c=0
        total=$((total + c))
    done
    echo "$total"
}

# マーカーがコードブロック外にあるか検証（ファイルまたはテキスト対応）
# ファイルモードでは grep -B15 -A15 でマーカー周辺30行のみを抽出して検証する（高速）
# Usage: verify_marker_outside_codeblock <file_or_text> <marker> [is_file]
# Returns: 0 if at least one marker is outside a code block, 1 otherwise
verify_marker_outside_codeblock() {
    local source="$1"
    local marker="$2"
    local is_file="${3:-false}"

    local text
    if [[ "$is_file" == "true" ]]; then
        # ファイルからANSI除去→マーカー周辺30行を抽出して検証
        text=$(strip_ansi < "$source" | grep -B 15 -A 15 -F "$marker" 2>/dev/null) || text=""
    else
        text=$(echo "$source" | strip_ansi)
    fi

    if [[ -z "$text" ]]; then
        return 1
    fi

    local count
    count=$(count_markers_outside_codeblock "$text" "$marker")
    [[ "$count" -gt 0 ]]
}
