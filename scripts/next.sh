#!/usr/bin/env bash
# ============================================================================
# next.sh - Intelligent next task recommendation
#
# Intelligently recommends the next GitHub Issue to work on based on
# dependencies, priority, and blocker status. Considers dependency depth,
# priority labels, and blocking issues.
#
# Usage: ./scripts/next.sh [options]
#
# Options:
#   -n, --count <N>     Number of issues to recommend (default: 1)
#   -l, --label <name>  Filter by specific label
#   --json              Output in JSON format
#   --dry-run           Show only recommendations (don't show run command)
#   -v, --verbose       Show detailed reasoning
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success
#   1 - No candidates found
#   2 - GitHub API error
#   3 - Invalid arguments
#
# Examples:
#   ./scripts/next.sh
#   ./scripts/next.sh -n 3
#   ./scripts/next.sh -l feature
#   ./scripts/next.sh --json
#   ./scripts/next.sh -v
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/dependency.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/priority.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

次に実行すべきGitHub Issueをインテリジェントに提案します。
依存関係・優先度・ブロッカー状況を考慮して最適なIssueを選択します。

Options:
    -n, --count <N>     提案するIssue数（デフォルト: 1）
    -l, --label <name>  特定ラベルでフィルタ
    --json              JSON形式で出力
    --dry-run           提案のみ（実行コマンドを表示しない）
    -v, --verbose       詳細な判断理由を表示
    -h, --help          このヘルプを表示

Prioritization Logic:
    1. Blocker status    - OPENなブロッカーがないIssueを優先
    2. Dependency depth  - 依存が少ない（レイヤーが浅い）Issueを優先
    3. Priority labels   - priority:high > medium > low
    4. Issue number      - 同スコアなら番号が小さい方を優先

Examples:
    $(basename "$0")                    # 次の1件を提案
    $(basename "$0") -n 3               # 次の3件を提案
    $(basename "$0") -l feature         # featureラベル付きから提案
    $(basename "$0") --json             # JSON形式で出力
    $(basename "$0") -v                 # 詳細な判断理由を表示

Exit codes:
    0 - Success
    1 - No candidates found
    2 - GitHub API error
    3 - Invalid arguments
EOF
}

main() {
    local count=1
    local label_filter=""
    local json_output=false
    local dry_run=false
    local verbose=false
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--count)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires an argument"
                    usage >&2
                    exit 3
                fi
                count="$2"
                # 数値チェック
                if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
                    log_error "Count must be a positive integer"
                    exit 3
                fi
                shift 2
                ;;
            -l|--label)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires an argument"
                    usage >&2
                    exit 3
                fi
                label_filter="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                enable_verbose
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 3
                ;;
        esac
    done
    
    # 依存関係チェック
    check_dependencies || exit 2
    
    # 設定ファイル読み込み
    load_config
    
    # STEP 1: Open状態のIssueを取得
    log_debug "Fetching open issues..."
    local open_issues_json
    if ! open_issues_json=$(gh issue list --state open --limit 100 --json number,title,labels 2>/dev/null); then
        log_error "Failed to fetch open issues"
        exit 2
    fi
    
    # Issue番号を抽出
    local all_issues
    all_issues=$(echo "$open_issues_json" | jq -r '.[].number' | tr '\n' ' ')
    
    if [[ -z "$all_issues" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"recommended":[],"message":"No open issues found"}'
        else
            log_info "No open issues found."
        fi
        exit 1
    fi
    
    log_debug "Found $(echo "$all_issues" | wc -w | tr -d ' ') open issues"
    
    # STEP 2: 実行中のIssueを除外
    log_debug "Filtering out running issues..."
    local non_running_issues
    non_running_issues=$(filter_non_running_issues "$all_issues")
    
    if [[ -z "$non_running_issues" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"recommended":[],"message":"All issues are currently running"}'
        else
            log_info "All issues are currently running."
        fi
        exit 1
    fi
    
    log_debug "$(echo "$non_running_issues" | wc -w | tr -d ' ') non-running issues"
    
    # STEP 3: ブロックされていないIssueをフィルタ
    log_debug "Filtering out blocked issues..."
    local unblocked_issues
    unblocked_issues=$(filter_unblocked_issues "$non_running_issues")
    
    if [[ -z "$unblocked_issues" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"recommended":[],"message":"All non-running issues are blocked"}'
        else
            log_info "All non-running issues are blocked by dependencies."
        fi
        exit 1
    fi
    
    log_debug "$(echo "$unblocked_issues" | wc -w | tr -d ' ') unblocked issues"
    
    # STEP 4: ラベルフィルタ適用（オプション）
    local candidate_issues="$unblocked_issues"
    if [[ -n "$label_filter" ]]; then
        log_debug "Applying label filter: $label_filter"
        candidate_issues=$(filter_by_label "$unblocked_issues" "$label_filter")
        
        if [[ -z "$candidate_issues" ]]; then
            if [[ "$json_output" == "true" ]]; then
                echo "{\"recommended\":[],\"message\":\"No issues found with label: $label_filter\"}"
            else
                log_info "No issues found with label: $label_filter"
            fi
            exit 1
        fi
        
        log_debug "$(echo "$candidate_issues" | wc -w | tr -d ' ') issues after label filter"
    fi
    
    # STEP 5: 優先度情報を付与
    log_debug "Calculating priority scores..."
    local enriched_issues
    if ! enriched_issues=$(enrich_issues_with_priority "$candidate_issues"); then
        log_error "Failed to calculate priority scores"
        exit 2
    fi
    
    # STEP 6: 優先度でソート
    log_debug "Sorting by priority..."
    local sorted_issues
    sorted_issues=$(sort_issues_by_priority "$enriched_issues")
    
    # STEP 7: 上位N件を取得
    local top_issues
    top_issues=$(echo "$sorted_issues" | jq -c ".[:$count]")
    
    local top_count
    top_count=$(echo "$top_issues" | jq 'length')
    
    if [[ "$top_count" -eq 0 ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"recommended":[],"message":"No candidates available"}'
        else
            log_info "No candidates available."
        fi
        exit 1
    fi
    
    # STEP 8: 出力
    if [[ "$json_output" == "true" ]]; then
        # JSON出力
        echo "{\"recommended\":$top_issues}"
    else
        # 標準出力
        local idx=0
        while [[ $idx -lt $top_count ]]; do
            local issue_data
            issue_data=$(echo "$top_issues" | jq -c ".[$idx]")
            local issue_number
            issue_number=$(echo "$issue_data" | jq -r '.number')
            
            if [[ $idx -gt 0 ]]; then
                echo ""
                echo "---"
                echo ""
            fi
            
            if [[ "$count" -eq 1 ]]; then
                echo "🎯 Next recommended issue: #$issue_number"
            else
                echo "🎯 Recommended issue #$((idx + 1)): #$issue_number"
            fi
            echo ""
            
            # 詳細情報を表示
            format_issue_details "$issue_data" "$verbose"
            
            # 実行コマンド（--dry-run でない場合）
            if [[ "$dry_run" != "true" ]]; then
                echo ""
                echo "Run: scripts/run.sh $issue_number"
            fi
            
            idx=$((idx + 1))
        done
    fi
}

main "$@"
