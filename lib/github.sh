#!/usr/bin/env bash
# github.sh - GitHub CLI操作

set -euo pipefail

_GITHUB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_GITHUB_LIB_DIR/log.sh"

# jqがインストールされているか確認
check_jq() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        log_info "Install: brew install jq (macOS) or apt install jq (Linux)"
        return 1
    fi
}

# gh CLIがインストールされているか確認
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install: https://cli.github.com/"
        return 1
    fi
    
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated"
        log_info "Run: gh auth login"
        return 1
    fi
}

# 全ての依存関係をチェック
check_dependencies() {
    check_jq || return 1
    check_gh_cli || return 1
}

# Issue情報を取得
get_issue() {
    local issue_number="$1"
    
    check_gh_cli || return 1
    
    gh issue view "$issue_number" --json number,title,body,labels,state,comments 2>/dev/null
}

# Issue番号からブランチ名を生成
issue_to_branch_name() {
    local issue_number="$1"
    local title
    
    check_jq || {
        echo "issue-$issue_number"
        return
    }
    
    title=$(get_issue "$issue_number" | jq -r '.title') || {
        echo "issue-$issue_number"
        return
    }
    
    # タイトルを英数字とハイフンに正規化
    local sanitized
    sanitized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-40)
    
    echo "issue-$issue_number-$sanitized"
}

# Issueのタイトルを取得
get_issue_title() {
    local issue_number="$1"
    
    check_jq || {
        echo "Issue #$issue_number"
        return
    }
    
    get_issue "$issue_number" | jq -r '.title' || echo "Issue #$issue_number"
}

# Issueの本文を取得
get_issue_body() {
    local issue_number="$1"
    
    check_jq || return 1
    
    get_issue "$issue_number" | jq -r '.body // empty'
}

# Issueのコメントを取得してMarkdown形式でフォーマット
# Usage: get_issue_comments <issue_number> [max_comments]
# max_comments: 最大コメント数（0 = 無制限、デフォルト: 0）
get_issue_comments() {
    local issue_number="$1"
    local max_comments="${2:-0}"
    
    check_jq || return 1
    
    local comments_json
    comments_json="$(get_issue "$issue_number" | jq -r '.comments // []')"
    
    # コメントが空の場合は空文字を返す
    local comment_count
    comment_count="$(echo "$comments_json" | jq 'length')"
    if [[ "$comment_count" -eq 0 ]]; then
        echo ""
        return 0
    fi
    
    # max_commentsが0より大きい場合、最新N件に制限
    if [[ "$max_comments" -gt 0 && "$comment_count" -gt "$max_comments" ]]; then
        # 最新N件を取得（配列の後ろからN件）
        comments_json="$(echo "$comments_json" | jq ".[-${max_comments}:]")"
    fi
    
    format_comments_section "$comments_json"
}

# コメントJSONをMarkdown形式にフォーマット
# Usage: format_comments_section <comments_json>
format_comments_section() {
    local comments_json="$1"
    
    # コメントが空の場合は空文字を返す
    if [[ -z "$comments_json" || "$comments_json" == "[]" || "$comments_json" == "null" ]]; then
        echo ""
        return 0
    fi
    
    local result=""
    local comment_count
    comment_count="$(echo "$comments_json" | jq 'length')"
    
    for ((i=0; i<comment_count; i++)); do
        local author body created_at formatted_date
        author="$(echo "$comments_json" | jq -r ".[$i].author.login // \"unknown\"")"
        body="$(echo "$comments_json" | jq -r ".[$i].body // \"\"")"
        created_at="$(echo "$comments_json" | jq -r ".[$i].createdAt // \"\"")"
        
        # ISO8601形式から日付部分を抽出（YYYY-MM-DD）
        if [[ -n "$created_at" ]]; then
            formatted_date="${created_at%%T*}"
        else
            formatted_date="unknown"
        fi
        
        # コメント本文をサニタイズ
        body="$(sanitize_issue_body "$body")"
        
        # Markdown形式で出力
        if [[ -n "$result" ]]; then
            result="${result}

"
        fi
        result="${result}### @${author} (${formatted_date})
${body}"
    done
    
    echo "$result"
}

# Issueの状態を取得
get_issue_state() {
    local issue_number="$1"
    
    check_jq || return 1
    
    get_issue "$issue_number" | jq -r '.state'
}

# リポジトリ情報を取得
get_repo_info() {
    gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null
}

# ===================
# Issue本文サニタイズ
# ===================

# 危険なパターンの定義
# shellcheck disable=SC2034
_DANGEROUS_PATTERNS=(
    '\$\([^)]+\)'           # コマンド置換 $(...)
    '`[^`]+`'               # バッククォート `...`
    '\$\{[^}]+\}'           # 変数展開 ${...}
)

# 危険なパターンが含まれているかチェック
# 戻り値: 0=危険なパターンあり(true), 1=安全(false)
# Bashの規約に従い、条件が真の場合に0を返す
has_dangerous_patterns() {
    local text="$1"
    
    # コマンド置換 $(...) - grepを使用して安全に検出
    if echo "$text" | grep -qE '\$\([^)]+\)'; then
        log_warn "Dangerous pattern detected: command substitution \$(...)  "
        return 0  # 危険あり = true
    fi
    
    # バッククォート `...`
    if echo "$text" | grep -q '`[^`]*`'; then
        log_warn "Dangerous pattern detected: backtick command \`...\`"
        return 0  # 危険あり = true
    fi
    
    # 変数展開 ${...}
    if echo "$text" | grep -qE '\$\{[^}]+\}'; then
        log_warn "Dangerous pattern detected: variable expansion \${...}"
        return 0  # 危険あり = true
    fi
    
    return 1  # 安全 = false
}

# Issue本文のサニタイズ
# 危険なパターンをエスケープして安全な形式に変換
# Usage: sanitize_issue_body <body>
sanitize_issue_body() {
    local body="$1"
    local sanitized="$body"
    
    # 空の場合はそのまま返す
    if [[ -z "$body" ]]; then
        echo ""
        return 0
    fi
    
    # 危険なパターンを検出して警告
    if has_dangerous_patterns "$body" 2>/dev/null; then
        log_info "Issue body contains potentially dangerous patterns, sanitizing..."
    fi
    
    # サニタイズ処理（sedを使用してクロスプラットフォーム互換性を確保）
    # 1. $( を \$( にエスケープ（コマンド置換を無効化）
    sanitized=$(echo "$sanitized" | sed 's/\$(/\\$(/g')
    
    # 2. バッククォートをエスケープ
    sanitized=$(echo "$sanitized" | sed 's/`/\\`/g')
    
    # 3. ${ を \${ にエスケープ（変数展開を無効化）
    sanitized=$(echo "$sanitized" | sed 's/\${/\\${/g')
    
    echo "$sanitized"
}

# ===================
# Issue取得（時刻フィルタ）
# ===================

# 指定時刻以降に作成されたIssueを取得
# Usage: get_issues_created_after <start_time_iso8601> [max_issues] [label]
# Returns: Issue番号を1行ずつ出力
get_issues_created_after() {
    local start_time="$1"
    local max_issues="${2:-20}"
    local label="${3:-}"
    
    check_gh_cli || return 1
    check_jq || return 1
    
    # 自分が作成したopenなIssueを取得し、開始時刻以降のものをフィルタ
    # shellcheck disable=SC2054  # number,createdAt is a gh CLI JSON fields parameter, not array elements
    local gh_args=(issue list --state open --author "@me" --limit "$max_issues" --json number,createdAt)
    
    # ラベルが指定された場合はフィルタに追加
    if [[ -n "$label" ]]; then
        gh_args+=(--label "$label")
    fi
    
    gh "${gh_args[@]}" 2>/dev/null \
        | jq -r --arg start "$start_time" '.[] | select(.createdAt >= $start) | .number'
}

# ===================
# PR操作
# ===================

# PRをDraft化
# Usage: mark_pr_as_draft <pr_number>
# Returns: 0=成功, 1=失敗
mark_pr_as_draft() {
    local pr_number="$1"
    
    check_gh_cli || return 1
    
    log_info "Marking PR #$pr_number as draft"
    
    # PRをDraft化（gh CLIのバージョンによって方法が異なる）
    if gh pr ready "$pr_number" --undo 2>/dev/null; then
        log_info "PR marked as draft"
        return 0
    else
        log_warn "Could not mark PR as draft (may require different gh CLI version)"
        return 1
    fi
}

# PRにコメント追加
# Usage: add_pr_comment <pr_number> <comment>
# Returns: 0=成功, 1=失敗
add_pr_comment() {
    local pr_number="$1"
    local comment="$2"
    
    check_gh_cli || return 1
    
    log_info "Adding comment to PR #$pr_number"
    
    if echo "$comment" | gh pr comment "$pr_number" -F - 2>/dev/null; then
        log_info "Comment added successfully"
        return 0
    else
        log_warn "Failed to add comment"
        return 1
    fi
}

# PRのCIチェック状態を取得
# Usage: get_pr_checks_status <pr_number>
# Returns: success | failure | pending | unknown
get_pr_checks_status() {
    local pr_number="$1"
    
    check_gh_cli || return 1
    check_jq || return 1
    
    # PRのチェック状態を取得
    local checks_json
    checks_json=$(gh pr checks "$pr_number" --json state,conclusion 2>/dev/null || echo "[]")
    
    # チェックがない場合は成功とみなす
    if [[ -z "$checks_json" || "$checks_json" == "[]" ]]; then
        echo "success"
        return 0
    fi
    
    # 失敗があるかチェック
    if echo "$checks_json" | jq -e 'any(.[]; .state == "FAILURE" or .conclusion == "failure")' > /dev/null 2>&1; then
        echo "failure"
        return 0
    fi
    
    # 進行中があるかチェック
    if echo "$checks_json" | jq -e 'any(.[]; .state == "PENDING" or .state == "QUEUED")' > /dev/null 2>&1; then
        echo "pending"
        return 0
    fi
    
    # 全て成功
    if echo "$checks_json" | jq -e 'all(.[]; .state == "SUCCESS" or .conclusion == "success")' > /dev/null 2>&1; then
        echo "success"
        return 0
    fi
    
    echo "unknown"
    return 0
}

# 失敗したCIのログを取得
# Usage: get_failed_ci_logs <pr_number>
get_failed_ci_logs() {
    local pr_number="$1"
    
    check_gh_cli || return 1
    
    log_info "Fetching failed CI logs for PR #$pr_number"
    
    # 最新の失敗したワークフロー実行を取得
    local run_id
    run_id=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
    
    if [[ -z "$run_id" ]]; then
        log_warn "No failed runs found"
        return 1
    fi
    
    # 失敗したジョブのログを取得
    gh run view "$run_id" --log-failed 2>/dev/null || echo ""
}

# ===================
# Issue依存関係チェック
# ===================

# IssueのブロッキングIssueをチェック
# Usage: check_issue_blocked <issue_number>
# Returns: 0=ブロックなし(安全), 1=ブロックあり
# ブロックありの場合、stdoutにブロック情報のJSONを出力
# フォーマット: [{"number": 482, "title": "...", "state": "OPEN"}, ...]
check_issue_blocked() {
    local issue_number="$1"
    
    check_gh_cli || return 1
    check_jq || return 1
    
    # Issue本文を取得
    local issue_body
    issue_body="$(get_issue_body "$issue_number")"
    
    if [[ -z "$issue_body" ]]; then
        # Issueが取得できない場合は安全とみなす
        return 0
    fi
    
    # "Blocked by #XXX" または "依存関係" セクションからブロッカーを抽出
    local blockers=""
    local open_blockers="[]"
    
    # "Blocked by #XXX" パターンを抽出（大文字小文字非依存、複数行対応）
    # Issue本文から "Blocked by #123" または "blocks: #123" などのパターンを抽出
    blockers="$(echo "$issue_body" | grep -iE '(blocked by|blocks?\s*:?)\s*#[0-9]+' | grep -oE '#[0-9]+' | tr -d '#')"
    
    # "依存関係" セクションがある場合はそこもチェック
    if echo "$issue_body" | grep -qE '^#{1,2}\s*依存関係'; then
        local dep_section
        # "依存関係" セクションから次のセクションまでの内容を抽出
        dep_section="$(echo "$issue_body" | sed -n '/^#{1,2}\s*依存関係/,/^#{1,2}\s/p' | head -n -1)"
        local dep_blockers
        dep_blockers="$(echo "$dep_section" | grep -oE '#[0-9]+' | tr -d '#')"
        if [[ -n "$dep_blockers" ]]; then
            blockers="$blockers $dep_blockers"
        fi
    fi
    
    # 重複を除去して処理
    blockers="$(echo "$blockers" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    
    if [[ -z "$(echo "$blockers" | tr -d ' ')" ]]; then
        # ブロッキングIssueが見つからない場合は安全
        return 0
    fi
    
    # 各ブロッキングIssueの状態を確認
    local blocker_number
    for blocker_number in $blockers; do
        # Issueが存在し、かつOPEN状態かチェック
        local blocker_info
        blocker_info="$(gh issue view "$blocker_number" --json number,title,state 2>/dev/null || echo "")"
        
        if [[ -n "$blocker_info" ]]; then
            local blocker_state
            blocker_state="$(echo "$blocker_info" | jq -r '.state // "UNKNOWN"')"
            
            if [[ "$blocker_state" == "OPEN" ]]; then
                # OPENなブロッカーを追加
                local blocker_title
                blocker_title="$(echo "$blocker_info" | jq -r '.title // "Unknown"')"
                local blocker_obj
                blocker_obj="$(jq -n --arg num "$blocker_number" --arg title "$blocker_title" --arg state "$blocker_state" '{number: ($num | tonumber), title: $title, state: $state}')"
                open_blockers="$(echo "$open_blockers" | jq --argjson obj "$blocker_obj" '. + [$obj]')"
            fi
        fi
    done
    
    # OPENなブロッカーがあるかチェック
    local open_count
    open_count="$(echo "$open_blockers" | jq 'length')"
    
    if [[ "$open_count" -gt 0 ]]; then
        # ブロックあり - ブロッカー情報を出力
        echo "$open_blockers"
        return 1
    fi
    
    # ブロックなし
    return 0
}

# ===================
# セッションラベル管理
# ===================

# セッションラベルを生成
# Usage: generate_session_label
# Returns: ラベル名（例: pi-runner-20260201-082900）
generate_session_label() {
    echo "pi-runner-$(date +%Y%m%d-%H%M%S)"
}

# ラベルを作成（存在しない場合のみ）
# Usage: create_label_if_not_exists <label> [description]
# Returns: 0=成功, 1=失敗
create_label_if_not_exists() {
    local label="$1"
    local description="${2:-Created by pi-issue-runner session}"
    
    check_gh_cli || return 1
    
    # ラベルが存在するかチェック（エラー出力を抑制）
    if gh label list --search "$label" --json name 2>/dev/null | jq -e --arg name "$label" '.[] | select(.name == $name)' > /dev/null 2>&1; then
        log_debug "Label '$label' already exists"
        return 0
    fi
    
    # ラベルを作成
    if gh label create "$label" --description "$description" --color "0E8A16" 2>/dev/null; then
        log_info "Created label: $label"
        return 0
    else
        log_warn "Failed to create label: $label (may already exist or insufficient permissions)"
        return 0  # ラベル作成失敗は致命的ではないので続行
    fi
}
