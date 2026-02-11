#!/usr/bin/env bash
# lock.sh - Cleanup lock management
# Extracted from status.sh (Issue #1430)
# Prevents race conditions between sweep.sh and watch-session.sh

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_LOCK_SH_SOURCED:-}" ]]; then
    return 0
fi
_LOCK_SH_SOURCED="true"

# 自身のディレクトリを取得
_LOCK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# status.shの関数（get_status_dir, init_status_dir）に依存
if ! declare -f get_status_dir > /dev/null 2>&1; then
    source "$_LOCK_LIB_DIR/status.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# =============================================================================
# Cleanup Lock Management (Issue #1077)
# Prevents race conditions between sweep.sh and watch-session.sh
# =============================================================================

# Acquire cleanup lock for an issue
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (成功), 1 (ロック取得失敗)
acquire_cleanup_lock() {
    local issue_number="$1"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    # mkdir を使ったアトミックなロック取得
    if mkdir "$lock_file" 2>/dev/null; then
        echo $$ > "$lock_file/pid"
        log_debug "Acquired cleanup lock for issue #$issue_number (PID: $$)"
        return 0
    fi
    
    # 既にロック済み - stale lockチェック
    local pid
    pid=$(cat "$lock_file/pid" 2>/dev/null) || pid=""
    
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        # stale lock - PIDファイルを上書きしてロック所有権を主張
        # rm + mkdir ではなく、PIDの上書きで原子的に所有権を移転（TOCTOU回避）
        if echo $$ > "$lock_file/pid" 2>/dev/null; then
            # PID書き込み成功後、実際に自分のPIDか再確認（別プロセスも上書きした可能性）
            local new_pid
            new_pid=$(cat "$lock_file/pid" 2>/dev/null) || new_pid=""
            if [[ "$new_pid" == "$$" ]]; then
                log_debug "Acquired cleanup lock for issue #$issue_number (took over stale lock from PID: $pid)"
                return 0
            fi
            log_debug "Failed to acquire cleanup lock for issue #$issue_number (race condition, got PID: $new_pid)"
            return 1
        fi
        # PIDファイルへの書き込みに失敗した場合はディレクトリごと作り直す
        rm -rf "$lock_file"
        if mkdir "$lock_file" 2>/dev/null; then
            echo $$ > "$lock_file/pid"
            log_debug "Acquired cleanup lock for issue #$issue_number after stale cleanup (PID: $$)"
            return 0
        fi
        log_debug "Failed to acquire cleanup lock for issue #$issue_number (race condition during recovery)"
        return 1
    fi
    
    log_debug "Failed to acquire cleanup lock for issue #$issue_number (held by PID: $pid)"
    return 1
}

# Release cleanup lock for an issue
# 引数:
#   $1 - issue_number: Issue番号
release_cleanup_lock() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    if [[ -d "$lock_file" ]]; then
        # 自分のロックか確認
        local lock_pid
        lock_pid=$(cat "$lock_file/pid" 2>/dev/null) || lock_pid=""
        
        # Check if it's our lock or the process is dead
        local can_release=false
        if [[ "$lock_pid" == "$$" ]]; then
            can_release=true
        elif [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            can_release=true
        fi
        
        if [[ "$can_release" == "true" ]]; then
            # 自分のロック、または既にプロセスが死んでいる場合のみ削除
            rm -rf "$lock_file"
            log_debug "Released cleanup lock for issue #$issue_number"
        else
            log_warn "Cannot release cleanup lock for issue #$issue_number: owned by PID $lock_pid"
        fi
    else
        log_debug "No cleanup lock to release for issue #$issue_number"
    fi
}

# Check if cleanup lock exists for an issue
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (ロック存在), 1 (ロック無し)
is_cleanup_locked() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    if [[ -d "$lock_file" ]]; then
        # PIDファイルが存在し、プロセスが生きているか確認
        local pid
        pid=$(cat "$lock_file/pid" 2>/dev/null) || pid=""
        
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # ロック有効
        else
            # stale lock
            log_debug "Detected stale cleanup lock for issue #$issue_number (PID: $pid)"
            return 1
        fi
    fi
    
    return 1  # ロック無し
}
