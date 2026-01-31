#!/usr/bin/env bash
# improve.sh - 継続的改善スクリプト
# プロジェクトレビュー→Issue作成→並列実行→完了待ち→再レビューのループを自動化

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/status.sh"

# グローバル変数
CREATED_ISSUES=()

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --max-iterations N   最大イテレーション数（デフォルト: 3）
    --max-issues N       1回あたりの最大Issue数（デフォルト: 5）
    --auto-continue      承認ゲートをスキップ（自動継続）
    --dry-run            レビューのみ実行（Issue作成・実行しない）
    --timeout <sec>      各イテレーションのタイムアウト（デフォルト: 3600）
    --review-only        project-reviewスキルで問題を表示するのみ
    -v, --verbose        詳細ログを表示
    -h, --help           このヘルプを表示

Description:
    プロジェクトの継続的改善を自動化します:
    1. プロジェクトをレビューして問題を発見
    2. 発見した問題からGitHub Issueを作成
    3. 各Issueに対してpi-issue-runnerを並列実行
    4. すべての実行が完了するまで待機
    5. 問題がなくなるか最大回数に達するまで繰り返し

Examples:
    $(basename "$0")
    $(basename "$0") --max-iterations 2 --max-issues 3
    $(basename "$0") --dry-run
    $(basename "$0") --auto-continue

Environment Variables:
    PI_COMMAND           piコマンドのパス（デフォルト: pi）
    LOG_LEVEL            ログレベル（DEBUG, INFO, WARN, ERROR）
EOF
}

main() {
    local max_iterations=3
    local max_issues=5
    local auto_continue=false
    local dry_run=false
    local review_only=false
    local timeout=3600

    # 引数のパース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-iterations)
                max_iterations="$2"
                shift 2
                ;;
            --max-issues)
                max_issues="$2"
                shift 2
                ;;
            --auto-continue)
                auto_continue=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --review-only)
                review_only=true
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="DEBUG"
                shift
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
                log_error "Unexpected argument: $1"
                usage >&2
                exit 1
                ;;
        esac
    done

    load_config

    # 依存関係チェック
    check_dependencies || exit 1

    local iteration=1

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║             🔧 継続的改善スクリプト (improve.sh)            ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  max-iterations: $max_iterations"
    echo "║  max-issues:     $max_issues"
    echo "║  auto-continue:  $auto_continue"
    echo "║  dry-run:        $dry_run"
    echo "║  timeout:        ${timeout}s"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    while [[ $iteration -le $max_iterations ]]; do
        echo ""
        echo "🔍 ════════════════════════════════════════════════════════"
        echo "   Iteration $iteration/$max_iterations"
        echo "════════════════════════════════════════════════════════════"
        echo ""

        # Phase 1: レビュー
        echo "[REVIEW] プロジェクトをレビュー中..."
        CREATED_ISSUES=()
        
        if ! review_and_create_issues "$max_issues" "$dry_run" "$review_only"; then
            log_error "Review failed"
            exit 1
        fi

        # Issue が0件なら完了
        if [[ ${#CREATED_ISSUES[@]} -eq 0 ]]; then
            echo ""
            echo "✅ 改善完了！問題は見つかりませんでした。"
            echo ""
            exit 0
        fi

        echo "[pi] ${#CREATED_ISSUES[@]}件の問題を発見/Issue作成"
        for issue in "${CREATED_ISSUES[@]}"; do
            echo "  - Issue #$issue"
        done

        # --review-only モードの場合はここで終了
        if [[ "$review_only" == "true" ]]; then
            echo ""
            echo "[INFO] --review-only モードのため、実行をスキップします"
            break
        fi

        # --dry-run モードの場合はPhase 2-3をスキップ
        if [[ "$dry_run" == "true" ]]; then
            echo ""
            echo "[INFO] --dry-run モードのため、実行をスキップします"
        else
            # Phase 2: 並列実行
            echo ""
            echo "[RUN] ${#CREATED_ISSUES[@]} Issueを並列実行中..."
            for issue in "${CREATED_ISSUES[@]}"; do
                echo "  Starting Issue #$issue..."
                "$SCRIPT_DIR/run.sh" "$issue" --no-attach || {
                    log_warn "Failed to start session for Issue #$issue"
                }
            done

            # Phase 3: 完了待機
            echo ""
            echo "[WAIT] 完了を待機中..."
            if ! "$SCRIPT_DIR/wait-for-sessions.sh" "${CREATED_ISSUES[@]}" --timeout "$timeout"; then
                log_warn "Some sessions failed or timed out"
            fi
        fi

        # Phase 4: 承認ゲート
        if [[ $iteration -lt $max_iterations ]]; then
            if [[ "$auto_continue" != "true" ]]; then
                echo ""
                read -r -p "次のイテレーションを実行しますか？ [Y/n]: " answer
                if [[ "$answer" =~ ^[Nn] ]]; then
                    echo "[INFO] ユーザーにより中断されました"
                    break
                fi
            fi
        fi

        ((iteration++)) || true
    done

    if [[ $iteration -gt $max_iterations ]]; then
        echo ""
        echo "[INFO] 最大イテレーション数 ($max_iterations) に達しました"
    fi

    echo ""
    echo "🏁 改善プロセス終了"
}

# 依存関係チェック
check_dependencies() {
    local missing=()

    # piコマンド
    local pi_command
    pi_command="$(get_config pi_command)"
    if ! command -v "$pi_command" &> /dev/null; then
        missing+=("$pi_command (pi)")
    fi

    # gh (GitHub CLI)
    if ! command -v gh &> /dev/null; then
        missing+=("gh (GitHub CLI)")
    fi

    # tmux
    if ! command -v tmux &> /dev/null; then
        missing+=("tmux")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep" >&2
        done
        return 1
    fi

    return 0
}

# piコマンドをPTY付きで実行（ターミナル幅を正しく認識させる）
# 引数:
#   $1 - output_file: 出力ファイルパス
#   $2 - pi_command: piコマンドのパス
#   残り - piコマンドの引数
# 戻り値:
#   piコマンドの終了コード
run_pi_interactive() {
    local output_file="$1"
    local pi_command="$2"
    shift 2
    
    local cols
    cols=$(tput cols 2>/dev/null || echo 120)
    
    log_debug "Terminal columns: $cols"
    log_debug "Output file: $output_file"
    
    # 方法1: script コマンドを試行（PTYを作成）
    if command -v script &>/dev/null; then
        log_debug "Trying script command for PTY preservation"
        
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: script -q <output_file> <command>
            # Note: macOS の script は引数をそのまま実行する
            log_debug "Using macOS script syntax"
            if COLUMNS="$cols" script -q "$output_file" "$pi_command" "$@" 2>/dev/null; then
                return 0
            fi
            log_debug "macOS script command failed, trying fallback"
        else
            # Linux: script -q -c "<command>" <output_file>
            # Note: Linux の script は -c オプションでコマンドを指定
            log_debug "Using Linux script syntax"
            local cmd_str="$pi_command"
            for arg in "$@"; do
                # 引数をシングルクォートでエスケープ
                cmd_str+=" '${arg//\'/\'\\\'\'}'"
            done
            if COLUMNS="$cols" script -q -c "$cmd_str" "$output_file" 2>/dev/null; then
                return 0
            fi
            log_debug "Linux script command failed, trying fallback"
        fi
    fi
    
    # 方法2: unbuffer を試行
    if command -v unbuffer &>/dev/null; then
        log_debug "Trying unbuffer for PTY preservation"
        if COLUMNS="$cols" unbuffer "$pi_command" "$@" 2>&1 | tee "$output_file"; then
            return 0
        fi
        log_debug "unbuffer failed, trying fallback"
    fi
    
    # 方法3: フォールバック（幅が狭くなる可能性あり）
    log_warn "PTY preservation not available (no script/unbuffer), display may be narrow"
    
    local pi_exit_code=0
    if command -v stdbuf &>/dev/null; then
        log_debug "Using stdbuf for line buffering (fallback)"
        COLUMNS="$cols" stdbuf -oL "$pi_command" "$@" 2>&1 | stdbuf -oL tee "$output_file" || pi_exit_code=$?
    else
        log_debug "Using standard pipe (fallback)"
        COLUMNS="$cols" "$pi_command" "$@" 2>&1 | tee "$output_file" || pi_exit_code=$?
    fi
    
    return $pi_exit_code
}

# プロジェクトをレビューしてIssueを作成
# 引数:
#   $1 - max_issues: 最大Issue数
#   $2 - dry_run: ドライランモード
#   $3 - review_only: レビューのみモード
review_and_create_issues() {
    local max_issues="$1"
    local dry_run="$2"
    local review_only="$3"
    
    local output_file
    output_file="$(mktemp)"
    trap "rm -f '$output_file'" RETURN
    
    local pi_command
    pi_command="$(get_config pi_command)"
    
    # プロンプトの構築
    local review_prompt
    if [[ "$review_only" == "true" ]]; then
        review_prompt="project-reviewスキルを使用してプロジェクト全体をレビューし、発見した問題を一覧で表示してください。Issue作成は行わないでください。"
    elif [[ "$dry_run" == "true" ]]; then
        review_prompt="project-reviewスキルを使用してプロジェクト全体をレビューし、発見した問題を一覧で表示してください。
発見した問題のうち、作成するべきIssueがあれば、以下の形式で番号を出力してください（実際にはIssue作成しないでください）:

###WOULD_CREATE_ISSUES###
<仮のIssue番号または説明を1行ずつ>
###END_ISSUES###"
    else
        review_prompt="project-reviewスキルを使用してプロジェクト全体を厳格にレビューし、発見した問題からGitHub Issueを作成してください。
最大${max_issues}件までのIssueを作成してください。

作成したIssue番号を以下の形式で最後に必ず出力してください:
###CREATED_ISSUES###
<Issue番号を1行ずつ、数字のみ>
###END_ISSUES###

例:
###CREATED_ISSUES###
147
148
###END_ISSUES###"
    fi

    echo "[pi] レビュー実行中..."
    
    # piを実行（PTY保持でターミナル幅を正しく認識させる）
    local pi_exit_code=0
    run_pi_interactive "$output_file" "$pi_command" --message "$review_prompt" || pi_exit_code=$?
    
    # ファイルシステムを同期（バッファフラッシュ）
    sync 2>/dev/null || true
    
    # 少し待機（ファイル書き込み完了を確実に）
    sleep 0.5
    
    if [[ $pi_exit_code -ne 0 ]]; then
        log_error "pi command failed with exit code $pi_exit_code"
        return 1
    fi
    
    # デバッグログ: ファイル情報を表示
    if [[ "${LOG_LEVEL:-}" == "DEBUG" ]]; then
        log_debug "Output file: $output_file"
        log_debug "File size: $(wc -c < "$output_file") bytes"
        log_debug "File lines: $(wc -l < "$output_file") lines"
    fi

    # Issue番号を抽出
    if [[ "$dry_run" == "true" ]]; then
        # ドライランモードでは仮のIssue番号を表示するのみ
        echo "[dry-run] 以下のIssueが作成される予定でした:"
        sed -n '/###WOULD_CREATE_ISSUES###/,/###END_ISSUES###/p' "$output_file" \
            | grep -v '###' \
            | head -n "$max_issues" \
            || true
        CREATED_ISSUES=()
    elif [[ "$review_only" == "true" ]]; then
        # レビューのみモードではIssue番号を抽出しない
        CREATED_ISSUES=()
    else
        # デバッグログ: 抽出前の状態を表示
        if [[ "${LOG_LEVEL:-}" == "DEBUG" ]]; then
            log_debug "Output file size: $(wc -c < "$output_file") bytes"
            log_debug "Checking for CREATED_ISSUES marker..."
            if grep -q "###CREATED_ISSUES###" "$output_file"; then
                log_debug "Marker found. Raw content between markers:"
                sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file" | cat -A | head -20
            else
                log_debug "Marker NOT found in output"
            fi
        fi
        
        # Issue番号を抽出（ANSIエスケープコード・制御文字を除去してから処理）
        local issues_text
        issues_text=$(cat "$output_file" \
            | tr -d '\r' \
            | sed 's/\x1b\[[0-9;]*m//g' \
            | sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' \
            | grep -oE '[0-9]+' \
            | head -n "$max_issues") || true
        
        if [[ "${LOG_LEVEL:-}" == "DEBUG" ]]; then
            log_debug "Extracted issues_text: '$issues_text'"
        fi
        
        if [[ -n "$issues_text" ]]; then
            while IFS= read -r issue; do
                if [[ -n "$issue" && "$issue" =~ ^[0-9]+$ ]]; then
                    CREATED_ISSUES+=("$issue")
                fi
            done <<< "$issues_text"
        fi
        
        if [[ "${LOG_LEVEL:-}" == "DEBUG" ]]; then
            log_debug "Final CREATED_ISSUES array: (${CREATED_ISSUES[*]:-})"
        fi
    fi

    return 0
}

main "$@"
