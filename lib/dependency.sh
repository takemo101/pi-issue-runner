#!/usr/bin/env bash
# dependency.sh - 依存関係解析・レイヤー計算

set -euo pipefail

_DEPENDENCY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DEPENDENCY_LIB_DIR/log.sh"
source "$_DEPENDENCY_LIB_DIR/github.sh"

# Issueのブロッカー番号一覧を取得（スペース区切り）
# 引数: issue_number
# 出力: ブロッカー番号（スペース区切り、1行）
get_issue_blockers_numbers() {
    local issue_number="$1"
    
    local blockers_json
    if ! blockers_json="$(get_issue_blockers "$issue_number")"; then
        log_warn "Failed to get blockers for issue #$issue_number"
        echo ""
        return 0
    fi
    
    # OPENまたはCLOSEDのブロッカー番号を抽出（完了していないブロッカーは実行順序に影響）
    echo "$blockers_json" | jq -r '[.[].number] | map(tostring) | join(" ")' 2>/dev/null || echo ""
}

# 依存関係グラフを構築
# 引数: Issue番号の配列
# 出力: "依存元 依存先"形式の行（tsort互換）
build_dependency_graph() {
    local -a issues=("$@")
    
    # Issue番号をキーにした連想配列で依存関係を保持
    declare -A dependencies
    
    for issue in "${issues[@]}"; do
        local blockers
        blockers="$(get_issue_blockers_numbers "$issue")"
        dependencies[$issue]="$blockers"
    done
    
    # tsort形式で出力: "依存先 依存元"（依存元が先に処理される）
    # ブロッカー → Issue の順序で出力
    for issue in "${issues[@]}"; do
        local blockers="${dependencies[$issue]:-}"
        if [[ -n "$blockers" ]]; then
            for blocker in $blockers; do
                # 指定されたIssueリスト内にブロッカーが含まれる場合のみ出力
                if [[ " ${issues[*]} " == *" $blocker "* ]]; then
                    echo "$blocker $issue"
                fi
            done
        fi
        # 依存がないIssueも出力（孤立点として）
        if [[ -z "$blockers" ]]; then
            echo "$issue $issue"
        fi
    done
}

# 循環依存を検出
# 引数: Issue番号の配列
# 戻り値: 0=循環なし, 1=循環あり
# 循環ありの場合、循環しているIssue番号を出力
detect_cycles() {
    local -a issues=("$@")
    
    # 依存グラフを構築
    local graph
    graph="$(build_dependency_graph "${issues[@]}")"
    
    if [[ -z "$graph" ]]; then
        return 0
    fi
    
    # tsortを使用して循環検出（tsortは循環があると警告を出力）
    local tsort_result
    local tsort_exit=0
    
    # tsortが利用可能かチェック
    if command -v tsort &>/dev/null; then
        tsort_result="$(echo "$graph" | tsort 2>&1)" || tsort_exit=$?
        
        # tsortが循環を検出した場合
        if [[ $tsort_exit -ne 0 ]] || [[ "$tsort_result" == *"cycle"* ]]; then
            # 循環しているノードを特定
            _detect_cycles_manual "${issues[@]}"
            return 1
        fi
    else
        # tsortがない場合は手動で循環検出
        if ! _detect_cycles_manual "${issues[@]}"; then
            return 1
        fi
    fi
    
    return 0
}

# 手動での循環検出（DFSベース）
# 引数: Issue番号の配列
# 戻り値: 0=循環なし, 1=循環あり
_detect_cycles_manual() {
    local -a issues=("$@")
    declare -A graph visited rec_stack
    
    # グラフ構築（隣接リスト）
    for issue in "${issues[@]}"; do
        local blockers
        blockers="$(get_issue_blockers_numbers "$issue")"
        graph[$issue]="$blockers"
        # shellcheck disable=SC2034
        visited[$issue]=false
        # shellcheck disable=SC2034
        rec_stack[$issue]=false
    done
    
    # DFSで循環検出
    for issue in "${issues[@]}"; do
        if [[ "${visited[$issue]}" == "false" ]]; then
            if _dfs_check_cycle "$issue" graph visited rec_stack ""; then
                return 1
            fi
        fi
    done
    
    return 0
}

# DFSでの循環検出ヘルパー
# 引数: node, graph_ref, visited_ref, rec_stack_ref, path
# 戻り値: 0=循環なし, 1=循環あり（見つかったら即返却）
_dfs_check_cycle() {
    local node="$1"
    local -n graph_ref="$2"
    local -n visited_ref="$3"
    local -n rec_stack_ref="$4"
    local path="${5:-}"
    
    visited_ref[node]=true
    rec_stack_ref[node]=true
    path="$path $node"
    
    local neighbors="${graph_ref[$node]:-}"
    for neighbor in $neighbors; do
        if [[ "${visited_ref[$neighbor]:-false}" == "false" ]]; then
            if _dfs_check_cycle "$neighbor" graph_ref visited_ref rec_stack_ref "$path"; then
                return 1
            fi
        elif [[ "${rec_stack_ref[$neighbor]}" == "true" ]]; then
            # 循環検出
            log_error "Cycle detected involving issue #$neighbor"
            echo "Cycle: $path $neighbor"
            return 1
        fi
    done
    
    rec_stack_ref[node]=false
    return 0
}

# レイヤー計算（深さベース）
# 引数: Issue番号の配列
# 出力: "深さ Issue番号"形式（深さ順にソート済み）
compute_layers() {
    local -a issues=("$@")
    declare -A depth blockers_map
    
    # 初期化
    for issue in "${issues[@]}"; do
        depth[$issue]=0
        local blockers
        blockers="$(get_issue_blockers_numbers "$issue")"
        # 指定リスト内のブロッカーのみ保持
        local filtered_blockers=""
        for blocker in $blockers; do
            if [[ " ${issues[*]} " == *" $blocker "* ]]; then
                filtered_blockers="$filtered_blockers $blocker"
            fi
        done
        blockers_map[$issue]="${filtered_blockers# }"
    done
    
    # 深さ計算（反復法）
    local changed=true
    local max_iterations=${#issues[@]}
    local iteration=0
    
    while [[ "$changed" == "true" && $iteration -lt $max_iterations ]]; do
        changed=false
        for issue in "${issues[@]}"; do
            local blockers="${blockers_map[$issue]:-}"
            for blocker in $blockers; do
                if [[ -n "${depth[$blocker]:-}" ]]; then
                    local new_depth=$((depth[$blocker] + 1))
                    if [[ $new_depth -gt ${depth[$issue]} ]]; then
                        depth[$issue]=$new_depth
                        changed=true
                    fi
                fi
            done
        done
        ((iteration++))
    done
    
    # 深さ順に出力
    for issue in "${issues[@]}"; do
        echo "${depth[$issue]} $issue"
    done | sort -n
}

# レイヤー情報をグループ化して出力
# 入力: compute_layersの出力（パイプで渡す）
# 出力: "Layer N: issue1 issue2 ..."形式
group_layers() {
    local current_layer=-1
    local layer_issues=""
    
    while IFS= read -r line; do
        local layer_num issue_num
        layer_num="$(echo "$line" | cut -d' ' -f1)"
        issue_num="$(echo "$line" | cut -d' ' -f2)"
        
        if [[ "$layer_num" != "$current_layer" ]]; then
            # 前のレイヤーを出力
            if [[ $current_layer -ge 0 && -n "$layer_issues" ]]; then
                echo "Layer $current_layer: ${layer_issues# }"
            fi
            current_layer=$layer_num
            layer_issues=""
        fi
        
        layer_issues="$layer_issues #$issue_num"
    done
    
    # 最後のレイヤーを出力
    if [[ $current_layer -ge 0 && -n "$layer_issues" ]]; then
        echo "Layer $current_layer: ${layer_issues# }"
    fi
}

# 実行計画を表示
# 引数: Issue番号の配列
# 出力: フォーマット済み実行計画
show_execution_plan() {
    local -a issues=("$@")
    
    log_info "Execution plan:"
    
    local layers_output
    layers_output="$(compute_layers "${issues[@]}")"
    
    local current_layer=-1
    local layer_issues=""
    
    while IFS= read -r line; do
        local layer_num issue_num
        layer_num="$(echo "$line" | cut -d' ' -f1)"
        issue_num="$(echo "$line" | cut -d' ' -f2)"
        
        if [[ "$layer_num" != "$current_layer" ]]; then
            if [[ $current_layer -ge 0 && -n "$layer_issues" ]]; then
                log_info "  Layer $current_layer: $layer_issues"
            fi
            current_layer=$layer_num
            layer_issues="#$issue_num"
        else
            layer_issues="$layer_issues, #$issue_num"
        fi
    done <<< "$layers_output"
    
    if [[ $current_layer -ge 0 && -n "$layer_issues" ]]; then
        log_info "  Layer $current_layer: $layer_issues"
    fi
}

# 指定レイヤーのIssue一覧を取得
# 引数: レイヤー番号, compute_layersの出力（パイプまたはhere-stringで渡す）
# 出力: Issue番号（1行に1つ）
get_issues_in_layer() {
    local target_layer="$1"
    local layers_data="${2:-}"
    
    # データがパイプから渡された場合
    if [[ -z "$layers_data" ]]; then
        layers_data="$(cat)"
    fi
    
    echo "$layers_data" | while IFS= read -r line; do
        local layer_num issue_num
        layer_num="$(echo "$line" | cut -d' ' -f1)"
        issue_num="$(echo "$line" | cut -d' ' -f2)"
        
        if [[ "$layer_num" == "$target_layer" ]]; then
            echo "$issue_num"
        fi
    done
}

# 最大レイヤー番号を取得
# 入力: compute_layersの出力（パイプで渡す）
# 出力: 最大レイヤー番号（0始まり）
get_max_layer() {
    local max_layer=-1
    
    while IFS= read -r line; do
        local layer_num
        layer_num="$(echo "$line" | cut -d' ' -f1)"
        if [[ "$layer_num" -gt "$max_layer" ]]; then
            max_layer=$layer_num
        fi
    done
    
    echo "$max_layer"
}
