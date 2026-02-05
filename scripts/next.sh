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

# Handle --help early (before main, to avoid eval issues)
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
Usage: next.sh [options]

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
    next.sh                    # 次の1件を提案
    next.sh -n 3               # 次の3件を提案
    next.sh -l feature         # featureラベル付きから提案
    next.sh --json             # JSON形式で出力
    next.sh -v                 # 詳細な判断理由を表示

Exit codes:
    0 - Success
    1 - No candidates found
    2 - GitHub API error
    3 - Invalid arguments
EOF
        exit 0
    fi
done

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

# ============================================================================
# Subfunction: parse_next_arguments
# Purpose: Parse command-line arguments
# Output: Shell variable assignments (eval-able)
# Note: Does not handle --help/-h (handled in main before calling this)
# ============================================================================
parse_next_arguments() {
    local count=1
    local label_filter=""
    local json_output=false
    local dry_run=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--count)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires an argument"
                    usage >&2
                    exit 3
                fi
                count="$2"
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
                # Should not reach here (handled before main)
                usage >&2
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 3
                ;;
        esac
    done
    
    echo "local count=$count"
    echo "local label_filter='$label_filter'"
    echo "local json_output=$json_output"
    echo "local dry_run=$dry_run"
    echo "local verbose=$verbose"
}

# ============================================================================
# Subfunction: fetch_and_filter_issues
# Purpose: Fetch open issues and filter by various criteria
# Arguments: $1=label_filter, $2=json_output
# Output: Candidate issue numbers (space-separated)
# ============================================================================
fetch_and_filter_issues() {
    local label_filter="$1"
    local json_output="$2"
    
    check_dependencies || exit 2
    load_config
    
    # Fetch open issues
    log_debug "Fetching open issues..."
    local open_issues_json
    if ! open_issues_json=$(gh issue list --state open --limit 100 --json number,title,labels 2>/dev/null); then
        log_error "Failed to fetch open issues"
        exit 2
    fi
    
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
    
    # Filter running issues
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
    
    # Filter blocked issues
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
    
    # Apply label filter if specified
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
    
    echo "$candidate_issues"
}

# ============================================================================
# Subfunction: enrich_and_sort_issues
# Purpose: Add priority scores and sort issues
# Arguments: $1=candidate_issues, $2=count
# Output: JSON array of top N issues
# ============================================================================
enrich_and_sort_issues() {
    local candidate_issues="$1"
    local count="$2"
    
    log_debug "Calculating priority scores..."
    local enriched_issues
    if ! enriched_issues=$(enrich_issues_with_priority "$candidate_issues"); then
        log_error "Failed to calculate priority scores"
        exit 2
    fi
    
    log_debug "Sorting by priority..."
    local sorted_issues
    sorted_issues=$(sort_issues_by_priority "$enriched_issues")
    
    local top_issues
    top_issues=$(echo "$sorted_issues" | jq -c ".[:$count]")
    
    echo "$top_issues"
}

# ============================================================================
# Subfunction: display_recommendations
# Purpose: Display recommended issues
# Arguments: $1=top_issues (JSON), $2=count, $3=json_output, $4=dry_run, $5=verbose
# ============================================================================
display_recommendations() {
    local top_issues="$1"
    local count="$2"
    local json_output="$3"
    local dry_run="$4"
    local verbose="$5"
    
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
    
    if [[ "$json_output" == "true" ]]; then
        echo "{\"recommended\":$top_issues}"
    else
        local idx=0
        while [[ $idx -lt $top_count ]]; do
            local issue_data
            issue_data=$(echo "$top_issues" | jq -c ".[$idx]")
            local issue_number
            issue_number=$(echo "$issue_data" | jq -r '.number')
            
            [[ $idx -gt 0 ]] && echo -e "\n---\n"
            
            if [[ "$count" -eq 1 ]]; then
                echo "🎯 Next recommended issue: #$issue_number"
            else
                echo "🎯 Recommended issue #$((idx + 1)): #$issue_number"
            fi
            echo ""
            
            format_issue_details "$issue_data" "$verbose"
            
            if [[ "$dry_run" != "true" ]]; then
                echo ""
                echo "Run: scripts/run.sh $issue_number"
            fi
            
            idx=$((idx + 1))
        done
    fi
}

# ============================================================================
# Main function
# Purpose: Orchestrate next task recommendation
# ============================================================================
main() {
    # Parse arguments
    eval "$(parse_next_arguments "$@")"
    
    # Fetch and filter issues
    local candidate_issues
    candidate_issues="$(fetch_and_filter_issues "$label_filter" "$json_output")"
    
    # Enrich and sort issues
    local top_issues
    top_issues="$(enrich_and_sort_issues "$candidate_issues" "$count")"
    
    # Display recommendations
    display_recommendations "$top_issues" "$count" "$json_output" "$dry_run" "$verbose"
}

main "$@"
