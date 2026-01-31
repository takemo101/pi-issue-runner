#!/usr/bin/env bash
# improve.sh - Continuous improvement (2-phase approach)
# Uses pi --print for review, GitHub API for issue retrieval

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"

# Constants
DEFAULT_MAX_ITERATIONS=3
DEFAULT_MAX_ISSUES=5
DEFAULT_TIMEOUT=3600
LOG_DIR="$PROJECT_ROOT/.improve-logs"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --max-iterations N   Max iteration count (default: $DEFAULT_MAX_ITERATIONS)
    --max-issues N       Max issues per iteration (default: $DEFAULT_MAX_ISSUES)
    --timeout N          Session completion timeout in seconds (default: $DEFAULT_TIMEOUT)
    --iteration N        Current iteration number (internal use)
    --log-dir DIR        Log directory (default: $LOG_DIR)
    -v, --verbose        Show verbose logs
    -h, --help           Show this help

Description:
    Runs continuous improvement using 2-phase approach:
    1. Runs pi --print for project review and Issue creation (auto-exits)
    2. Fetches created Issues via GitHub API
    3. Starts parallel execution via run.sh --no-attach
    4. Monitors completion via wait-for-sessions.sh
    5. Recursively starts next iteration

Log files:
    Pi output is saved to: $LOG_DIR/iteration-N-YYYYMMDD-HHMMSS.log

Examples:
    $(basename "$0")
    $(basename "$0") --max-iterations 2 --max-issues 3
    $(basename "$0") --timeout 1800
    $(basename "$0") --log-dir /tmp/improve-logs

Environment Variables:
    PI_COMMAND           Path to pi command (default: pi)
    LOG_LEVEL            Log level (DEBUG, INFO, WARN, ERROR)
EOF
}

main() {
    local max_iterations=$DEFAULT_MAX_ITERATIONS
    local max_issues=$DEFAULT_MAX_ISSUES
    local timeout=$DEFAULT_TIMEOUT
    local iteration=1
    local log_dir="$LOG_DIR"

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
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --iteration)
                iteration="$2"
                shift 2
                ;;
            --log-dir)
                log_dir="$2"
                shift 2
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
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

    # Dependency check
    check_dependencies || exit 1

    # Max iterations check
    if [[ $iteration -gt $max_iterations ]]; then
        echo ""
        echo "🏁 Maximum iterations ($max_iterations) reached"
        exit 0
    fi

    # Create log directory
    mkdir -p "$log_dir"
    local log_file
    log_file="$log_dir/iteration-${iteration}-$(date +%Y%m%d-%H%M%S).log"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  🔧 Continuous Improvement - Iteration $iteration/$max_iterations"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Log file: $log_file"
    echo ""

    local pi_command
    pi_command="$(get_config pi_command)"

    # Record start time for Issue filtering
    local start_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Phase 1: Run pi --print for review and Issue creation
    local prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題からGitHub Issueを作成してください（最大${max_issues}件）。
Issueを作成しない場合は「問題は見つかりませんでした」と報告してください。"

    echo "[PHASE 1] Running project review via pi --print..."
    echo "[PHASE 1] This may take a few minutes..."
    
    # Run pi in --print mode and save output to log file while displaying
    if ! "$pi_command" --print --message "$prompt" 2>&1 | tee "$log_file"; then
        log_warn "pi command returned non-zero exit code"
    fi
    
    echo ""
    echo "[PHASE 1] Review complete. Log saved to: $log_file"

    # Phase 2: Fetch Issues via GitHub API
    echo ""
    echo "[PHASE 2] Fetching Issues created after $start_time..."
    
    local issues
    issues=$(get_issues_created_after "$start_time" "$max_issues") || true
    
    if [[ -z "$issues" ]]; then
        echo "No new Issues created"
        echo ""
        echo "✅ Improvement complete! No issues found."
        exit 0
    fi
    
    # Convert Issue numbers to array
    local issue_array=()
    while IFS= read -r issue; do
        if [[ -n "$issue" && "$issue" =~ ^[0-9]+$ ]]; then
            issue_array+=("$issue")
        fi
    done <<< "$issues"
    
    if [[ ${#issue_array[@]} -eq 0 ]]; then
        echo "No new Issues created"
        echo ""
        echo "✅ Improvement complete! No issues found."
        exit 0
    fi
    
    echo "Created Issues: ${issue_array[*]}"

    # Phase 3: Start parallel execution via run.sh
    echo ""
    echo "[PHASE 3] Starting parallel execution..."
    
    for issue in "${issue_array[@]}"; do
        echo "  Starting Issue #$issue..."
        "$SCRIPT_DIR/run.sh" "$issue" --no-attach || {
            log_warn "Failed to start session for Issue #$issue"
        }
    done

    # Phase 4: Wait for sessions to complete
    echo ""
    echo "[PHASE 4] Waiting for sessions to complete..."
    
    if ! "$SCRIPT_DIR/wait-for-sessions.sh" "${issue_array[@]}" --timeout "$timeout"; then
        log_warn "Some sessions failed or timed out"
    fi

    # Phase 5: Recursive call for next iteration
    echo ""
    echo "[PHASE 5] Starting next iteration..."
    
    exec "$0" \
        --max-iterations "$max_iterations" \
        --max-issues "$max_issues" \
        --timeout "$timeout" \
        --log-dir "$log_dir" \
        --iteration "$((iteration + 1))"
}

# Dependency check
check_dependencies() {
    local missing=()

    # pi command
    local pi_command
    pi_command="$(get_config pi_command)"
    if ! command -v "$pi_command" &> /dev/null; then
        missing+=("$pi_command (pi)")
    fi

    # gh command
    if ! command -v gh &> /dev/null; then
        missing+=("gh (GitHub CLI)")
    fi

    # jq command (required for GitHub API parsing)
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
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

main "$@"
