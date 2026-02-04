#!/usr/bin/env bash
# ci-fix.sh - CI失敗検出・自動修正機能
#
# このライブラリはCI失敗を検出して自動修正を試行します。
# 対応する失敗タイプ:
#   - Lint/Clippy: cargo clippy --fix
#   - Format: cargo fmt
#   - Test失敗: AI解析による修正
#   - ビルドエラー: AI解析による修正
#
# 【重要】使用状況について:
#   このファイルは他のスクリプトから直接 source されるのではなく、
#   scripts/ci-fix-helper.sh というラッパースクリプトを介して使用されます。
#   これは意図的な設計で、ライブラリ層とCLIインターフェース層を分離しています。
#
# 使用フロー:
#   agents/ci-fix.md (エージェントテンプレート)
#     → scripts/ci-fix-helper.sh (CLIラッパー)
#       → lib/ci-fix.sh (このライブラリ)
#
# 直接使用する場合:
#   source lib/ci-fix.sh
#   handle_ci_failure 42 123 /path/to/worktree
#
# 依存モジュール:
#   - lib/log.sh: ログ出力
#   - lib/github.sh: GitHub CLI操作
#   - lib/ci-monitor.sh: CI状態監視
#   - lib/ci-classifier.sh: 失敗タイプ分類
#   - lib/ci-retry.sh: リトライ管理
#
# 関連ファイル:
#   - scripts/ci-fix-helper.sh: このライブラリのCLIラッパー
#   - agents/ci-fix.md: ci-fixエージェントテンプレート
#   - workflows/ci-fix.yaml: ci-fixワークフロー定義

set -euo pipefail

__CI_FIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$__CI_FIX_LIB_DIR/log.sh"
source "$__CI_FIX_LIB_DIR/github.sh"
source "$__CI_FIX_LIB_DIR/ci-monitor.sh"
source "$__CI_FIX_LIB_DIR/ci-classifier.sh"
source "$__CI_FIX_LIB_DIR/ci-retry.sh"

# ===================
# プロジェクトタイプ検出
# ===================

# プロジェクトタイプを検出
# Usage: detect_project_type [worktree_path]
# Returns: rust | node | python | go | bash | unknown
detect_project_type() {
    local worktree_path="${1:-.}"
    
    # Rust: Cargo.toml の存在
    if [[ -f "$worktree_path/Cargo.toml" ]]; then
        echo "rust"
        return 0
    fi
    
    # Node/JavaScript: package.json の存在
    if [[ -f "$worktree_path/package.json" ]]; then
        echo "node"
        return 0
    fi
    
    # Python: pyproject.toml または setup.py の存在
    if [[ -f "$worktree_path/pyproject.toml" ]] || [[ -f "$worktree_path/setup.py" ]]; then
        echo "python"
        return 0
    fi
    
    # Go: go.mod の存在
    if [[ -f "$worktree_path/go.mod" ]]; then
        echo "go"
        return 0
    fi
    
    # Bash: *.bats ファイルまたは test/test_helper.bash の存在
    # shellcheck disable=SC2144
    if ls "$worktree_path"/*.bats &>/dev/null || [[ -f "$worktree_path/test/test_helper.bash" ]]; then
        echo "bash"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# ===================
# 自動修正実行
# ===================

# 自動修正を試行
# Usage: try_auto_fix <failure_type> [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_auto_fix() {
    local failure_type="$1"
    local worktree_path="${2:-.}"
    
    log_info "Attempting auto-fix for: $failure_type"
    
    case "$failure_type" in
        "$FAILURE_TYPE_LINT")
            try_fix_lint "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_FORMAT")
            try_fix_format "$worktree_path"
            return $?
            ;;
        "$FAILURE_TYPE_TEST")
            # テスト失敗はAI修正が必要
            log_info "Test failures require AI-based fixing"
            return 2
            ;;
        "$FAILURE_TYPE_BUILD")
            # ビルドエラーはAI修正が必要
            log_info "Build errors require AI-based fixing"
            return 2
            ;;
        *)
            log_warn "Unknown failure type: $failure_type"
            return 2
            ;;
    esac
}

# Lint修正を試行（汎用版）
# Usage: try_fix_lint [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_fix_lint() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix lint issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    log_info "Detected project type: $project_type"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        case "$project_type" in
            rust)
                if ! command -v cargo &> /dev/null; then
                    log_error "cargo not found. Cannot auto-fix lint issues."
                    return 1
                fi
                if cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features 2>&1; then
                    log_info "Clippy fix applied successfully"
                    return 0
                else
                    log_error "Clippy fix failed"
                    return 1
                fi
                ;;
            node)
                # npm scriptsにlint:fixがあればそれを使用、なければeslintを試行
                if grep -q '"lint:fix"' package.json 2>/dev/null; then
                    log_info "Running npm run lint:fix..."
                    if npm run lint:fix 2>&1; then
                        log_info "Lint fix applied successfully"
                        return 0
                    else
                        log_warn "npm run lint:fix failed"
                        return 1
                    fi
                elif command -v npx &> /dev/null; then
                    log_info "Trying npx eslint --fix..."
                    if npx eslint --fix . 2>&1; then
                        log_info "ESLint fix applied successfully"
                        return 0
                    else
                        log_warn "ESLint fix failed or not configured"
                        return 2  # 自動修正不可
                    fi
                else
                    log_warn "No linter found for Node project"
                    return 2  # 自動修正不可
                fi
                ;;
            python)
                # autopep8で自動修正を試行
                if command -v autopep8 &> /dev/null; then
                    log_info "Running autopep8..."
                    if autopep8 --in-place --aggressive --aggressive --recursive . 2>&1; then
                        log_info "autopep8 fix applied successfully"
                        return 0
                    else
                        log_error "autopep8 fix failed"
                        return 1
                    fi
                else
                    log_warn "autopep8 not found. Install with: pip install autopep8"
                    return 2  # 自動修正不可
                fi
                ;;
            go)
                # golangci-lintがあれば使用
                if command -v golangci-lint &> /dev/null; then
                    log_info "Running golangci-lint run --fix..."
                    if golangci-lint run --fix 2>&1; then
                        log_info "golangci-lint fix applied successfully"
                        return 0
                    else
                        log_warn "golangci-lint fix failed"
                        return 1
                    fi
                else
                    log_warn "golangci-lint not found. Install from: https://golangci-lint.run/usage/install/"
                    return 2  # 自動修正不可
                fi
                ;;
            bash)
                # ShellCheckは自動修正をサポートしていない
                log_warn "Bash linting (shellcheck) does not support auto-fix"
                return 2  # 自動修正不可
                ;;
            *)
                log_warn "Unknown project type. Cannot auto-fix lint."
                return 2  # 自動修正不可
                ;;
        esac
    )
}

# フォーマット修正を試行（汎用版）
# Usage: try_fix_format [worktree_path]
# Returns: 0=修正成功, 1=修正失敗, 2=自動修正不可
try_fix_format() {
    local worktree_path="${1:-.}"
    
    log_info "Trying to fix format issues..."
    
    # プロジェクトタイプを検出
    local project_type
    project_type=$(detect_project_type "$worktree_path")
    
    log_info "Detected project type: $project_type"
    
    # worktreeパスに移動して実行
    (
        cd "$worktree_path" || return 1
        
        case "$project_type" in
            rust)
                if ! command -v cargo &> /dev/null; then
                    log_error "cargo not found. Cannot auto-fix format issues."
                    return 1
                fi
                if cargo fmt --all 2>&1; then
                    log_info "Format fix applied successfully"
                    return 0
                else
                    log_error "Format fix failed"
                    return 1
                fi
                ;;
            node)
                # npm scriptsにformatがあればそれを使用、なければprettierを試行
                if grep -q '"format"' package.json 2>/dev/null; then
                    log_info "Running npm run format..."
                    if npm run format 2>&1; then
                        log_info "Format fix applied successfully"
                        return 0
                    else
                        log_warn "npm run format failed"
                        return 1
                    fi
                elif command -v npx &> /dev/null; then
                    log_info "Trying npx prettier --write..."
                    if npx prettier --write . 2>&1; then
                        log_info "Prettier fix applied successfully"
                        return 0
                    else
                        log_warn "Prettier fix failed or not configured"
                        return 2  # 自動修正不可
                    fi
                else
                    log_warn "No formatter found for Node project"
                    return 2  # 自動修正不可
                fi
                ;;
            python)
                # blackを優先、なければautopep8
                if command -v black &> /dev/null; then
                    log_info "Running black..."
                    if black . 2>&1; then
                        log_info "black fix applied successfully"
                        return 0
                    else
                        log_error "black fix failed"
                        return 1
                    fi
                elif command -v autopep8 &> /dev/null; then
                    log_info "Running autopep8..."
                    if autopep8 --in-place --recursive . 2>&1; then
                        log_info "autopep8 fix applied successfully"
                        return 0
                    else
                        log_error "autopep8 fix failed"
                        return 1
                    fi
                else
                    log_warn "No formatter found for Python project (black or autopep8)"
                    return 2  # 自動修正不可
                fi
                ;;
            go)
                if ! command -v gofmt &> /dev/null; then
                    log_error "gofmt not found. Cannot auto-fix format issues."
                    return 1
                fi
                if gofmt -w . 2>&1; then
                    log_info "gofmt fix applied successfully"
                    return 0
                else
                    log_error "gofmt fix failed"
                    return 1
                fi
                ;;
            bash)
                # shfmtがあれば使用
                if command -v shfmt &> /dev/null; then
                    log_info "Running shfmt..."
                    if shfmt -w -i 4 . 2>&1; then
                        log_info "shfmt fix applied successfully"
                        return 0
                    else
                        log_error "shfmt fix failed"
                        return 1
                    fi
                else
                    log_warn "shfmt not found. Install from: https://github.com/mvdan/sh"
                    return 2  # 自動修正不可
                fi
                ;;
            *)
                log_warn "Unknown project type. Cannot auto-fix format."
                return 2  # 自動修正不可
                ;;
        esac
    )
}

# ローカル検証を実行
# Usage: run_local_validation [worktree_path]
# Returns: 0=検証成功, 1=検証失敗
run_local_validation() {
    local worktree_path="${1:-.}"
    
    log_info "Running local validation..."
    
    if ! command -v cargo &> /dev/null; then
        log_warn "cargo not found. Skipping local validation."
        return 0
    fi
    
    (
        cd "$worktree_path" || return 1
        
        # clippyチェック
        log_info "Running cargo clippy..."
        if ! cargo clippy --all-targets --all-features -- -D warnings 2>&1; then
            log_error "Clippy check failed"
            return 1
        fi
        
        # テスト実行（簡易版）
        log_info "Running cargo test..."
        if ! cargo test --lib 2>&1; then
            log_error "Test failed"
            return 1
        fi
        
        log_info "Local validation passed"
        return 0
    )
}

# ===================
# エスカレーション処理
# ===================

# PRをDraft化して手動対応にエスカレート
# Usage: escalate_to_manual <pr_number> <failure_log>
escalate_to_manual() {
    local pr_number="$1"
    local failure_log="${2:-}"
    
    log_warn "Escalating to manual handling for PR #$pr_number"
    
    # PRをDraft化
    mark_pr_as_draft "$pr_number"
    
    # 失敗ログをコメント追加（要約版）
    local comment="## 🤖 CI自動修正: エスカレーション\n\n"
    comment+="CI失敗の自動修正が困難なため、手動対応が必要です。\n\n"
    comment+="### 失敗サマリー\n"
    comment+="\`\`\`\n"
    # ログの先頭500文字のみ追加
    comment+="$(echo "$failure_log" | head -c 500)"
    comment+="\n\`\`\`\n\n"
    comment+="### 対応が必要な項目\n"
    comment+="- [ ] 失敗ログの確認\n"
    comment+="- [ ] 問題の修正\n"
    comment+="- [ ] CIの再実行\n"
    
    add_pr_comment "$pr_number" "$comment"
    
    return 0
}

# PRをDraft化
# Usage: mark_pr_as_draft <pr_number>
mark_pr_as_draft() {
    local pr_number="$1"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot mark PR as draft."
        return 1
    fi
    
    log_info "Marking PR #$pr_number as draft"
    
    # PRをDraft化（gh CLIのバージョンによって方法が異なる）
    if gh pr ready "$pr_number" --undo 2>/dev/null; then
        log_info "PR marked as draft"
        return 0
    else
        # 代替方法: PRを編集してDraftに
        log_warn "Could not mark PR as draft (may require different gh CLI version)"
        return 1
    fi
}

# PRにコメント追加
# Usage: add_pr_comment <pr_number> <comment>
add_pr_comment() {
    local pr_number="$1"
    local comment="$2"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot add comment."
        return 1
    fi
    
    log_info "Adding comment to PR #$pr_number"
    
    if echo "$comment" | gh pr comment "$pr_number" -F - 2>/dev/null; then
        log_info "Comment added successfully"
        return 0
    else
        log_warn "Failed to add comment"
        return 1
    fi
}

# ===================
# メイン処理
# ===================

# CI失敗を検出して自動修正を試行
# Usage: handle_ci_failure <issue_number> <pr_number> [worktree_path]
# Returns: 0=修正成功・マージ可能, 1=修正失敗・エスカレーション必要, 2=致命的エラー
handle_ci_failure() {
    local issue_number="$1"
    local pr_number="$2"
    local worktree_path="${3:-.}"
    
    log_info "Handling CI failure for Issue #$issue_number, PR #$pr_number"
    
    # リトライ回数チェック
    if ! should_continue_retry "$issue_number"; then
        log_warn "Maximum retries reached. Escalating..."
        escalate_to_manual "$pr_number" "Maximum retry count exceeded"
        return 1
    fi
    
    # リトライ回数をインクリメント
    increment_retry_count "$issue_number"
    
    # 失敗ログを取得
    local failure_log
    failure_log=$(get_failed_ci_logs "$pr_number" || echo "")
    
    if [[ -z "$failure_log" ]]; then
        log_warn "Could not retrieve failure logs"
        escalate_to_manual "$pr_number" "Failed to retrieve CI logs"
        return 1
    fi
    
    # 失敗タイプを分類
    local failure_type
    failure_type=$(classify_ci_failure "$failure_log")
    log_info "Detected failure type: $failure_type"
    
    # 自動修正を試行
    local fix_result
    try_auto_fix "$failure_type" "$worktree_path"
    fix_result=$?
    
    case $fix_result in
        0)
            # 自動修正成功
            log_info "Auto-fix applied successfully"
            
            # ローカル検証
            if run_local_validation "$worktree_path"; then
                return 0
            else
                log_warn "Local validation failed after auto-fix"
                return 1
            fi
            ;;
        2)
            # AI修正が必要
            log_info "Auto-fix not available for this failure type. Requires AI fixing."
            return 1
            ;;
        *)
            # 修正失敗
            log_error "Auto-fix failed"
            return 1
            ;;
    esac
}
