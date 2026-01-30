#!/usr/bin/env bash
# run.sh - GitHub Issueからworktreeを作成してpiを起動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/log.sh"

# 依存関係チェック
check_dependencies || exit 1

# エラー時のクリーンアップを設定
setup_cleanup_trap cleanup_worktree_on_error

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number> [options]

Arguments:
    issue-number    GitHub Issue番号

Options:
    --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH   ベースブランチ（デフォルト: HEAD）
    --no-attach     セッション作成後にアタッチしない
    --reattach      既存セッションがあればアタッチ
    --force         既存セッション/worktreeを削除して再作成
    --pi-args ARGS  piに渡す追加の引数
    -h, --help      このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") 42 --no-attach
    $(basename "$0") 42 --reattach
    $(basename "$0") 42 --force
    $(basename "$0") 42 --branch custom-feature
    $(basename "$0") 42 --base develop
EOF
}

main() {
    local issue_number=""
    local custom_branch=""
    local base_branch="HEAD"
    local no_attach=false
    local reattach=false
    local force=false
    local extra_pi_args=""

    # 引数のパース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue|-i)
                issue_number="$2"
                shift 2
                ;;
            --branch|-b)
                custom_branch="$2"
                shift 2
                ;;
            --base)
                base_branch="$2"
                shift 2
                ;;
            --no-attach)
                no_attach=true
                shift
                ;;
            --reattach)
                reattach=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --pi-args)
                extra_pi_args="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$issue_number" ]]; then
                    issue_number="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_number" ]]; then
        log_error "Issue number is required"
        usage >&2
        exit 1
    fi

    # 設定読み込み
    load_config

    # セッション名を早期に生成（既存チェック用）
    local session_name
    session_name="$(generate_session_name "$issue_number")"

    # 既存セッションのチェック
    if session_exists "$session_name"; then
        if [[ "$reattach" == "true" ]]; then
            log_info "Attaching to existing session: $session_name"
            attach_session "$session_name"
            exit 0
        elif [[ "$force" == "true" ]]; then
            log_info "Removing existing session: $session_name"
            kill_session "$session_name" || true
        else
            log_error "Session '$session_name' already exists."
            log_info "Options:"
            log_info "  --reattach  Attach to existing session"
            log_info "  --force     Remove and recreate session"
            exit 1
        fi
    fi

    # 並列実行数の制限チェック（--forceの場合はスキップ）
    if [[ "$force" != "true" ]]; then
        if ! check_concurrent_limit; then
            exit 1
        fi
    fi

    # Issue情報取得
    log_info "Fetching Issue #$issue_number..."
    local issue_title
    issue_title="$(get_issue_title "$issue_number")"
    log_info "Title: $issue_title"
    
    local issue_body
    issue_body="$(get_issue_body "$issue_number" 2>/dev/null)" || issue_body=""

    # ブランチ名決定
    local branch_name
    if [[ -n "$custom_branch" ]]; then
        branch_name="$custom_branch"
    else
        branch_name="$(issue_to_branch_name "$issue_number")"
    fi
    log_info "Branch: feature/$branch_name"

    # 既存Worktreeのチェック
    local existing_worktree
    if existing_worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
        if [[ "$force" == "true" ]]; then
            log_info "Removing existing worktree: $existing_worktree"
            remove_worktree "$existing_worktree" true || true
        else
            log_error "Worktree already exists: $existing_worktree"
            log_info "Options:"
            log_info "  --force     Remove and recreate worktree"
            exit 1
        fi
    fi

    # Worktree作成
    log_info "=== Creating Worktree ==="
    local worktree_path
    worktree_path="$(create_worktree "$branch_name" "$base_branch")"
    local full_worktree_path
    full_worktree_path="$(cd "$worktree_path" && pwd)"
    
    # エラー時クリーンアップ用にworktreeを登録
    register_worktree_for_cleanup "$full_worktree_path"

    # piコマンド構築
    local pi_command
    pi_command="$(get_config pi_command)"
    local pi_args
    pi_args="$(get_config pi_args)"
    
    # プロンプトファイルを作成（シェルエスケープ問題を回避）
    local prompt_file="$full_worktree_path/.pi-prompt.md"
    cat > "$prompt_file" << EOF
Implement GitHub Issue #$issue_number

## Title
$issue_title

## Description
$issue_body

---

## Instructions

You are implementing GitHub Issue #$issue_number in an isolated worktree.

### Step 1: Understand the Issue
- Read the issue description carefully
- If unclear, check related files in the codebase

### Step 2: Implement
- Follow existing code style and patterns
- Keep changes minimal and focused
- Add/update tests if applicable

### Step 3: Verify
- Run unit tests: \`./test/*_test.sh\` (if modified lib/ files)
- Run Bats tests: \`bats tests/\` (if Bats installed)
- Check syntax for all changed files: \`bash -n <file>\`
- If no tests exist for modified code, consider adding them

### Step 4: Commit & Push
\`\`\`bash
git add -A
git commit -m "<type>: <description>

Closes #$issue_number"
git push -u origin feature/$branch_name
\`\`\`

### Step 5: Self-Review

Before creating a PR, perform a multi-perspective self-review from different personas.

#### Persona-Based Review Criteria (10 points total)

**🔧 Senior Engineer** - Code quality, design patterns, edge cases
| Criterion | Points | Focus |
|-----------|--------|-------|
| Correctness & Completeness | 3 | Does the code solve the issue correctly? Are all requirements implemented? |
| Code Quality | 2 | Is the code clean, readable, and follows existing patterns? |

**🧪 QA Engineer** - Test coverage, edge cases, error handling
| Criterion | Points | Focus |
|-----------|--------|-------|
| Testing | 2 | Are there adequate tests? Do all tests pass? Are edge cases covered? |

**📚 Technical Writer** - Documentation, clarity, consistency
| Criterion | Points | Focus |
|-----------|--------|-------|
| Documentation Consistency | 2 | Are all docs (README, SKILL, AGENTS, SPECIFICATION) consistent with the changes? |

**All Personas**
| Criterion | Points | Focus |
|-----------|--------|-------|
| No Regressions | 1 | Does the change break existing functionality? |

#### Implementation Completeness Check
Before scoring, verify these items:
- [ ] All requirements from the issue are implemented
- [ ] All edge cases are handled
- [ ] Error handling is complete
- [ ] All affected files are updated
- [ ] No TODO/FIXME left unresolved

#### Consistency Check Items
- If script options changed → Update option descriptions in all docs
- If new files added → Update directory structure explanations
- If configuration items changed → Update configuration examples
- If dependencies added → Update prerequisites section

#### Consistency Check Commands
\`\`\`bash
# Check option consistency across docs
./scripts/run.sh --help
grep -E "--[a-z]+" README.md SKILL.md docs/SPECIFICATION.md

# Check directory structure consistency
ls -la scripts/ lib/
grep -A20 "ディレクトリ構造" README.md AGENTS.md docs/SPECIFICATION.md

# Check for unresolved TODOs
grep -rn "TODO\|FIXME" --include="*.sh" --include="*.md" .
\`\`\`

#### Scoring
- Review your changes: \`git diff HEAD~1\`
- Score each criterion from each persona's perspective
- Calculate total and check Implementation Completeness
- **If score >= 9**: Proceed to Step 6
- **If score < 9**: Fix the issues and repeat Step 5

#### Output Format
\`\`\`
## Self-Review Score: X/10

### 🔧 Senior Engineer Review
| Criterion | Score | Notes |
|-----------|-------|-------|
| Correctness & Completeness | X/3 | ... |
| Code Quality | X/2 | ... |

### 🧪 QA Engineer Review
| Criterion | Score | Notes |
|-----------|-------|-------|
| Testing | X/2 | ... |

### 📚 Technical Writer Review
| Criterion | Score | Notes |
|-----------|-------|-------|
| Documentation Consistency | X/2 | ... |

### All Personas
| Criterion | Score | Notes |
|-----------|-------|-------|
| No Regressions | X/1 | ... |

### Implementation Completeness
- [x] All requirements from the issue are implemented
- [x] All edge cases are handled
- [x] Error handling is complete
- [x] All affected files are updated
- [x] No TODO/FIXME left unresolved

### Issues to Fix (if score < 9)
- ...
\`\`\`

### Step 6: Create & Merge PR
\`\`\`bash
gh pr create --title "<type>: <short description>" --body "## Summary
Closes #$issue_number

## Changes
- <list key changes made>
- <files modified and why>

## Testing
- <how the changes were tested>
- <test commands run>"
gh pr merge --merge --delete-branch
\`\`\`

### Commit Types
- feat: New feature
- fix: Bug fix  
- docs: Documentation
- refactor: Code refactoring
- test: Adding tests
- chore: Maintenance

### On Error
- If tests fail, fix the issue before committing
- If PR merge fails, report the error
EOF
    
    # piにプロンプトファイルを渡す（@でファイル参照）
    local full_command="$pi_command $pi_args $extra_pi_args @\"$prompt_file\""

    # tmuxセッション作成
    log_info "=== Starting Pi Session ==="
    create_session "$session_name" "$full_worktree_path" "$full_command"
    
    # セッション作成成功 - クリーンアップ対象から除外
    unregister_worktree_for_cleanup

    log_info "=== Summary ==="
    log_info "Issue:     #$issue_number - $issue_title"
    log_info "Worktree:  $worktree_path"
    log_info "Branch:    feature/$branch_name"
    log_info "Session:   $session_name"

    # アタッチ
    if [[ "$no_attach" == "false" ]]; then
        local start_in_session
        start_in_session="$(get_config tmux_start_in_session)"
        if [[ "$start_in_session" == "true" ]]; then
            log_info "Attaching to session..."
            attach_session "$session_name"
        fi
    else
        log_info "Session started in background."
        log_info "Attach with: $(basename "$0")/../attach.sh $session_name"
    fi
}

main "$@"
