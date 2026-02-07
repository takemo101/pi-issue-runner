#!/usr/bin/env bash
# context.sh - コンテキスト永続化管理

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CONTEXT_SH_SOURCED:-}" ]]; then
    return 0
fi
_CONTEXT_SH_SOURCED="true"

# 自身のディレクトリを取得
_CONTEXT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリを読み込み
if ! declare -f get_config > /dev/null 2>&1; then
    source "$_CONTEXT_LIB_DIR/config.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# ===================
# ディレクトリ管理
# ===================

# コンテキストディレクトリを取得
# 戻り値: .worktrees/.context のパス
get_context_dir() {
    load_config
    local worktree_base
    worktree_base="$(get_config worktree_base_dir)"
    echo "${worktree_base}/.context"
}

# コンテキストディレクトリを初期化
init_context_dir() {
    local context_dir
    context_dir="$(get_context_dir)"
    
    if [[ ! -d "$context_dir" ]]; then
        mkdir -p "$context_dir/issues"
        log_debug "Created context directory: $context_dir"
    fi
    
    if [[ ! -d "$context_dir/issues" ]]; then
        mkdir -p "$context_dir/issues"
        log_debug "Created context issues directory: $context_dir/issues"
    fi
}

# プロジェクトコンテキストファイルのパスを取得
# 戻り値: project.md のパス
get_project_context_file() {
    local context_dir
    context_dir="$(get_context_dir)"
    echo "${context_dir}/project.md"
}

# Issue固有コンテキストファイルのパスを取得
# 引数: $1 - issue_number
# 戻り値: issues/<issue_number>.md のパス
get_issue_context_file() {
    local issue_number="$1"
    local context_dir
    context_dir="$(get_context_dir)"
    echo "${context_dir}/issues/${issue_number}.md"
}

# ===================
# コンテキスト読み込み
# ===================

# プロジェクト全体のコンテキストを読み込み
# 戻り値: コンテキスト内容（Markdown形式）、ファイルがない場合は空文字列
load_project_context() {
    local context_file
    context_file="$(get_project_context_file)"
    
    if [[ -f "$context_file" ]]; then
        cat "$context_file"
    fi
}

# Issue固有のコンテキストを読み込み
# 引数: $1 - issue_number
# 戻り値: コンテキスト内容（Markdown形式）、ファイルがない場合は空文字列
load_issue_context() {
    local issue_number="$1"
    local context_file
    context_file="$(get_issue_context_file "$issue_number")"
    
    if [[ -f "$context_file" ]]; then
        cat "$context_file"
    fi
}

# 両方のコンテキストを結合して読み込み
# 引数: $1 - issue_number
# 戻り値: 結合されたコンテキスト（セクション分け付き）
load_all_context() {
    local issue_number="$1"
    local project_context issue_context
    
    project_context="$(load_project_context)"
    issue_context="$(load_issue_context "$issue_number")"
    
    # 両方とも空の場合は何も返さない
    if [[ -z "$project_context" && -z "$issue_context" ]]; then
        return 0
    fi
    
    # プロジェクトコンテキストがある場合
    if [[ -n "$project_context" ]]; then
        echo "### プロジェクト全体の知見"
        echo ""
        echo "$project_context"
        echo ""
    fi
    
    # Issue固有コンテキストがある場合
    if [[ -n "$issue_context" ]]; then
        echo "### このIssue固有の履歴"
        echo ""
        echo "$issue_context"
    fi
}

# ===================
# コンテキスト保存
# ===================

# プロジェクトコンテキストファイルを初期化（新規作成）
init_project_context() {
    init_context_dir
    
    local context_file
    context_file="$(get_project_context_file)"
    
    if [[ ! -f "$context_file" ]]; then
        cat > "$context_file" << 'EOF'
# Project Context

## 技術的決定事項

## 既知の問題

## 学習した教訓

## 重要なファイル

EOF
        log_debug "Initialized project context: $context_file"
    fi
}

# Issue固有コンテキストを初期化（新規作成）
# 引数: $1 - issue_number
#       $2 - issue_title (オプション)
init_issue_context() {
    local issue_number="$1"
    local issue_title="${2:-Issue #${issue_number}}"
    
    init_context_dir
    
    local context_file
    context_file="$(get_issue_context_file "$issue_number")"
    
    if [[ ! -f "$context_file" ]]; then
        local timestamp
        timestamp="$(date +"%Y-%m-%d")"
        
        cat > "$context_file" << EOF
# Issue #${issue_number} Context

## Issue情報
- Title: ${issue_title}
- Created: ${timestamp}

## 試行履歴

## 関連Issue

## メモ

EOF
        log_debug "Initialized issue context: $context_file"
    fi
}

# プロジェクトコンテキストに追記
# 引数: $1 - text (追記する内容)
append_project_context() {
    local text="$1"
    
    init_project_context
    
    local context_file
    context_file="$(get_project_context_file)"
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    
    {
        echo ""
        echo "## Entry (${timestamp})"
        echo ""
        echo "$text"
    } >> "$context_file"
    
    log_debug "Appended to project context: $context_file"
}

# Issue固有コンテキストに追記
# 引数: $1 - issue_number
#       $2 - text (追記する内容)
append_issue_context() {
    local issue_number="$1"
    local text="$2"
    
    # ファイルが存在しない場合は初期化
    local context_file
    context_file="$(get_issue_context_file "$issue_number")"
    if [[ ! -f "$context_file" ]]; then
        init_issue_context "$issue_number"
    fi
    
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    
    {
        echo ""
        echo "## Session (${timestamp})"
        echo ""
        echo "$text"
    } >> "$context_file"
    
    log_debug "Appended to issue context: $context_file"
}

# ===================
# コンテキスト管理
# ===================

# Issue固有コンテキストの一覧を取得
# 戻り値: Issue番号のリスト（1行に1つ）
list_issue_contexts() {
    local context_dir
    context_dir="$(get_context_dir)"
    local issues_dir="${context_dir}/issues"
    
    if [[ ! -d "$issues_dir" ]]; then
        return 0
    fi
    
    for context_file in "$issues_dir"/*.md; do
        [[ -f "$context_file" ]] || continue
        local issue_number
        issue_number="$(basename "$context_file" .md)"
        echo "$issue_number"
    done | sort -n
}

# コンテキストをエクスポート（表示用）
# 引数: $1 - issue_number (空の場合はプロジェクトコンテキスト)
# 戻り値: コンテキスト内容
export_context() {
    local issue_number="${1:-}"
    
    if [[ -z "$issue_number" ]]; then
        # プロジェクトコンテキストを表示
        load_project_context
    else
        # Issue固有コンテキストを表示
        load_issue_context "$issue_number"
    fi
}

# 古いコンテキストをクリーンアップ
# 引数: $1 - days (指定日数より古いコンテキストを削除)
# 戻り値: 削除されたファイル数
clean_old_contexts() {
    local days="${1:-30}"
    local context_dir
    context_dir="$(get_context_dir)"
    local issues_dir="${context_dir}/issues"
    
    if [[ ! -d "$issues_dir" ]]; then
        echo "0"
        return 0
    fi
    
    local count=0
    while IFS= read -r context_file; do
        [[ -z "$context_file" ]] && continue
        rm -f "$context_file"
        ((count++)) || true
        log_debug "Removed old context: $context_file"
    done < <(find "$issues_dir" -name "*.md" -type f -mtime +"$days" 2>/dev/null || true)
    
    echo "$count"
}

# コンテキストファイルが存在するかチェック
# 引数: $1 - issue_number (空の場合はプロジェクトコンテキスト)
# 戻り値: 0=存在する, 1=存在しない
context_exists() {
    local issue_number="${1:-}"
    
    if [[ -z "$issue_number" ]]; then
        # プロジェクトコンテキストの存在確認
        local context_file
        context_file="$(get_project_context_file)"
        [[ -f "$context_file" ]]
    else
        # Issue固有コンテキストの存在確認
        local context_file
        context_file="$(get_issue_context_file "$issue_number")"
        [[ -f "$context_file" ]]
    fi
}

# コンテキストファイルを削除
# 引数: $1 - issue_number (空の場合はプロジェクトコンテキスト)
remove_context() {
    local issue_number="${1:-}"
    
    if [[ -z "$issue_number" ]]; then
        # プロジェクトコンテキストを削除
        local context_file
        context_file="$(get_project_context_file)"
        if [[ -f "$context_file" ]]; then
            rm -f "$context_file"
            log_debug "Removed project context: $context_file"
        fi
    else
        # Issue固有コンテキストを削除
        local context_file
        context_file="$(get_issue_context_file "$issue_number")"
        if [[ -f "$context_file" ]]; then
            rm -f "$context_file"
            log_debug "Removed issue context: $context_file"
        fi
    fi
}
