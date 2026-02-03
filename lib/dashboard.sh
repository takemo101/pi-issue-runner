#!/usr/bin/env bash
# dashboard.sh - ダッシュボード表示ロジック

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

_DASHBOARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bash 4.0以上を要求（連想配列のサポート）
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "[ERROR] Bash 4.0 or higher is required (current: ${BASH_VERSION})" >&2
    echo "[INFO] Install: brew install bash (macOS)" >&2
    # sourceされている場合はreturn、スクリプトとして実行されている場合はexit
    # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
fi

# 依存ライブラリの読み込み
if ! declare -f log_debug > /dev/null 2>&1; then
    source "$_DASHBOARD_LIB_DIR/log.sh"
fi

if ! declare -f get_config > /dev/null 2>&1; then
    source "$_DASHBOARD_LIB_DIR/config.sh"
fi

if ! declare -f get_issue > /dev/null 2>&1; then
    source "$_DASHBOARD_LIB_DIR/github.sh"
fi

if ! declare -f list_all_statuses > /dev/null 2>&1; then
    source "$_DASHBOARD_LIB_DIR/status.sh"
fi

if ! declare -f list_sessions > /dev/null 2>&1; then
    source "$_DASHBOARD_LIB_DIR/tmux.sh"
fi

# ====================
# Box Drawing Functions
# ====================

# ボックスの上部を描画
draw_box_top() {
    local width="${1:-64}"
    printf "╔"
    printf '═%.0s' $(seq 1 "$width")
    printf "╗\n"
}

# ボックスのラインを描画
draw_box_line() {
    local text="$1"
    local width="${2:-64}"
    # ANSIエスケープシーケンスを除いた文字数を計算
    local text_length=${#text}
    # カラーコードがある場合は考慮（簡易版）
    if [[ "$text" =~ \033 ]]; then
        # カラーコード分を引く（概算）
        text_length=$((text_length - $(echo "$text" | grep -o $'\033\[[0-9;]*m' | wc -l | tr -d ' ') * 6))
    fi
    local padding=$((width - text_length))
    printf "║ %s" "$text"
    printf ' %.0s' $(seq 1 "$padding")
    printf "║\n"
}

# ボックスの区切り線を描画
draw_box_separator() {
    local width="${1:-64}"
    printf "╠"
    printf '═%.0s' $(seq 1 "$width")
    printf "╣\n"
}

# ボックスの下部を描画
draw_box_bottom() {
    local width="${1:-64}"
    printf "╚"
    printf '═%.0s' $(seq 1 "$width")
    printf "╝\n"
}

# ====================
# Data Collection Functions
# ====================

# GitHub Issuesを取得（open状態）
collect_github_issues() {
    local limit="${1:-50}"
    
    check_gh_cli 2>/dev/null || {
        log_warn "GitHub CLI not available, skipping issue collection"
        echo "[]"
        return 1
    }
    
    gh issue list --state open --limit "$limit" \
        --json number,title,labels,createdAt 2>/dev/null || echo "[]"
}

# 今週クローズされたIssuesを取得
collect_closed_issues_this_week() {
    check_gh_cli 2>/dev/null || {
        echo "[]"
        return 1
    }
    
    # 7日前の日付を取得（macOS/Linux互換）
    local week_ago
    if date -v-7d +%Y-%m-%d &>/dev/null; then
        # macOS
        week_ago=$(date -v-7d +%Y-%m-%d)
    else
        # Linux
        week_ago=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -d '-7 days' +%Y-%m-%d)
    fi
    
    gh issue list --state closed --limit 100 \
        --json number,closedAt 2>/dev/null \
        | jq -r --arg start "${week_ago}T00:00:00Z" \
            '[.[] | select(.closedAt >= $start)]' 2>/dev/null || echo "[]"
}

# ローカルステータスを全て取得
collect_local_statuses() {
    # タブ区切りで issue_number<TAB>status を返す
    list_all_statuses 2>/dev/null || echo ""
}

# tmuxセッション情報を取得
collect_session_info() {
    list_sessions 2>/dev/null || echo ""
}

# ====================
# Data Categorization Functions
# ====================

# グローバル連想配列（Bash 3.x互換のため関数外で宣言）
declare -A CATEGORIZED_ISSUES

# Issueを4つのカテゴリに分類
# 入力: GitHub Issues JSON配列
# 出力: 連想配列（カテゴリ名 -> Issue番号のスペース区切り文字列）
categorize_issues() {
    local issues_json="$1"
    
    # 初期化
    CATEGORIZED_ISSUES[in_progress]=""
    CATEGORIZED_ISSUES[blocked]=""
    CATEGORIZED_ISSUES[ready]=""
    CATEGORIZED_ISSUES[completed]=""
    
    # ローカルステータスを取得
    local statuses
    statuses="$(collect_local_statuses)"
    
    # 各Issueを分類
    local issue_count
    issue_count=$(echo "$issues_json" | jq 'length' 2>/dev/null)
    # Ensure issue_count is a valid number
    if [[ -z "$issue_count" || "$issue_count" == "null" || "$issue_count" == "[]" ]]; then
        issue_count=0
    fi
    
    for ((i=0; i<issue_count; i++)); do
        local issue_num title
        issue_num=$(echo "$issues_json" | jq -r ".[$i].number" 2>/dev/null)
        [[ -z "$issue_num" ]] && continue
        
        # ローカルステータスを確認
        local status
        status=$(echo "$statuses" | grep "^${issue_num}[[:space:]]" | cut -f2 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "running" ]]; then
            # IN PROGRESS
            CATEGORIZED_ISSUES[in_progress]+="$issue_num "
        else
            # BLOCKEDかREADYかを判定
            if check_issue_blocked "$issue_num" >/dev/null 2>&1; then
                # BLOCKED
                CATEGORIZED_ISSUES[blocked]+="$issue_num "
            else
                # READY
                CATEGORIZED_ISSUES[ready]+="$issue_num "
            fi
        fi
    done
    
    # 今週クローズされたIssueを追加
    local closed_issues
    closed_issues="$(collect_closed_issues_this_week)"
    local closed_count
    closed_count=$(echo "$closed_issues" | jq 'length' 2>/dev/null)
    # Ensure closed_count is a valid number
    if [[ -z "$closed_count" || "$closed_count" == "null" || "$closed_count" == "[]" ]]; then
        closed_count=0
    fi
    
    for ((i=0; i<closed_count; i++)); do
        local issue_num
        issue_num=$(echo "$closed_issues" | jq -r ".[$i].number" 2>/dev/null)
        [[ -z "$issue_num" ]] && continue
        CATEGORIZED_ISSUES[completed]+="$issue_num "
    done
}

# ====================
# Display Functions
# ====================

# サマリーセクションを描画
draw_summary_section() {
    local width="${1:-60}"
    
    # 各カテゴリのカウント
    local in_progress_count blocked_count ready_count completed_count
    in_progress_count=$(echo "${CATEGORIZED_ISSUES[in_progress]}" | wc -w | tr -d ' ')
    blocked_count=$(echo "${CATEGORIZED_ISSUES[blocked]}" | wc -w | tr -d ' ')
    ready_count=$(echo "${CATEGORIZED_ISSUES[ready]}" | wc -w | tr -d ' ')
    completed_count=$(echo "${CATEGORIZED_ISSUES[completed]}" | wc -w | tr -d ' ')
    
    draw_box_line "SUMMARY" "$width"
    draw_box_line "  In Progress:  ${in_progress_count} issues" "$width"
    draw_box_line "  Blocked:      ${blocked_count} issues" "$width"
    draw_box_line "  Ready:        ${ready_count} issues" "$width"
    draw_box_line "  Completed:    ${completed_count} issues (this week)" "$width"
}

# IN PROGRESSセクションを描画
draw_in_progress_section() {
    local width="${1:-60}"
    local verbose="${2:-false}"
    
    local issues="${CATEGORIZED_ISSUES[in_progress]}"
    local count
    count=$(echo "$issues" | wc -w | tr -d ' ')
    
    draw_box_separator "$width"
    draw_box_line "IN PROGRESS ($count)" "$width"
    
    if [[ "$count" -eq 0 ]]; then
        draw_box_line "  No issues in progress" "$width"
        return 0
    fi
    
    for issue_num in $issues; do
        local title session
        title="$(get_issue_title "$issue_num" 2>/dev/null || echo "Issue #$issue_num")"
        session="$(generate_session_name "$issue_num")"
        
        # タイトルを短縮（最大40文字）
        if [[ ${#title} -gt 40 ]]; then
            title="${title:0:37}..."
        fi
        
        # セッションが実行中か確認
        local session_status="[stopped]"
        if session_exists "$session" 2>/dev/null; then
            session_status="[running]"
        fi
        
        local line
        line=$(printf "  #%-4s %-40s %s" "$issue_num" "$title" "$session_status")
        draw_box_line "$line" "$width"
        
        # verbose モードでセッション名も表示
        if [[ "$verbose" == "true" ]]; then
            draw_box_line "         Session: $session" "$width"
        fi
    done
}

# BLOCKEDセクションを描画
draw_blocked_section() {
    local width="${1:-60}"
    local max_items="${2:-5}"
    
    local issues="${CATEGORIZED_ISSUES[blocked]}"
    local count
    count=$(echo "$issues" | wc -w | tr -d ' ')
    
    draw_box_separator "$width"
    draw_box_line "BLOCKED ($count)" "$width"
    
    if [[ "$count" -eq 0 ]]; then
        draw_box_line "  No blocked issues" "$width"
        return 0
    fi
    
    local displayed=0
    for issue_num in $issues; do
        [[ "$displayed" -ge "$max_items" ]] && break
        
        local title
        title="$(get_issue_title "$issue_num" 2>/dev/null || echo "Issue #$issue_num")"
        
        # ブロッカー情報を取得
        local blockers_json
        blockers_json="$(get_issue_blockers "$issue_num" 2>/dev/null || echo '[]')"
        
        # OPEN状態のブロッカーのみ抽出
        local open_blockers
        open_blockers=$(echo "$blockers_json" | jq -r '[.[] | select(.state == "OPEN") | .number] | join(", ")' 2>/dev/null || echo "")
        
        # タイトルを短縮
        if [[ ${#title} -gt 35 ]]; then
            title="${title:0:32}..."
        fi
        
        local line
        if [[ -n "$open_blockers" ]]; then
            line=$(printf "  #%-4s %-35s Blocked by: %s" "$issue_num" "$title" "$open_blockers")
        else
            line=$(printf "  #%-4s %-35s Blocked" "$issue_num" "$title")
        fi
        draw_box_line "$line" "$width"
        
        displayed=$((displayed + 1))
    done
    
    # 表示しきれなかった分があれば表示
    if [[ "$count" -gt "$max_items" ]]; then
        local remaining=$((count - max_items))
        draw_box_line "  ... and $remaining more" "$width"
    fi
}

# READYセクションを描画
draw_ready_section() {
    local width="${1:-60}"
    local max_items="${2:-5}"
    
    local issues="${CATEGORIZED_ISSUES[ready]}"
    local count
    count=$(echo "$issues" | wc -w | tr -d ' ')
    
    draw_box_separator "$width"
    draw_box_line "READY ($count)" "$width"
    
    if [[ "$count" -eq 0 ]]; then
        draw_box_line "  No ready issues" "$width"
        return 0
    fi
    
    local displayed=0
    for issue_num in $issues; do
        [[ "$displayed" -ge "$max_items" ]] && break
        
        local title
        title="$(get_issue_title "$issue_num" 2>/dev/null || echo "Issue #$issue_num")"
        
        # タイトルを短縮
        if [[ ${#title} -gt 50 ]]; then
            title="${title:0:47}..."
        fi
        
        local line
        line=$(printf "  #%-4s %s" "$issue_num" "$title")
        draw_box_line "$line" "$width"
        
        displayed=$((displayed + 1))
    done
    
    # 表示しきれなかった分があれば表示
    if [[ "$count" -gt "$max_items" ]]; then
        local remaining=$((count - max_items))
        draw_box_line "  ... and $remaining more" "$width"
    fi
}

# ====================
# Main Dashboard Functions
# ====================

# ダッシュボード全体を描画
draw_dashboard() {
    local width="${1:-60}"
    local compact="${2:-false}"
    local section="${3:-all}"
    local verbose="${4:-false}"
    
    # データ収集と分類
    local issues_json
    issues_json="$(collect_github_issues)"
    categorize_issues "$issues_json"
    
    # ヘッダー
    draw_box_top "$width"
    draw_box_line "Pi Issue Runner Dashboard" "$width"
    draw_box_separator "$width"
    
    # リポジトリ情報
    local repo
    repo="$(get_repo_info 2>/dev/null || echo "unknown")"
    draw_box_line "Repository: $repo" "$width"
    
    # 更新時刻
    local updated
    updated="$(date '+%Y-%m-%d %H:%M:%S')"
    draw_box_line "Updated: $updated" "$width"
    
    draw_box_separator "$width"
    
    # セクション表示
    if [[ "$section" == "all" || "$section" == "summary" ]]; then
        draw_summary_section "$width"
    fi
    
    if [[ "$compact" == "false" ]]; then
        if [[ "$section" == "all" || "$section" == "progress" ]]; then
            draw_in_progress_section "$width" "$verbose"
        fi
        
        if [[ "$section" == "all" || "$section" == "blocked" ]]; then
            draw_blocked_section "$width"
        fi
        
        if [[ "$section" == "all" || "$section" == "ready" ]]; then
            draw_ready_section "$width"
        fi
    fi
    
    # フッター
    draw_box_bottom "$width"
}

# JSON形式で出力
output_json() {
    # データ収集と分類
    local issues_json
    issues_json="$(collect_github_issues)"
    categorize_issues "$issues_json"
    
    # リポジトリ情報
    local repo updated
    repo="$(get_repo_info 2>/dev/null || echo "unknown")"
    updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    
    # 各カテゴリのカウント
    local in_progress_count blocked_count ready_count completed_count
    in_progress_count=$(echo "${CATEGORIZED_ISSUES[in_progress]}" | wc -w | tr -d ' ')
    blocked_count=$(echo "${CATEGORIZED_ISSUES[blocked]}" | wc -w | tr -d ' ')
    ready_count=$(echo "${CATEGORIZED_ISSUES[ready]}" | wc -w | tr -d ' ')
    completed_count=$(echo "${CATEGORIZED_ISSUES[completed]}" | wc -w | tr -d ' ')
    
    # JSON配列の構築
    local in_progress_array blocked_array ready_array completed_array
    in_progress_array=$(echo "${CATEGORIZED_ISSUES[in_progress]}" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s 'map(tonumber)' 2>/dev/null || echo "[]")
    blocked_array=$(echo "${CATEGORIZED_ISSUES[blocked]}" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s 'map(tonumber)' 2>/dev/null || echo "[]")
    ready_array=$(echo "${CATEGORIZED_ISSUES[ready]}" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s 'map(tonumber)' 2>/dev/null || echo "[]")
    completed_array=$(echo "${CATEGORIZED_ISSUES[completed]}" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s 'map(tonumber)' 2>/dev/null || echo "[]")
    
    # JSON出力
    jq -n \
        --arg repo "$repo" \
        --arg updated "$updated" \
        --argjson in_progress_count "$in_progress_count" \
        --argjson blocked_count "$blocked_count" \
        --argjson ready_count "$ready_count" \
        --argjson completed_count "$completed_count" \
        --argjson in_progress "$in_progress_array" \
        --argjson blocked "$blocked_array" \
        --argjson ready "$ready_array" \
        --argjson completed "$completed_array" \
        '{
            repository: $repo,
            updated: $updated,
            summary: {
                in_progress: $in_progress_count,
                blocked: $blocked_count,
                ready: $ready_count,
                completed: $completed_count
            },
            issues: {
                in_progress: $in_progress,
                blocked: $blocked,
                ready: $ready,
                completed: $completed
            }
        }'
}
