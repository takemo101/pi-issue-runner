#!/usr/bin/env bash
# worktree.sh - Git worktree操作

set -euo pipefail

# 現在のディレクトリを取得
_WORKTREE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# configとlogを読み込み
source "$_WORKTREE_LIB_DIR/config.sh"
source "$_WORKTREE_LIB_DIR/log.sh"

# worktreeを作成
create_worktree() {
    local branch_name="$1"
    local base_branch="${2:-HEAD}"
    local worktree_dir
    
    load_config
    worktree_dir="$(get_config worktree_base_dir)/$branch_name"
    
    # 既存のworktreeチェック
    if [[ -d "$worktree_dir" ]]; then
        log_error "Worktree already exists: $worktree_dir"
        return 1
    fi
    
    # ベースディレクトリ作成
    mkdir -p "$(get_config worktree_base_dir)"
    
    # worktree作成
    log_info "Creating worktree: $worktree_dir (branch: feature/$branch_name)"
    
    if git rev-parse --verify "feature/$branch_name" &> /dev/null; then
        # ブランチが既に存在する場合
        git worktree add "$worktree_dir" "feature/$branch_name" >&2
    else
        # 新規ブランチ作成
        git worktree add -b "feature/$branch_name" "$worktree_dir" "$base_branch" >&2
    fi
    
    # ファイルのコピー
    copy_files_to_worktree "$worktree_dir"
    
    # 最後にパスのみを標準出力に出力
    echo "$worktree_dir"
}

# 環境ファイルをworktreeにコピー
copy_files_to_worktree() {
    local worktree_dir="$1"
    local files
    
    load_config
    files="$(get_config worktree_copy_files)"
    
    for file in $files; do
        if [[ -f "$file" ]]; then
            log_debug "Copying $file to worktree"
            cp "$file" "$worktree_dir/"
        fi
    done
}

# worktreeを削除
remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    
    if [[ ! -d "$worktree_path" ]]; then
        log_error "Worktree not found: $worktree_path"
        return 1
    fi
    
    log_info "Removing worktree: $worktree_path"
    
    if [[ "$force" == "true" ]]; then
        git worktree remove --force "$worktree_path"
    else
        git worktree remove "$worktree_path"
    fi
}

# worktree一覧を取得
list_worktrees() {
    load_config
    local base_dir
    base_dir="$(get_config worktree_base_dir)"
    
    # プロセス置換を使用してサブシェルを回避
    while read -r line; do
        if [[ "$line" =~ ^worktree ]]; then
            local path="${line#worktree }"
            if [[ "$path" == *"$base_dir"* ]]; then
                echo "$path"
            fi
        fi
    done < <(git worktree list --porcelain)
}

# worktreeのブランチを取得
get_worktree_branch() {
    local worktree_path="$1"
    local found_worktree=false
    local branch=""
    
    # パスを正規化（macOSでの/var -> /private/var シンボリックリンク対応）
    if [[ -d "$worktree_path" ]]; then
        worktree_path="$(cd "$worktree_path" && pwd -P)"
    fi
    
    # プロセス置換を使用してサブシェルを回避
    while read -r line; do
        if [[ "$found_worktree" == "true" ]]; then
            if [[ "$line" =~ ^branch ]]; then
                branch="${line#branch refs/heads/}"
                break
            fi
            # 空行でworktreeエントリ終了
            [[ -z "$line" ]] && break
        elif [[ "$line" == "worktree $worktree_path" ]]; then
            found_worktree=true
        fi
    done < <(git worktree list --porcelain)
    
    [[ -n "$branch" ]] && echo "$branch"
}

# Issue番号からworktreeパスを検索
find_worktree_by_issue() {
    local issue_number="$1"
    
    load_config
    local base_dir
    base_dir="$(get_config worktree_base_dir)"
    
    # issue-{number}* パターンで検索（ブランチ名にタイトルが含まれる場合に対応）
    local pattern="issue-${issue_number}"
    
    for dir in "$base_dir"/*; do
        if [[ -d "$dir" && "$(basename "$dir")" == $pattern* ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    return 1
}
