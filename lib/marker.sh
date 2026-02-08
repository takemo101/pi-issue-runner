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
