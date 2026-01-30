#!/usr/bin/env bash
# worktree.sh - Git worktree操作

set -euo pipefail

# 現在のディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# configを読み込み
source "$SCRIPT_DIR/config.sh"

# worktreeを作成
create_worktree() {
    local branch_name="$1"
    local base_branch="${2:-HEAD}"
    local worktree_dir
    
    load_config
    worktree_dir="$(get_config worktree_base_dir)/$branch_name"
    
    # 既存のworktreeチェック
    if [[ -d "$worktree_dir" ]]; then
        echo "Error: Worktree already exists: $worktree_dir" >&2
        return 1
    fi
    
    # ベースディレクトリ作成
    mkdir -p "$(get_config worktree_base_dir)"
    
    # worktree作成
    echo "Creating worktree: $worktree_dir (branch: feature/$branch_name)" >&2
    
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
            echo "Copying $file to worktree" >&2
            cp "$file" "$worktree_dir/"
        fi
    done
}

# worktreeを削除
remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: Worktree not found: $worktree_path" >&2
        return 1
    fi
    
    echo "Removing worktree: $worktree_path"
    
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
    
    git worktree list --porcelain | while read -r line; do
        if [[ "$line" =~ ^worktree ]]; then
            local path="${line#worktree }"
            if [[ "$path" == *"$base_dir"* ]]; then
                echo "$path"
            fi
        fi
    done
}

# worktreeのブランチを取得
get_worktree_branch() {
    local worktree_path="$1"
    
    git worktree list --porcelain | while read -r line; do
        if [[ "$line" == "worktree $worktree_path" ]]; then
            while read -r subline; do
                if [[ "$subline" =~ ^branch ]]; then
                    echo "${subline#branch refs/heads/}"
                    return
                fi
                [[ -z "$subline" ]] && break
            done
        fi
    done
}

# Issue番号からworktreeパスを検索
find_worktree_by_issue() {
    local issue_number="$1"
    
    load_config
    local base_dir
    base_dir="$(get_config worktree_base_dir)"
    
    # issue-XXX-* パターンで検索
    local pattern="issue-${issue_number}"
    
    for dir in "$base_dir"/*; do
        if [[ -d "$dir" && "$(basename "$dir")" == $pattern* ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    return 1
}
