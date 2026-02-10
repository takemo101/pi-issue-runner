#!/usr/bin/env bash
# ============================================================================
# tracker.sh - プロンプト効果測定の集計・表示
#
# タスクの成功/失敗をワークフロー別に集計し、プロンプト改善に活用する。
#
# Usage: ./scripts/tracker.sh [options]
#
# Options:
#   --by-workflow       ワークフロー別成功率を表示
#   --failures          失敗パターン分析（直近の失敗一覧）
#   --gates             ゲート統計表示（ゲート別通過率、リトライ数）
#   --since "N days"    期間指定（N日以内のエントリのみ）
#   --json              JSON形式で出力
#   -h, --help          ヘルプを表示
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/tracker.sh
#   ./scripts/tracker.sh --by-workflow
#   ./scripts/tracker.sh --failures
#   ./scripts/tracker.sh --since "7 days"
#   ./scripts/tracker.sh --json
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tracker.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

プロンプト効果測定の集計・表示

Options:
    --by-workflow       ワークフロー別成功率を表示
    --failures          失敗パターン分析（直近の失敗一覧）
    --gates             ゲート統計表示（ゲート別通過率、リトライ数）
    --since "N days"    期間指定（N日以内のエントリのみ）
    --json              JSON形式で出力
    -h, --help          このヘルプを表示
EOF
}

# ============================================================================
# Date filtering
# ============================================================================

_parse_since_to_epoch() {
    local since_str="$1"
    local days=""

    if [[ "$since_str" =~ ^([0-9]+)[[:space:]]*(days?|d)$ ]]; then
        days="${BASH_REMATCH[1]}"
    elif [[ "$since_str" =~ ^([0-9]+)$ ]]; then
        days="$since_str"
    else
        log_error "Invalid --since format: '$since_str' (expected: 'N days' or 'N')"
        return 1
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        date -u -v-"${days}d" +%s
    else
        date -u -d "${days} days ago" +%s
    fi
}

_iso_to_epoch() {
    local iso_ts="$1"
    local clean_ts="${iso_ts%Z}"
    clean_ts="${clean_ts//T/ }"

    if [[ "$(uname)" == "Darwin" ]]; then
        date -u -j -f "%Y-%m-%d %H:%M:%S" "$clean_ts" +%s 2>/dev/null || echo "0"
    else
        date -u -d "${iso_ts}" +%s 2>/dev/null || echo "0"
    fi
}

_filter_by_since() {
    local since_epoch="$1"
    local line ts_epoch

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local ts
        if command -v jq &>/dev/null; then
            ts="$(printf '%s' "$line" | jq -r '.timestamp // ""' 2>/dev/null)" || ts=""
        else
            ts="$(printf '%s' "$line" | grep -o '"timestamp":"[^"]*"' | sed 's/"timestamp":"\([^"]*\)"/\1/')" || ts=""
        fi

        if [[ -n "$ts" ]]; then
            ts_epoch="$(_iso_to_epoch "$ts")"
            if [[ "$ts_epoch" -ge "$since_epoch" ]]; then
                printf '%s\n' "$line"
            fi
        fi
    done
}

# ============================================================================
# Output functions
# ============================================================================

_show_summary() {
    local tracker_file="$1"
    local since_epoch="${2:-}"

    local entries
    if [[ -n "$since_epoch" ]]; then
        entries="$(_filter_by_since "$since_epoch" < "$tracker_file")"
    else
        entries="$(cat "$tracker_file")"
    fi

    if [[ -z "$entries" ]]; then
        echo "=== Prompt Tracker Summary ==="
        echo "No entries found."
        return 0
    fi

    local total success error
    total="$(printf '%s\n' "$entries" | wc -l | tr -d ' ')"

    if command -v jq &>/dev/null; then
        success="$(printf '%s\n' "$entries" | jq -r 'select(.result == "success")' | jq -s 'length')"
        error="$(printf '%s\n' "$entries" | jq -r 'select(.result == "error")' | jq -s 'length')"
    else
        success="$(printf '%s\n' "$entries" | grep -c '"result":"success"\|"result": "success"' || echo 0)"
        error="$(printf '%s\n' "$entries" | grep -c '"result":"error"\|"result": "error"' || echo 0)"
    fi

    local rate="0.0"
    if [[ "$total" -gt 0 ]]; then
        rate="$(awk "BEGIN {printf \"%.1f\", ($success / $total) * 100}")"
    fi

    echo "=== Prompt Tracker Summary ==="
    echo "Total: $total tasks ($success success, $error error) - ${rate}%"
}

_show_by_workflow() {
    local tracker_file="$1"
    local since_epoch="${2:-}"

    local entries
    if [[ -n "$since_epoch" ]]; then
        entries="$(_filter_by_since "$since_epoch" < "$tracker_file")"
    else
        entries="$(cat "$tracker_file")"
    fi

    if [[ -z "$entries" ]]; then
        echo "No entries found."
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for --by-workflow"
        return 1
    fi

    _show_summary_from_entries "$entries"

    echo ""
    echo "By Workflow:"

    local workflows
    workflows="$(printf '%s\n' "$entries" | jq -r '.workflow' | sort -u)"

    while IFS= read -r wf; do
        [[ -z "$wf" ]] && continue
        local wf_entries wf_total wf_success wf_rate
        wf_entries="$(printf '%s\n' "$entries" | jq -c "select(.workflow == \"$wf\")")"
        wf_total="$(printf '%s\n' "$wf_entries" | wc -l | tr -d ' ')"
        wf_success="$(printf '%s\n' "$wf_entries" | jq -r 'select(.result == "success")' | jq -s 'length')"
        wf_rate="0.0"
        if [[ "$wf_total" -gt 0 ]]; then
            wf_rate="$(awk "BEGIN {printf \"%.1f\", ($wf_success / $wf_total) * 100}")"
        fi
        printf "  %-12s %d/%d  %s%%\n" "$wf" "$wf_success" "$wf_total" "$wf_rate"
    done <<< "$workflows"
}

_show_summary_from_entries() {
    local entries="$1"

    local total success error rate
    total="$(printf '%s\n' "$entries" | wc -l | tr -d ' ')"
    success="$(printf '%s\n' "$entries" | jq -r 'select(.result == "success")' | jq -s 'length')"
    error="$(printf '%s\n' "$entries" | jq -r 'select(.result == "error")' | jq -s 'length')"
    rate="0.0"
    if [[ "$total" -gt 0 ]]; then
        rate="$(awk "BEGIN {printf \"%.1f\", ($success / $total) * 100}")"
    fi

    echo "=== Prompt Tracker Summary ==="
    echo "Total: $total tasks ($success success, $error error) - ${rate}%"
}

_show_failures() {
    local tracker_file="$1"
    local since_epoch="${2:-}"

    local entries
    if [[ -n "$since_epoch" ]]; then
        entries="$(_filter_by_since "$since_epoch" < "$tracker_file")"
    else
        entries="$(cat "$tracker_file")"
    fi

    if [[ -z "$entries" ]]; then
        echo "No entries found."
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for --failures"
        return 1
    fi

    local failures
    failures="$(printf '%s\n' "$entries" | jq -c 'select(.result == "error")')"

    if [[ -z "$failures" ]]; then
        echo "No failures found."
        return 0
    fi

    echo "Recent Failures:"
    printf '%s\n' "$failures" | tail -10 | while IFS= read -r line; do
        local issue wf error_type
        issue="$(printf '%s' "$line" | jq -r '.issue')"
        wf="$(printf '%s' "$line" | jq -r '.workflow')"
        error_type="$(printf '%s' "$line" | jq -r '.error_type // "unknown"')"
        printf "  #%-6s (%-10s) - %s\n" "$issue" "$wf" "$error_type"
    done
}

_show_gates() {
    local tracker_file="$1"
    local since_epoch="${2:-}"

    local entries
    if [[ -n "$since_epoch" ]]; then
        entries="$(_filter_by_since "$since_epoch" < "$tracker_file")"
    else
        entries="$(cat "$tracker_file")"
    fi

    if [[ -z "$entries" ]]; then
        echo "No entries found."
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for --gates"
        return 1
    fi

    local with_gates
    with_gates="$(printf '%s\n' "$entries" | jq -c 'select(.gates != null and .gates != {})')"

    if [[ -z "$with_gates" ]]; then
        echo "=== Gate Statistics ==="
        echo "No gate data found."
        return 0
    fi

    local total_entries
    total_entries="$(printf '%s\n' "$with_gates" | wc -l | tr -d ' ')"

    echo "=== Gate Statistics ==="
    echo "Entries with gate data: $total_entries"
    echo ""

    local all_gate_names
    all_gate_names="$(printf '%s\n' "$with_gates" | jq -r '.gates | keys[]' | sort -u)"

    echo "Gate Pass Rates:"
    while IFS= read -r gate_name; do
        [[ -z "$gate_name" ]] && continue
        local gate_total gate_pass gate_rate total_attempts
        gate_total="$(printf '%s\n' "$with_gates" | jq -c --arg g "$gate_name" 'select(.gates[$g] != null)' | wc -l | tr -d ' ')"
        gate_pass="$(printf '%s\n' "$with_gates" | jq -c --arg g "$gate_name" 'select(.gates[$g] != null and .gates[$g].result == "pass")' | wc -l | tr -d ' ')"
        gate_rate="0.0"
        if [[ "$gate_total" -gt 0 ]]; then
            gate_rate="$(awk "BEGIN {printf \"%.1f\", ($gate_pass / $gate_total) * 100}")"
        fi
        total_attempts="$(printf '%s\n' "$with_gates" | jq --arg g "$gate_name" '.gates[$g].attempts // 0' | awk '{s+=$1} END {print s}')"
        printf "  %-30s %d/%d  %s%%  (total attempts: %s)\n" "$gate_name" "$gate_pass" "$gate_total" "$gate_rate" "$total_attempts"
    done <<< "$all_gate_names"

    echo ""
    local total_retries
    total_retries="$(printf '%s\n' "$with_gates" | jq '.total_gate_retries // 0' | awk '{s+=$1} END {print s}')"
    echo "Total retries across all entries: $total_retries"
}

_show_json() {
    local tracker_file="$1"
    local since_epoch="${2:-}"

    local entries
    if [[ -n "$since_epoch" ]]; then
        entries="$(_filter_by_since "$since_epoch" < "$tracker_file")"
    else
        entries="$(cat "$tracker_file")"
    fi

    if [[ -z "$entries" ]]; then
        echo "[]"
        return 0
    fi

    if command -v jq &>/dev/null; then
        printf '%s\n' "$entries" | jq -s '.'
    else
        printf '[%s]\n' "$(printf '%s\n' "$entries" | paste -sd, -)"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    local mode="summary"
    local since_str=""
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --by-workflow)
                mode="by-workflow"
                shift
                ;;
            --failures)
                mode="failures"
                shift
                ;;
            --gates)
                mode="gates"
                shift
                ;;
            --since)
                since_str="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
    done

    load_config 2>/dev/null || true

    local tracker_file
    tracker_file="$(get_tracker_file)"

    if [[ ! -f "$tracker_file" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo "[]"
        else
            echo "=== Prompt Tracker Summary ==="
            echo "No entries found."
        fi
        exit 0
    fi

    local since_epoch=""
    if [[ -n "$since_str" ]]; then
        since_epoch="$(_parse_since_to_epoch "$since_str")"
    fi

    if [[ "$json_output" == "true" ]]; then
        _show_json "$tracker_file" "$since_epoch"
        exit 0
    fi

    case "$mode" in
        summary)
            _show_summary "$tracker_file" "$since_epoch"
            ;;
        by-workflow)
            _show_by_workflow "$tracker_file" "$since_epoch"
            ;;
        failures)
            _show_failures "$tracker_file" "$since_epoch"
            ;;
        gates)
            _show_gates "$tracker_file" "$since_epoch"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
