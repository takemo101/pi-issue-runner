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
