#!/usr/bin/env bash
# priority.sh - Issue優先度計算ライブラリ

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_PRIORITY_SH_SOURCED:-}" ]]; then
    return 0
fi
_PRIORITY_SH_SOURCED="true"

_PRIORITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_PRIORITY_LIB_DIR/log.sh"
source "$_PRIORITY_LIB_DIR/github.sh"
source "$_PRIORITY_LIB_DIR/dependency.sh"
source "$_PRIORITY_LIB_DIR/status.sh"

# ラベルJSONから優先度スコアを取得
# 引数: labels_json - ラベルのJSON配列 (e.g., [{"name":"priority:high"},...])
# 出力: スコア (100, 50, 10)
get_priority_score_from_labels() {
    local labels_json="$1"
    
    check_jq || {
        echo "50"  # デフォルト
        return 0
    }
    
    # priority:* ラベルを検索
    local priority_label
    priority_label=$(echo "$labels_json" | jq -r '.[] | select(.name | startswith("priority:")) | .name' | head -1)
    
    case "$priority_label" in
        "priority:high")
            echo "100"
            ;;
        "priority:medium")
            echo "50"
            ;;
        "priority:low")
            echo "10"
            ;;
        *)
            echo "50"  # デフォルトはmedium相当
            ;;
    esac
}

# Issueの総合優先度スコアを計算
# 引数:
#   $1 - issue_number
#   $2 - layer (依存関係レイヤー)
#   $3 - labels_json (オプション、取得済みの場合)
# 出力: スコア (整数)
# 計算式: base_score - (layer * 10)
calculate_issue_priority() {
    local issue_number="$1"
    local layer="$2"
    local labels_json="${3:-}"
    
    # ラベル情報が提供されていない場合は取得
    if [[ -z "$labels_json" ]]; then
        local issue_info
        if ! issue_info=$(get_issue "$issue_number" 2>/dev/null); then
            log_warn "Could not get issue info for #$issue_number"
            echo "0"
            return 0
        fi
        labels_json=$(echo "$issue_info" | jq -r '.labels // []')
    fi
    
    local base_score
    base_score=$(get_priority_score_from_labels "$labels_json")
    
    # レイヤーペナルティを適用
    local layer_penalty=$((layer * 10))
    local final_score=$((base_score - layer_penalty))
    
    echo "$final_score"
}

# 複数IssueをJSON配列として取得し、優先度スコアを追加
# 引数: Issue番号の配列 (スペース区切り文字列)
# 出力: JSON配列 [{"number":N,"score":S,"layer":L,...},...]
# 注: この関数は依存関係レイヤーを計算してスコアを算出します
enrich_issues_with_priority() {
    # shellcheck disable=SC2206  # 意図的に単語分割を使用
    local -a issues_arr=($1)
    
    check_jq || {
        log_error "jq is required for priority calculation"
        return 1
    }
    
    # レイヤー計算
    local layers_output
    if ! layers_output=$(compute_layers "${issues_arr[@]}" 2>/dev/null); then
        log_warn "Could not compute layers, using layer 0 for all"
        layers_output=""
    fi
    
    # レイヤー情報を連想配列に格納
    declare -A issue_layers
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local layer_num issue_num
        layer_num=$(echo "$line" | cut -d' ' -f1)
        issue_num=$(echo "$line" | cut -d' ' -f2)
        issue_layers[$issue_num]=$layer_num
    done <<< "$layers_output"
    
    # 各Issueの情報を取得してJSON構築
    local result="["
    local first=true
    
    for issue_num in "${issues_arr[@]}"; do
        local issue_info title labels_json layer score
        
        # Issue情報を取得
        if ! issue_info=$(get_issue "$issue_num" 2>/dev/null); then
            log_warn "Skipping issue #$issue_num (could not retrieve info)"
            continue
        fi
        
        title=$(echo "$issue_info" | jq -r '.title // ""')
        labels_json=$(echo "$issue_info" | jq -r '.labels // []')
        layer=${issue_layers[$issue_num]:-0}
        score=$(calculate_issue_priority "$issue_num" "$layer" "$labels_json")
        
        # JSON追加
        if [[ "$first" == "false" ]]; then
            result="$result,"
        fi
        first=false
        
        # jqを使用して安全にJSON構築
        local issue_json
        issue_json=$(jq -n \
            --argjson number "$issue_num" \
            --arg title "$title" \
            --argjson score "$score" \
            --argjson layer "$layer" \
            --argjson labels "$labels_json" \
            '{number: $number, title: $title, score: $score, layer: $layer, labels: $labels}')
        
        result="$result$issue_json"
    done
    
    result="$result]"
    echo "$result"
}

# IssueのJSON配列を優先度スコアでソート
# 引数: JSON配列 (enrich_issues_with_priorityの出力形式)
# 出力: スコアの降順でソートされたJSON配列
# 同スコアの場合はIssue番号の昇順
sort_issues_by_priority() {
    local issues_json="$1"
    
    check_jq || {
        echo "$issues_json"
        return 0
    }
    
    # スコア降順、Issue番号昇順でソート
    echo "$issues_json" | jq 'sort_by(-(.score), .number)'
}

# ブロックされていないIssueをフィルタ
# 引数: Issue番号の配列 (スペース区切り文字列)
# 出力: フィルタ後のIssue番号 (スペース区切り)
filter_unblocked_issues() {
    local issues="$1"
    local result=""
    
    for issue in $issues; do
        # check_issue_blockedは 0=ブロックなし, 1=ブロックあり
        if check_issue_blocked "$issue" > /dev/null 2>&1; then
            result="$result $issue"
        fi
    done
    
    echo "${result# }"  # 先頭スペースを削除
}

# 実行中でないIssueをフィルタ
# 引数: Issue番号の配列 (スペース区切り文字列)
# 出力: フィルタ後のIssue番号 (スペース区切り)
filter_non_running_issues() {
    local issues="$1"
    
    # issuesが空の場合はそのまま返す
    if [[ -z "$issues" ]]; then
        echo ""
        return 0
    fi
    
    local result=""
    
    # 実行中のIssue一覧を取得
    local running_issues
    running_issues=$(list_issues_by_status "running" 2>/dev/null | tr '\n' ' ')
    
    # running_issuesが空の場合はすべて返す
    if [[ -z "$running_issues" ]]; then
        echo "$issues"
        return 0
    fi
    
    for issue in $issues; do
        # running_issuesに含まれていなければ追加
        # shellcheck disable=SC2076  # スペース区切りのリテラルマッチが意図
        if [[ ! " $running_issues " =~ " $issue " ]]; then
            result="$result $issue"
        fi
    done
    
    echo "${result# }"
}

# 指定ラベルを持つIssueをフィルタ
# 引数:
#   $1 - Issue番号の配列 (スペース区切り文字列)
#   $2 - ラベル名
# 出力: フィルタ後のIssue番号 (スペース区切り)
filter_by_label() {
    local issues="$1"
    local target_label="$2"
    local result=""
    
    check_jq || {
        log_warn "jq not available, label filter skipped"
        echo "$issues"
        return 0
    }
    
    for issue in $issues; do
        local issue_info labels_json
        if ! issue_info=$(get_issue "$issue" 2>/dev/null); then
            continue
        fi
        
        labels_json=$(echo "$issue_info" | jq -r '.labels // []')
        
        # ラベルが含まれているかチェック
        if echo "$labels_json" | jq -e --arg label "$target_label" '.[] | select(.name == $label)' > /dev/null 2>&1; then
            result="$result $issue"
        fi
    done
    
    echo "${result# }"
}

# 優先度情報を含む詳細説明を生成
# 引数: Issue情報のJSON (enrich_issues_with_priorityの要素)
# 出力: フォーマット済みテキスト
format_issue_details() {
    local issue_json="$1"
    local verbose="${2:-false}"
    
    check_jq || return 1
    
    local number title score layer labels_str priority_name
    number=$(echo "$issue_json" | jq -r '.number')
    title=$(echo "$issue_json" | jq -r '.title')
    score=$(echo "$issue_json" | jq -r '.score')
    layer=$(echo "$issue_json" | jq -r '.layer')
    
    # ラベルを文字列化
    labels_str=$(echo "$issue_json" | jq -r '.labels | map(.name) | join(", ")')
    [[ -z "$labels_str" ]] && labels_str="(none)"
    
    # priority:* ラベルから優先度名を取得
    priority_name=$(echo "$issue_json" | jq -r '.labels | map(.name) | map(select(startswith("priority:"))) | .[0] // "priority:medium"' | sed 's/priority://')
    
    echo "Title: $title"
    
    if [[ "$verbose" == "true" ]]; then
        echo "Priority: $priority_name (score: $score)"
        echo "Layer: $layer (dependency depth)"
        
        # ブロッカー情報
        local blockers
        if blockers=$(get_issue_blockers "$number" 2>/dev/null); then
            local blocker_count
            blocker_count=$(echo "$blockers" | jq 'length')
            if [[ "$blocker_count" -gt 0 ]]; then
                echo "Blockers: $blocker_count issue(s)"
            else
                echo "Blockers: None"
            fi
        else
            echo "Blockers: (could not check)"
        fi
        
        # ステータス
        local status
        status=$(get_status_value "$number" 2>/dev/null || echo "unknown")
        echo "Status: $status"
        
        echo "Labels: $labels_str"
        
        # スコア計算の詳細
        local base_score=$((score + layer * 10))
        echo ""
        echo "Calculation:"
        echo "- Base priority score: $base_score"
        echo "- Layer penalty: $((layer * 10)) ($layer * 10)"
        echo "- Final score: $score"
    else
        echo "Priority: $priority_name"
        
        # シンプルな理由説明
        local reason=""
        if [[ "$layer" -eq 0 ]]; then
            reason="No dependencies"
        else
            reason="$layer level(s) of dependencies"
        fi
        
        # ブロッカーチェック
        local blocker_status="no blockers"
        if ! check_issue_blocked "$number" > /dev/null 2>&1; then
            blocker_status="has blockers"
        fi
        
        echo "Reason: $reason, $blocker_status"
        
        # 依存関係情報（簡易版）
        if [[ "$layer" -gt 0 ]]; then
            echo "Dependencies: $layer level(s) deep"
        else
            echo "Dependencies: None (ready to start)"
        fi
    fi
}
