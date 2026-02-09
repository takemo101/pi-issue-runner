#!/usr/bin/env bash
# github.sh - GitHub CLI操作

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_GITHUB_SH_SOURCED:-}" ]]; then
    return 0
fi
_GITHUB_SH_SOURCED="true"

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
    local author created_at body formatted_date
    
    # 全コメントを単一のjq呼び出しで処理
    # null文字区切りでauthor, createdAt, bodyを出力し、レコード間もnull文字で区切る
    while IFS= read -r -d '' author && IFS= read -r -d '' created_at && IFS= read -r -d '' body; do
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
    done < <(printf '%s' "$comments_json" | jq -j \
        '.[] | (.author.login // "unknown"), "\u0000", (.createdAt // ""), "\u0000", (.body // ""), "\u0000"')
    
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
    if printf '%s\n' "$text" | grep -qE '\$\([^)]+\)'; then
        log_warn "Dangerous pattern detected: command substitution \$(...)  "
        return 0  # 危険あり = true
    fi
    
    # バッククォート `...`
    if printf '%s\n' "$text" | grep -q '`[^`]*`'; then
        log_warn "Dangerous pattern detected: backtick command \`...\`"
        return 0  # 危険あり = true
    fi
    
    # 変数展開 ${...}
    if printf '%s\n' "$text" | grep -qE '\$\{[^}]+\}'; then
        log_warn "Dangerous pattern detected: variable expansion \${...}"
        return 0  # 危険あり = true
    fi
    
    # プロセス置換 <(...)
    if printf '%s\n' "$text" | grep -qE '<\([^)]+\)'; then
        log_warn "Dangerous pattern detected: process substitution <(...)"
        return 0  # 危険あり = true
    fi
    
    # プロセス置換 >(...)
    if printf '%s\n' "$text" | grep -qE '>\([^)]+\)'; then
        log_warn "Dangerous pattern detected: process substitution >(...)"
        return 0  # 危険あり = true
    fi
    
    # 算術展開 $((...))
    if printf '%s\n' "$text" | grep -qE '\$\(\([^)]+\)\)'; then
        log_warn "Dangerous pattern detected: arithmetic expansion \$((...))"
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
    # printf '%s' を使用してechoの問題を回避：
    # - 末尾の改行が追加されない
    # - -n, -e で始まる文字列が誤解釈されない
    # 
    # 7つのsedコマンドを1回にまとめてパフォーマンスを改善
    sanitized=$(printf '%s' "$sanitized" | sed \
        -e 's/\$((/__ARITH_OPEN__/g' \
        -e 's/\$(/\\$(/g' \
        -e 's/__ARITH_OPEN__/\\$((/g' \
        -e 's/`/\\`/g' \
        -e 's/\${/\\${/g' \
        -e 's/<(/\\<( /g' \
        -e 's/>(/\\>(/g')
    
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
# Issue依存関係（ブロッカー）管理
# ===================

# Issueのブロッカー一覧を取得（GraphQL API使用）
# 引数: issue_number
# 戻り値: JSON配列 [{number, title, state}, ...]
# 例: [{"number":38,"title":"基盤機能","state":"OPEN"}]
get_issue_blockers() {
    local issue_number="$1"
    
    check_jq || return 1
    check_gh_cli || return 1
    
    # リポジトリ情報を取得
    local repo_info owner repo
    repo_info=$(gh repo view --json owner,name 2>/dev/null) || {
        log_error "Failed to get repository info"
        echo "[]"
        return 1
    }
    
    owner=$(echo "$repo_info" | jq -r '.owner.login')
    repo=$(echo "$repo_info" | jq -r '.name')
    
    if [[ -z "$owner" || -z "$repo" ]]; then
        log_error "Could not determine repository owner/name"
        echo "[]"
        return 1
    fi
    
    local query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          blockedBy(first: 20) {
            nodes {
              number
              title
              state
            }
          }
        }
      }
    }'
    
    # GraphQL APIでブロッカーを取得
    local result
    result=$(gh api graphql \
        -F "owner=$owner" \
        -F "repo=$repo" \
        -F "number=$issue_number" \
        -f "query=$query" 2>/dev/null) || {
        echo "[]"
        return 1
    }
    
    # blockedBy.nodes を抽出
    local blockers
    blockers=$(echo "$result" | jq -r '.data.repository.issue.blockedBy.nodes // []')
    
    echo "$blockers"
}

# Issueがブロックされているかチェック
# 引数: issue_number
# 戻り値: 0=ブロックされていない, 1=ブロックされている
# stdout: ブロックされている場合、OPENなブロッカー情報をJSON配列で出力
check_issue_blocked() {
    local issue_number="$1"
    
    local blockers
    if ! blockers=$(get_issue_blockers "$issue_number"); then
        log_error "Failed to get issue blockers"
        return 1
    fi
    
    # OPEN状態のブロッカーをフィルタ
    local open_blockers
    open_blockers=$(echo "$blockers" | jq '[.[] | select(.state == "OPEN")]')
    
    local open_count
    open_count=$(echo "$open_blockers" | jq 'length')
    
    if [[ "$open_count" -gt 0 ]]; then
        echo "$open_blockers"
        return 1
    fi
    
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
