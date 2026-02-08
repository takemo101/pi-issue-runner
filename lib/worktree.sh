#!/usr/bin/env bash
# worktree.sh - Git worktree操作

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WORKTREE_SH_SOURCED:-}" ]]; then
    return 0
fi
_WORKTREE_SH_SOURCED="true"

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
    local config_file
    
    load_config
    
    # 設定ファイルが見つかった場合はYAML配列から直接読み取る
    if config_file="$(config_file_found 2>/dev/null)"; then
        while IFS= read -r file; do
            if [[ -n "$file" ]] && [[ -f "$file" ]]; then
                log_debug "Copying $file to worktree"
                cp "$file" "$worktree_dir/"
            fi
        done < <(yaml_get_array "$config_file" ".worktree.copy_files")
    else
        # デフォルトファイルリスト（設定ファイルがない場合）
        local default_files
        default_files="$(get_config worktree_copy_files)"
        # Use while-read loop to safely handle filenames with spaces
        # Split space-separated list into lines, then read each line
        # shellcheck disable=SC2086  # Intentional word splitting for space-separated file list
        while IFS= read -r file; do
            if [[ -n "$file" && -f "$file" ]]; then
                log_debug "Copying $file to worktree"
                cp "$file" "$worktree_dir/"
            fi
        done < <(printf '%s\n' $default_files)
    fi
}

# worktreeを削除（リトライ付き）
remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    local max_retries=3
    local retry_delay=2
    local attempt=1
    
    if [[ ! -d "$worktree_path" ]]; then
        log_error "Worktree not found: $worktree_path"
        return 1
    fi
    
    # パスを正規化（シンボリックリンクを解決）
    local normalized_path
    normalized_path="$(cd "$worktree_path" && pwd -P)" 2>/dev/null || normalized_path="$worktree_path"
    
    log_info "Removing worktree: $worktree_path"
    
    while [[ $attempt -le $max_retries ]]; do
        local cmd_result=0
        
        if [[ "$force" == "true" ]]; then
            git worktree remove --force "$worktree_path" 2>&1 || cmd_result=$?
        else
            git worktree remove "$worktree_path" 2>&1 || cmd_result=$?
        fi
        
        if [[ $cmd_result -eq 0 ]]; then
            log_info "Worktree removed successfully on attempt $attempt"
            return 0
        fi
        
        log_warn "Worktree removal failed on attempt $attempt (exit code: $cmd_result)"
        
        # worktreeがまだ存在するか正規化されたパスで確認
        local worktree_still_exists=false
        while read -r line; do
            if [[ "$line" =~ ^worktree ]]; then
                local listed_path="${line#worktree }"
                # パスを正規化して比較（シンボリックリンク対応）
                local normalized_listed_path
                if [[ -d "$listed_path" ]]; then
                    normalized_listed_path="$(cd "$listed_path" && pwd -P)" 2>/dev/null || normalized_listed_path="$listed_path"
                else
                    normalized_listed_path="$listed_path"
                fi
                if [[ "$normalized_listed_path" == "$normalized_path" ]]; then
                    worktree_still_exists=true
                    break
                fi
            fi
        done < <(git worktree list --porcelain 2>/dev/null)
        
        if [[ "$worktree_still_exists" == "true" ]] || [[ -d "$worktree_path" ]]; then
            # worktreeがまだ存在する（gitの管理下または実際のディレクトリのいずれか）
            if [[ $attempt -lt $max_retries ]]; then
                log_info "Retrying in ${retry_delay} seconds..."
                sleep $retry_delay
            fi
        else
            # worktreeは既に削除されている
            log_info "Worktree already removed"
            return 0
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to remove worktree after $max_retries attempts: $worktree_path"
    log_error "You may need to manually run: git worktree remove --force '$worktree_path'"
    return 1
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

# worktreeが使用中かどうかをチェック
# 使用中のプロセスがある場合はtrueを返す
# Usage: is_worktree_in_use <worktree_path>
is_worktree_in_use() {
    local worktree_path="$1"
    
    if [[ ! -d "$worktree_path" ]]; then
        return 1  # 存在しない = 使用中ではない
    fi
    
    # lsofで使用中かチェック（macOS/Linux両対応）
    # +d (lowercase) で直下のみチェック - 大規模ディレクトリでのパフォーマンス改善
    if command -v lsof >/dev/null 2>&1; then
        if lsof +d "$worktree_path" 2>/dev/null | grep -q .; then
            return 0  # 使用中
        fi
    fi
    
    # fuserで使用中かチェック（Linux中心）
    if command -v fuser >/dev/null 2>&1; then
        if fuser "$worktree_path" 2>/dev/null | grep -q '[0-9]'; then
            return 0  # 使用中
        fi
    fi
    
    return 1  # 使用中ではない
}

# worktreeを安全に削除（使用中チェック付き）
# Usage: safe_remove_worktree <worktree_path> [force]
safe_remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    local max_wait=30
    local waited=0
    
    if [[ ! -d "$worktree_path" ]]; then
        log_debug "Worktree does not exist: $worktree_path"
        return 0
    fi
    
    log_info "Checking if worktree is in use: $worktree_path"
    
    # 使用中の場合は待機
    while is_worktree_in_use "$worktree_path" && [[ "$waited" -lt "$max_wait" ]]; do
        log_info "Worktree is in use, waiting... (${waited}s/${max_wait}s)"
        sleep 1
        waited=$((waited + 1))
    done
    
    # それでも使用中の場合
    if is_worktree_in_use "$worktree_path"; then
        if [[ "$force" == "true" ]]; then
            log_warn "Worktree still in use after ${max_wait}s, forcing removal..."
        else
            log_error "Worktree is still in use after ${max_wait}s: $worktree_path"
            log_error "Please check running processes and try again, or use --force"
            return 1
        fi
    fi
    
    # 削除実行
    remove_worktree "$worktree_path" "$force"
}
