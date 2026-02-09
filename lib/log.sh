#!/usr/bin/env bash
# log.sh - ログ出力とエラーハンドリング

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_LOG_SH_SOURCED:-}" ]]; then
    return 0
fi
_LOG_SH_SOURCED="true"

# ログレベル: DEBUG < INFO < WARN < ERROR < QUIET
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# カラー出力（TTYの場合のみ）
if [[ -t 2 ]]; then
    _LOG_COLOR_RESET='\033[0m'
    _LOG_COLOR_DEBUG='\033[0;36m'  # Cyan
    _LOG_COLOR_INFO='\033[0;32m'   # Green
    _LOG_COLOR_WARN='\033[0;33m'   # Yellow
    _LOG_COLOR_ERROR='\033[0;31m'  # Red
else
    _LOG_COLOR_RESET=''
    _LOG_COLOR_DEBUG=''
    _LOG_COLOR_INFO=''
    _LOG_COLOR_WARN=''
    _LOG_COLOR_ERROR=''
fi

# ログレベルを数値に変換
_log_level_to_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        QUIET) echo 4 ;;
        *)     echo 1 ;;  # デフォルトはINFO
    esac
}

# メインログ関数
log() {
    local level="$1"
    shift
    local message="$*"
    
    local current_level
    current_level="$(_log_level_to_num "$LOG_LEVEL")"
    local msg_level
    msg_level="$(_log_level_to_num "$level")"
    
    # 現在のレベル以上のメッセージのみ出力
    if [[ $msg_level -lt $current_level ]]; then
        return 0
    fi
    
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    local color=""
    case "$level" in
        DEBUG) color="$_LOG_COLOR_DEBUG" ;;
        INFO)  color="$_LOG_COLOR_INFO" ;;
        WARN)  color="$_LOG_COLOR_WARN" ;;
        ERROR) color="$_LOG_COLOR_ERROR" ;;
    esac
    
    printf "%b[%s] [%s]%b %s\n" "$color" "$timestamp" "$level" "$_LOG_COLOR_RESET" "$message" >&2
}

# 便利関数
log_debug() { log DEBUG "$@"; }
log_info()  { log INFO "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_success() { log_info "$@"; }  # Alias for compatibility with init.sh

# ログレベルを設定
set_log_level() {
    local level="$1"
    case "$level" in
        DEBUG|INFO|WARN|ERROR|QUIET)
            LOG_LEVEL="$level"
            ;;
        *)
            log_warn "Unknown log level: $level, using INFO"
            LOG_LEVEL="INFO"
            ;;
    esac
}

# verbose/quietオプションの処理
enable_verbose() {
    LOG_LEVEL="DEBUG"
}

enable_quiet() {
    LOG_LEVEL="ERROR"
}

# Note: cleanup trap functions (setup_cleanup_trap, cleanup_worktree_on_error, etc.)
# have been moved to lib/cleanup-trap.sh
