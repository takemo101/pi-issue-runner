#!/usr/bin/env bash
# context.sh - コンテキスト管理CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/context.sh"
source "$SCRIPT_DIR/../lib/log.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <subcommand> [options]

Manage context persistence for GitHub Issues.

Subcommands:
    show <issue>          Issue固有のコンテキストを表示
    show-project          プロジェクトコンテキストを表示
    add <issue> <text>    Issue固有のコンテキストに追記
    add-project <text>    プロジェクトコンテキストに追記
    edit <issue>          エディタでIssue固有コンテキストを編集
    edit-project          エディタでプロジェクトコンテキストを編集
    list                  コンテキストがあるIssue一覧
    clean [--days N]      古いコンテキストを削除（デフォルト: 30日）
    export <issue>        Markdown形式でエクスポート
    remove <issue>        Issue固有のコンテキストを削除
    remove-project        プロジェクトコンテキストを削除
    init <issue> [title]  Issue固有のコンテキストを初期化
    init-project          プロジェクトコンテキストを初期化

Options:
    -h, --help            このヘルプを表示

Examples:
    # コンテキストを表示
    $(basename "$0") show 42
    $(basename "$0") show-project

    # コンテキストに追記
    $(basename "$0") add 42 "JWT認証は依存ライブラリの問題で失敗"
    $(basename "$0") add-project "ShellCheck SC2155を修正する際は変数宣言と代入を分離"

    # エディタで編集
    $(basename "$0") edit 42
    $(basename "$0") edit-project

    # 一覧表示
    $(basename "$0") list

    # クリーンアップ
    $(basename "$0") clean --days 30

    # コンテキストを削除
    $(basename "$0") remove 42
    $(basename "$0") remove-project

    # コンテキストを初期化
    $(basename "$0") init 42 "My Feature"
    $(basename "$0") init-project
EOF
}

# エディタを取得
get_editor() {
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if command -v nano &>/dev/null; then
            editor="nano"
        elif command -v vim &>/dev/null; then
            editor="vim"
        elif command -v vi &>/dev/null; then
            editor="vi"
        else
            log_error "No editor found. Set \$EDITOR environment variable."
            return 1
        fi
    fi
    echo "$editor"
}

# show サブコマンド
cmd_show() {
    local issue_number="$1"
    
    if ! context_exists "$issue_number"; then
        log_warn "No context found for issue #$issue_number"
        return 1
    fi
    
    log_info "Context for issue #$issue_number:"
    echo ""
    export_context "$issue_number"
}

# show-project サブコマンド
cmd_show_project() {
    if ! context_exists; then
        log_warn "No project context found"
        return 1
    fi
    
    log_info "Project context:"
    echo ""
    export_context
}

# add サブコマンド
cmd_add() {
    local issue_number="$1"
    shift
    local text="$*"
    
    if [[ -z "$text" ]]; then
        log_error "Text is required"
        return 1
    fi
    
    append_issue_context "$issue_number" "$text"
    log_info "Added context to issue #$issue_number"
}

# add-project サブコマンド
cmd_add_project() {
    local text="$*"
    
    if [[ -z "$text" ]]; then
        log_error "Text is required"
        return 1
    fi
    
    append_project_context "$text"
    log_info "Added context to project"
}

# edit サブコマンド
cmd_edit() {
    local issue_number="$1"
    local editor
    editor="$(get_editor)" || return 1
    
    local context_file
    context_file="$(get_issue_context_file "$issue_number")"
    
    # ファイルが存在しない場合は初期化
    if [[ ! -f "$context_file" ]]; then
        init_issue_context "$issue_number"
    fi
    
    "$editor" "$context_file"
    log_info "Edited context for issue #$issue_number"
}

# edit-project サブコマンド
cmd_edit_project() {
    local editor
    editor="$(get_editor)" || return 1
    
    local context_file
    context_file="$(get_project_context_file)"
    
    # ファイルが存在しない場合は初期化
    if [[ ! -f "$context_file" ]]; then
        init_project_context
    fi
    
    "$editor" "$context_file"
    log_info "Edited project context"
}

# list サブコマンド
cmd_list() {
    local issues
    issues="$(list_issue_contexts)"
    
    if [[ -z "$issues" ]]; then
        log_info "No issue contexts found"
        return 0
    fi
    
    log_info "Issues with context:"
    echo ""
    while IFS= read -r issue; do
        echo "  #$issue"
    done <<< "$issues"
}

# clean サブコマンド
cmd_clean() {
    local days="30"
    
    # --days オプションを解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                days="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    log_info "Cleaning contexts older than $days days..."
    local count
    count="$(clean_old_contexts "$days")"
    
    if [[ "$count" -eq 0 ]]; then
        log_info "No old contexts found"
    else
        log_info "Removed $count old context(s)"
    fi
}

# export サブコマンド
cmd_export() {
    local issue_number="${1:-}"
    
    if [[ -z "$issue_number" ]]; then
        # プロジェクトコンテキストをエクスポート
        if ! context_exists; then
            log_error "No project context found"
            return 1
        fi
        export_context
    else
        # Issue固有コンテキストをエクスポート
        if ! context_exists "$issue_number"; then
            log_error "No context found for issue #$issue_number"
            return 1
        fi
        export_context "$issue_number"
    fi
}

# remove サブコマンド
cmd_remove() {
    local issue_number="$1"
    
    if ! context_exists "$issue_number"; then
        log_warn "No context found for issue #$issue_number"
        return 1
    fi
    
    # 確認プロンプト
    read -p "Remove context for issue #$issue_number? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remove_context "$issue_number"
        log_info "Removed context for issue #$issue_number"
    else
        log_info "Cancelled"
    fi
}

# remove-project サブコマンド
cmd_remove_project() {
    if ! context_exists; then
        log_warn "No project context found"
        return 1
    fi
    
    # 確認プロンプト
    read -p "Remove project context? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remove_context
        log_info "Removed project context"
    else
        log_info "Cancelled"
    fi
}

# init サブコマンド
cmd_init() {
    local issue_number="$1"
    local issue_title="${2:-Issue #${issue_number}}"
    
    if context_exists "$issue_number"; then
        log_warn "Context already exists for issue #$issue_number"
        return 1
    fi
    
    init_issue_context "$issue_number" "$issue_title"
    log_info "Initialized context for issue #$issue_number"
}

# init-project サブコマンド
cmd_init_project() {
    if context_exists; then
        log_warn "Project context already exists"
        return 1
    fi
    
    init_project_context
    log_info "Initialized project context"
}

main() {
    # 設定ファイルチェック（必須）
    require_config_file "pi-context" || exit 1
    
    # ヘルプ表示
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        show)
            if [[ $# -lt 1 ]]; then
                log_error "Issue number is required"
                usage
                exit 1
            fi
            cmd_show "$@"
            ;;
        show-project)
            cmd_show_project
            ;;
        add)
            if [[ $# -lt 2 ]]; then
                log_error "Issue number and text are required"
                usage
                exit 1
            fi
            cmd_add "$@"
            ;;
        add-project)
            if [[ $# -lt 1 ]]; then
                log_error "Text is required"
                usage
                exit 1
            fi
            cmd_add_project "$@"
            ;;
        edit)
            if [[ $# -lt 1 ]]; then
                log_error "Issue number is required"
                usage
                exit 1
            fi
            cmd_edit "$@"
            ;;
        edit-project)
            cmd_edit_project
            ;;
        list)
            cmd_list
            ;;
        clean)
            cmd_clean "$@"
            ;;
        export)
            cmd_export "$@"
            ;;
        remove)
            if [[ $# -lt 1 ]]; then
                log_error "Issue number is required"
                usage
                exit 1
            fi
            cmd_remove "$@"
            ;;
        remove-project)
            cmd_remove_project
            ;;
        init)
            if [[ $# -lt 1 ]]; then
                log_error "Issue number is required"
                usage
                exit 1
            fi
            cmd_init "$@"
            ;;
        init-project)
            cmd_init_project
            ;;
        *)
            log_error "Unknown subcommand: $subcommand"
            usage
            exit 1
            ;;
    esac
}

main "$@"
