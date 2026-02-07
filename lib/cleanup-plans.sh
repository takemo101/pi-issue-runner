#!/usr/bin/env bash
# cleanup-plans.sh - 計画書のクリーンアップ関数

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CLEANUP_PLANS_SH_SOURCED:-}" ]]; then
    return 0
fi
_CLEANUP_PLANS_SH_SOURCED="true"

# 自身のディレクトリを取得
_CLEANUP_PLANS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config.shがまだロードされていなければロード
if ! declare -f get_config > /dev/null 2>&1; then
    source "$_CLEANUP_PLANS_LIB_DIR/config.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# 古い計画書をクリーンアップ（直近N件を保持）
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
#   $2 - keep_count: 保持する件数（省略時は設定から取得）
cleanup_old_plans() {
    local dry_run="${1:-false}"
    local keep_count="${2:-}"
    
    load_config
    
    # 保持件数を取得
    if [[ -z "$keep_count" ]]; then
        keep_count="$(get_config plans_keep_recent)"
    fi
    
    # 0の場合は全て保持（何もしない）
    if [[ "$keep_count" == "0" ]]; then
        log_info "plans.keep_recent is 0, keeping all plans"
        return 0
    fi
    
    local plans_dir
    plans_dir="$(get_config plans_dir)"
    
    if [[ ! -d "$plans_dir" ]]; then
        log_debug "No plans directory found: $plans_dir"
        return 0
    fi
    
    # 計画書ファイルを更新日時の降順でソート
    # ファイルリストを取得してからソート（OS互換性のため）
    local plan_files=""
    local unsorted_files
    unsorted_files=$(find "$plans_dir" -name "issue-*-plan.md" -type f 2>/dev/null)
    
    if [[ -n "$unsorted_files" ]]; then
        # OSを検出して適切なstatコマンドを使用
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS/BSD: stat -f '%m %N' (modification time in seconds, filename)
            plan_files=$(echo "$unsorted_files" | while IFS= read -r file; do
                local mtime
                mtime=$(stat -f '%m' "$file" 2>/dev/null)
                echo "$mtime $file"
            done | sort -rn | awk '{print $2}')
        else
            # Linux/GNU: stat -c '%Y %n' (modification time in seconds, filename)
            plan_files=$(echo "$unsorted_files" | while IFS= read -r file; do
                local mtime
                mtime=$(stat -c '%Y' "$file" 2>/dev/null)
                echo "$mtime $file"
            done | sort -rn | awk '{print $2}')
        fi
    fi
    
    if [[ -z "$plan_files" ]]; then
        log_info "No plan files found in $plans_dir"
        return 0
    fi
    
    local total_count
    total_count=$(echo "$plan_files" | wc -l | tr -d ' ')
    
    if [[ "$total_count" -le "$keep_count" ]]; then
        log_info "Found $total_count plan(s), keeping all (limit: $keep_count)"
        return 0
    fi
    
    local deleted=0
    
    # 古いファイルを削除（keep_count件より後のファイル）
    local line_num=0
    while IFS= read -r plan_file; do
        [[ -z "$plan_file" ]] && continue
        line_num=$((line_num + 1))
        
        # 直近keep_count件は保持
        if [[ "$line_num" -le "$keep_count" ]]; then
            log_debug "Keeping: $plan_file"
            continue
        fi
        
        deleted=$((deleted + 1))
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would delete: $plan_file"
        else
            log_info "Deleting old plan: $plan_file"
            rm -f "$plan_file"
        fi
    done <<< "$plan_files"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would delete $deleted old plan(s), keeping $keep_count recent"
    else
        log_info "Deleted $deleted old plan(s), kept $keep_count recent"
    fi
}

# クローズ済みIssueの計画書をクリーンアップ
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
cleanup_closed_issue_plans() {
    local dry_run="${1:-false}"
    
    load_config
    
    local plans_dir
    plans_dir="$(get_config plans_dir)"
    
    if [[ ! -d "$plans_dir" ]]; then
        log_info "No plans directory found: $plans_dir"
        return 0
    fi
    
    # gh CLIが利用可能かチェック
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install: https://cli.github.com/"
        return 1
    fi
    
    local count=0
    local plan_files
    plan_files=$(find "$plans_dir" -name "issue-*-plan.md" -type f 2>/dev/null || true)
    
    if [[ -z "$plan_files" ]]; then
        log_info "No plan files found in $plans_dir"
        return 0
    fi
    
    while IFS= read -r plan_file; do
        [[ -z "$plan_file" ]] && continue
        
        # ファイル名からIssue番号を抽出
        local filename
        filename=$(basename "$plan_file")
        local issue_number
        issue_number=$(echo "$filename" | sed -n 's/issue-\([0-9]*\)-plan\.md/\1/p')
        
        if [[ -z "$issue_number" ]]; then
            log_debug "Could not extract issue number from: $filename"
            continue
        fi
        
        # Issueの状態を確認
        local issue_state
        issue_state=$(gh issue view "$issue_number" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$issue_state" == "CLOSED" ]]; then
            count=$((count + 1))
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY-RUN] Would delete: $plan_file (Issue #$issue_number is closed)"
            else
                log_info "Deleting: $plan_file (Issue #$issue_number is closed)"
                rm -f "$plan_file"
            fi
        else
            log_debug "Keeping: $plan_file (Issue #$issue_number state: $issue_state)"
        fi
    done <<< "$plan_files"
    
    if [[ $count -eq 0 ]]; then
        log_info "No closed issue plans found to delete."
    elif [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would delete $count plan file(s)"
    else
        log_info "Deleted $count plan file(s)"
    fi
}
