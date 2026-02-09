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
    
    # macOSではsetsidがないため、perlのsetpgrp(0,0)で新しいプロセスグループを作成。
    # これにより親プロセスグループへのSIGTERM/SIGINTが子に波及しない。
    # perlも利用不可の場合は、trap '' HUP でSIGHUPのみ無視するフォールバック。
    #
    # プロセスグループ分離が重要な理由:
    #   run-batch.shがタイムアウト等でkillされると、同じプロセスグループ全体に
    #   SIGTERMが送信され、watcherが巻き添えで死ぬ。
    #   プロセスグループを分離すれば、親のkillは子に波及しない。
    #   かつ、watcherは自身のSIGTERMハンドラを持てる（restart/stop可能）。
    if command -v perl &> /dev/null; then
        # perl経由でプロセスグループを分離して実行
        (
            exec 0</dev/null
            exec 1>>"$log_file"
            exec 2>&1
            
            # setpgrp(0,0)で新しいプロセスグループのリーダーになる
            # これで親のプロセスグループへのシグナルが波及しない
            perl -e '
                use POSIX qw(setsid);
                # setpgrp で新プロセスグループ作成（setsid より軽量）
                setpgrp(0, 0);
                exec @ARGV or die "exec failed: $!";
            ' -- "$@" &
            local bg_pid=$!
            echo "$bg_pid" > "$pid_file"
            disown "$bg_pid" 2>/dev/null || true
        ) &
    else
        # perl も setsid もない環境: SIGHUPのみ無視（SIGTERM保護なし）
        (
            trap '' HUP
            
            exec 0</dev/null
            exec 1>>"$log_file"
            exec 2>&1
            
            "$@" &
            local bg_pid=$!
            echo "$bg_pid" > "$pid_file"
            disown %1 2>/dev/null || disown "$bg_pid" 2>/dev/null || true
        ) &
    fi
    
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
