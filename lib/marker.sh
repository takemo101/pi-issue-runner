#!/usr/bin/env bash
# marker.sh - マーカー検出ユーティリティ

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_MARKER_SH_SOURCED:-}" ]]; then
    return 0
fi
_MARKER_SH_SOURCED="true"

# コードブロック外のマーカー数をカウント
# コードブロック内（前後1行に```がある）のマーカーは除外
# Usage: count_markers_outside_codeblock <output> <marker>
# Returns: コードブロック外のマーカー数
count_markers_outside_codeblock() {
    local output="$1"
    local marker="$2"
    local count=0
    
    # 出力を行番号付きで処理
    local line_numbers
    line_numbers=$(echo "$output" | grep -nE "^[[:space:]]*${marker}$" 2>/dev/null | cut -d: -f1) || true
    
    if [[ -z "$line_numbers" ]]; then
        echo "0"
        return
    fi
    
    # 各マーカー行について、前後1行にコードブロックマーカーがあるかチェック
    local total_lines
    total_lines=$(echo "$output" | wc -l)
    
    while IFS= read -r line_num; do
        [[ -z "$line_num" ]] && continue
        
        # 前後1行の範囲を計算
        local prev_line=$((line_num - 1))
        local next_line=$((line_num + 1))
        
        # 前の行と次の行を取得
        local prev_content=""
        local next_content=""
        
        if [[ $prev_line -ge 1 ]]; then
            prev_content=$(echo "$output" | sed -n "${prev_line}p") || prev_content=""
        fi
        
        if [[ $next_line -le $total_lines ]]; then
            next_content=$(echo "$output" | sed -n "${next_line}p") || next_content=""
        fi
        
        # マーカーは「前の行」と「次の行」の両方にコードブロックマーカーがある場合のみ除外
        # （つまり、```で囲まれている場合）
        local prev_has_fence=false
        local next_has_fence=false
        
        if echo "$prev_content" | grep -qF '```'; then
            prev_has_fence=true
        fi
        
        if echo "$next_content" | grep -qF '```'; then
            next_has_fence=true
        fi
        
        # 両方にフェンスがある場合のみコードブロック内と判定
        if [[ "$prev_has_fence" == "true" && "$next_has_fence" == "true" ]]; then
            continue  # Skip this marker
        fi
        
        # それ以外の場合はカウント
        count=$((count + 1))
    done <<< "$line_numbers"
    
    echo "$count"
}
