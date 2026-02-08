#!/usr/bin/env bash
# daemon.sh - プロセスをデーモン化（親プロセスグループから分離）
#
# Issue #553: run-batch.sh経由で起動したwatcherがタイムアウト時に死ぬ問題の解決
# setsidがない環境（macOSなど）でも動作するように、プロセスグループを分離する

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_DAEMON_SH_SOURCED:-}" ]]; then
    return 0
fi
_DAEMON_SH_SOURCED="true"

# コマンドをデーモン化して実行
# Usage: daemonize <log_file> <command> [args...]
# Returns: デーモンプロセスのPID（setsid使用時）、または子シェルのPID（互換モード時）
# 注: macOSでは孫プロセスのPIDを直接取得できないため、pgrep等で検索が必要な場合がある
daemonize() {
    local log_file="$1"
    shift
    
    if [[ $# -eq 0 ]]; then
        echo "Usage: daemonize <log_file> <command> [args...]" >&2
        return 1
    fi
    
    # Linuxでsetsidが利用可能な場合はそれを使用（最も確実な方法）
    if command -v setsid &> /dev/null; then
        setsid "$@" >> "$log_file" 2>&1 &
        echo "$!"
        return 0
    fi
    
    # macOS/その他: 互換モードでデーモン化
    # nohup + サブシェル + 即時バックグラウンド実行 + disown の組み合わせ
    # これにより、親プロセスが終了しても子プロセスは生き続ける
    local pid_file
    pid_file="$(mktemp "${TMPDIR:-/tmp}/daemon_pid.XXXXXX")"
    # RETURN trapでPIDファイルを確実にクリーンアップ（異常終了時も実行される）
    trap 'rm -f "$pid_file" 2>/dev/null' RETURN
    
    # サブシェル内で実行し、即座にバックグラウンド化
    # nohupでSIGHUPを無視し、標準入出力を適切にリダイレクト
    (
        # SIGHUPを無視（最優先で設定）
        trap '' HUP
        
        # 標準入出力を閉じる（またはリダイレクト）
        exec 0</dev/null
        exec 1>>"$log_file"
        exec 2>&1
        
        # バックグラウンドで実行しPIDを記録
        "$@" &
        local bg_pid=$!
        echo "$bg_pid" > "$pid_file"
        
        # jobsテーブルから削除（親シェルに影響与えない）
        # Note: サブシェル内では disown が失敗する場合があるが、
        # trap '' HUP で SIGHUP を無視しているため問題ない
        disown %1 2>/dev/null || disown "$bg_pid" 2>/dev/null || true
        
        # 親が先に終了しても子プロセスは継続
        # このサブシェルはすぐに終了するが、バックグラウンドの子は生き続ける
    ) &
    
    local wrapper_pid=$!
    
    # サブシェルがPIDを書き込むのを待つ
    local attempts=0
    local max_attempts=100  # 最大10秒待機（高負荷時のタイムアウト対策）
    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -s "$pid_file" ]]; then
            break
        fi
        sleep 0.1
        ((attempts++)) || true
    done
    
    # 子プロセスのPIDを読み込み
    local child_pid=""
    if [[ -s "$pid_file" ]]; then
        child_pid="$(cat "$pid_file" 2>/dev/null)"
    fi
    
    # PIDファイルを削除
    rm -f "$pid_file"
    
    # サブシェルが終了するのを待つ
    wait "$wrapper_pid" 2>/dev/null || true
    
    if [[ -n "$child_pid" ]] && [[ "$child_pid" =~ ^[0-9]+$ ]]; then
        echo "$child_pid"
    else
        # PIDが取得できなかった場合は、pgrepでプロセスを検索（フォールバック）
        # wrapper PIDは既に再利用されている可能性があるため、コマンドパターンで検索
        echo "Warning: PID file timeout. Attempting to find process by pattern..." >&2
        
        # コマンドラインからプロセスを検索
        local cmd_pattern="${*}"
        local found_pid
        found_pid=$(find_daemon_pid "$cmd_pattern" 2>/dev/null || echo "")
        
        if [[ -n "$found_pid" ]] && [[ "$found_pid" =~ ^[0-9]+$ ]]; then
            echo "$found_pid"
        else
            # プロセスが見つからない場合はエラーを報告
            echo "Error: Failed to retrieve daemon PID" >&2
            return 1
        fi
    fi
    
    return 0
}

# コマンドがバックグラウンドで実行中かチェック
# Usage: is_daemon_running <pid>
is_daemon_running() {
    local pid="$1"
    if [[ -z "$pid" ]] || [[ "$pid" == "0" ]]; then
        return 1
    fi
    # set -e を一時的に無効化して kill の結果をチェック
    set +e
    kill -0 "$pid" 2>/dev/null
    local result=$?
    set -e
    return $result
}

# デーモンプロセスを安全に終了
# Usage: stop_daemon <pid> [signal]
stop_daemon() {
    local pid="$1"
    local signal="${2:-TERM}"
    
    if [[ -z "$pid" ]] || [[ "$pid" == "0" ]]; then
        return 1
    fi
    
    # set -e を一時的に無効化
    set +e
    kill -"$signal" "$pid" 2>/dev/null
    local result=$?
    set -e
    
    if [[ $result -eq 0 ]]; then
        return 0
    fi
    return 1
}

# 指定したコマンドラインで実行中のデーモンプロセスのPIDを検索
# Usage: find_daemon_pid <pattern>
# Returns: マッチした最初のPID（複数ある場合）
find_daemon_pid() {
    local pattern="$1"
    if command -v pgrep &> /dev/null; then
        pgrep -f "$pattern" | head -1
    else
        # pgrepがない場合はps+grepで検索（フォールバック）
        # shellcheck disable=SC2009
        ps aux | grep -v grep | grep -F "$pattern" | awk '{print $2}' | head -1
    fi
}
