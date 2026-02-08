#!/usr/bin/env bash
# ============================================================================
# init.sh - Project initialization
#
# Initializes a project for use with pi-issue-runner by creating
# configuration files, directories, and optional templates.
#
# Usage: ./scripts/init.sh [options]
#
# Options:
#   --full          Full setup (creates agents/ and workflows/ directories)
#   --minimal       Minimal setup (.pi-runner.yaml only)
#   --force         Overwrite existing files
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/init.sh              # Standard setup
#   ./scripts/init.sh --full       # Full setup
#   ./scripts/init.sh --minimal    # Minimal setup
#   ./scripts/init.sh --force      # Force overwrite
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log.sh"

# ヘルプを先に処理
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            cat << 'HELP_EOF'
Usage: init.sh [options]

Options:
    --full          完全セットアップ（agents/, workflows/ も作成）
    --minimal       最小セットアップ（.pi-runner.yaml のみ）
    --force         既存ファイルを上書き
    -h, --help      このヘルプを表示

Examples:
    init.sh              # 標準セットアップ
    init.sh --full       # 完全セットアップ
    init.sh --minimal    # 最小セットアップ
    init.sh --force      # 既存ファイルを上書き
HELP_EOF
            exit 0
            ;;
    esac
done

# AGENTS.md の「既知の制約」セクション
AGENTS_MD_SECTION='## 既知の制約

<!-- エージェントが重要な知見を発見した際、ここに1行サマリーとリンクを追加する -->
<!-- 例: - playwright-cli 0.0.63+: デフォルトセッション使用必須 → [詳細](docs/decisions/001-playwright-session.md) -->'

# AGENTS.md に「既知の制約」セクションを追加
update_agents_md() {
    local agents_md="AGENTS.md"
    
    # AGENTS.md が存在しない場合はスキップ
    if [[ ! -f "$agents_md" ]]; then
        log_warn "AGENTS.md が見つかりません（スキップ）"
        return 0
    fi
    
    # 既に「既知の制約」セクションがある場合はスキップ
    if grep -qF "## 既知の制約" "$agents_md" 2>/dev/null; then
        log_warn "AGENTS.md に「既知の制約」セクションは既に存在します"
        return 0
    fi
    
    # ファイル末尾に追加
    {
        echo ""
        echo "$AGENTS_MD_SECTION"
    } >> "$agents_md"
    
    log_success "AGENTS.md に「既知の制約」セクションを追加"
}

# .pi-runner.yaml のテンプレート
generate_config_content() {
    cat << 'EOF'
# pi-issue-runner 設定ファイル
# 詳細: https://github.com/takemo101/pi-issue-runner/blob/main/docs/configuration.md

worktree:
  base_dir: ".worktrees"
  # copy_files: ".env .env.local"  # worktreeにコピーするファイル

tmux:
  session_prefix: "pi"
  # start_in_session: true

pi:
  command: "pi"
  # args: ""

# parallel:
#   max_concurrent: 0  # 0 = 無制限
EOF
}

# .worktrees/.gitkeep のテンプレート
generate_gitkeep_content() {
    cat << 'EOF'
# このディレクトリはpi-issue-runnerのworktree用です
# .gitignoreで除外されています
EOF
}

# agents/custom.md のテンプレート
generate_custom_agent_content() {
    cat << 'EOF'
# Custom Agent

GitHub Issue #{{issue_number}} を処理します。

## コンテキスト
- **Issue番号**: #{{issue_number}}
- **タイトル**: {{issue_title}}
- **ブランチ**: {{branch_name}}
- **作業ディレクトリ**: {{worktree_path}}

## タスク
1. Issueの内容を確認
2. 必要な変更を実装
3. テストを実行
4. コミット＆プッシュ
EOF
}

# workflows/custom.yaml のテンプレート
generate_custom_workflow_content() {
    cat << 'EOF'
name: custom
description: カスタムワークフロー
steps:
  - plan
  - implement
  - review
  - merge
EOF
}

# .gitignore に追加する内容
GITIGNORE_ENTRIES="
# pi-issue-runner
.worktrees/
.improve-logs/
.pi-runner.yaml.local
.pi-runner.yaml
.pi-runner.yml
.pi-prompt.md
*.swp
"

# ファイルを作成（上書きチェック付き）
create_file() {
    local file="$1"
    local content="$2"
    local force="$3"
    
    if [[ -f "$file" ]]; then
        if [[ "$force" == "true" ]]; then
            echo "$content" > "$file"
            log_success "$file を上書き"
        else
            log_warn "$file は既に存在します（--force で上書き可能）"
            return 1
        fi
    else
        local dir
        dir="$(dirname "$file")"
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
        echo "$content" > "$file"
        log_success "$file を作成"
    fi
    return 0
}

# ディレクトリを作成
create_directory() {
    local dir="$1"
    
    if [[ -d "$dir" ]]; then
        log_warn "$dir ディレクトリは既に存在します"
        return 1
    else
        mkdir -p "$dir"
        log_success "$dir/ ディレクトリを作成"
        return 0
    fi
}

# .gitignore を更新
update_gitignore() {
    local force="$1"
    local gitignore=".gitignore"
    local added=false
    
    # 各エントリをチェックして追加
    while IFS= read -r entry; do
        # 空行とコメント行はスキップしない（そのまま処理）
        [[ -z "$entry" ]] && continue
        
        # コメント行は特別に処理
        if [[ "$entry" == \#* ]]; then
            if [[ ! -f "$gitignore" ]] || ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
                echo "$entry" >> "$gitignore"
            fi
            continue
        fi
        
        # 既に存在するかチェック（完全一致）
        if [[ -f "$gitignore" ]] && grep -qFx "$entry" "$gitignore" 2>/dev/null; then
            continue
        fi
        
        # 追加
        echo "$entry" >> "$gitignore"
        added=true
    done <<< "$GITIGNORE_ENTRIES"
    
    if [[ "$added" == "true" ]]; then
        log_success ".gitignore を更新"
    else
        log_warn ".gitignore は更新不要（エントリ済み）"
    fi
}

# ============================================================================
# Subfunction: parse_init_arguments
# Purpose: Parse command-line arguments
# Output: Sets global variables with _PARSE_ prefix
# ============================================================================
parse_init_arguments() {
    local mode="standard"
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                mode="full"
                shift
                ;;
            --minimal)
                mode="minimal"
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                # 上で処理済み
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use -h or --help for usage information." >&2
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                echo "Use -h or --help for usage information." >&2
                exit 1
                ;;
        esac
    done

    # Set global variables
    _PARSE_mode="$mode"
    _PARSE_force="$force"
}

# ============================================================================
# Subfunction: validate_init_inputs
# Purpose: Validate Git repository and inputs
# ============================================================================
validate_init_inputs() {
    # Git リポジトリかチェック
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Git リポジトリではありません。git init を先に実行してください。"
        exit 1
    fi
}

# ============================================================================
# Subfunction: setup_config_file
# Purpose: Create .pi-runner.yaml configuration file
# Arguments: $1=force
# ============================================================================
setup_config_file() {
    local force="$1"
    
    create_file ".pi-runner.yaml" "$(generate_config_content)" "$force" || true
}

# ============================================================================
# Subfunction: setup_directories
# Purpose: Create all necessary directories
# Arguments: $1=force
# ============================================================================
setup_directories() {
    local force="$1"
    
    # .worktrees/ ディレクトリ
    if create_directory ".worktrees"; then
        # .gitkeep を作成
        create_file ".worktrees/.gitkeep" "$(generate_gitkeep_content)" "$force" || true
    fi

    # docs/plans/ ディレクトリ（計画書保存先）
    create_directory "docs/plans" || true

    # docs/decisions/ ディレクトリ（ADR保存先）
    create_directory "docs/decisions" || true
}

# ============================================================================
# Subfunction: setup_additional_files
# Purpose: Update AGENTS.md, .gitignore, and create full mode files
# Arguments: $1=mode, $2=force
# ============================================================================
setup_additional_files() {
    local mode="$1"
    local force="$2"
    
    # AGENTS.md に「既知の制約」セクションを追加
    update_agents_md

    # .gitignore 更新
    update_gitignore "$force"

    # full モードの場合は追加ファイルを作成
    if [[ "$mode" == "full" ]]; then
        echo ""
        echo "  [完全モード: 追加ファイル作成]"
        
        # agents/custom.md
        create_file "agents/custom.md" "$(generate_custom_agent_content)" "$force" || true
        
        # workflows/custom.yaml
        create_file "workflows/custom.yaml" "$(generate_custom_workflow_content)" "$force" || true
    fi
}

# ============================================================================
# Main function
# ============================================================================
main() {
    # Parse arguments (sets _PARSE_* global variables)
    parse_init_arguments "$@" || exit $?
    
    # Copy to local variables for clarity
    local mode="$_PARSE_mode"
    local force="$_PARSE_force"
    
    # Validate inputs
    validate_init_inputs

    echo "🚀 pi-issue-runner プロジェクト初期化"
    echo ""

    # Setup config file
    setup_config_file "$force"

    # minimal モードの場合はここで終了
    if [[ "$mode" == "minimal" ]]; then
        echo ""
        echo "✅ 最小初期化完了！"
        echo ""
        echo "次のステップ:"
        echo "  1. .pi-runner.yaml を編集してカスタマイズ"
        echo "  2. pi-run <issue-number> でIssueを実行"
        return 0
    fi

    # Setup directories
    setup_directories "$force"

    # Setup additional files
    setup_additional_files "$mode" "$force"

    echo ""
    echo "✅ 初期化完了！"
    echo ""
    
    # 孤立したステータスファイルをチェック
    check_orphaned_statuses
    
    echo "次のステップ:"
    echo "  1. .pi-runner.yaml を編集してカスタマイズ"
    echo "  2. pi-run <issue-number> でIssueを実行"
}

# 孤立したステータスファイルをチェックして警告
check_orphaned_statuses() {
    # ローカル色定義（出力フォーマット用）
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local NC='\033[0m'
    
    local status_dir=".worktrees/.status"
    
    # ステータスディレクトリが存在しない場合はスキップ
    [[ ! -d "$status_dir" ]] && return 0
    
    # lib/status.sh をロード可能な場合は使用
    if [[ -f "$SCRIPT_DIR/../lib/status.sh" ]]; then
        source "$SCRIPT_DIR/../lib/config.sh" 2>/dev/null || true
        source "$SCRIPT_DIR/../lib/status.sh" 2>/dev/null || true
        
        if declare -f count_orphaned_statuses &>/dev/null; then
            local count
            count="$(count_orphaned_statuses)"
            if [[ "$count" -gt 0 ]]; then
                echo -e "  ${YELLOW}⚠${NC} $count 個の孤立したステータスファイルがあります"
                echo -e "    クリーンアップするには: ${GREEN}./scripts/cleanup.sh --orphans${NC}"
                echo ""
            fi
            return 0
        fi
    fi
    
    # フォールバック: 単純なファイルカウント
    local worktree_base=".worktrees"
    local orphan_count=0
    
    for status_file in "$status_dir"/*.json; do
        [[ -f "$status_file" ]] || continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        
        # 対応するworktreeが存在するか確認
        local has_worktree=false
        for dir in "$worktree_base"/issue-"${issue_number}"-*; do
            if [[ -d "$dir" ]]; then
                has_worktree=true
                break
            fi
        done
        
        [[ "$has_worktree" == "false" ]] && orphan_count=$((orphan_count + 1))
    done
    
    if [[ "$orphan_count" -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} $orphan_count 個の孤立したステータスファイルがあります"
        echo -e "    クリーンアップするには: ${GREEN}./scripts/cleanup.sh --orphans${NC}"
        echo ""
    fi
}

main "$@"
