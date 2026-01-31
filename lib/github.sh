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
    
    gh issue view "$issue_number" --json number,title,body,labels,state 2>/dev/null
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
# Usage: get_issues_created_after <start_time_iso8601> [max_issues]
# Returns: Issue番号を1行ずつ出力
get_issues_created_after() {
    local start_time="$1"
    local max_issues="${2:-20}"
    
    check_gh_cli || return 1
    check_jq || return 1
    
    # 自分が作成したopenなIssueを取得し、開始時刻以降のものをフィルタ
    gh issue list --state open --author "@me" --limit "$max_issues" --json number,createdAt 2>/dev/null \
        | jq -r --arg start "$start_time" '.[] | select(.createdAt >= $start) | .number'
}
