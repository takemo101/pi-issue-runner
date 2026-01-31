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

# Global: Track active sessions for cleanup on exit
declare -a ACTIVE_ISSUE_NUMBERS=()

# Cleanup function for EXIT trap
cleanup_on_exit() {
    local exit_code=$?
    
    # Only cleanup if there are active sessions and exit is not normal
    if [[ ${#ACTIVE_ISSUE_NUMBERS[@]} -gt 0 && $exit_code -ne 0 ]]; then
        log_warn "Interrupted! Cleaning up ${#ACTIVE_ISSUE_NUMBERS[@]} active session(s)..."
        for issue in "${ACTIVE_ISSUE_NUMBERS[@]}"; do
            log_info "  Cleaning up Issue #$issue..."
            "$SCRIPT_DIR/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
        done
        log_info "Cleanup completed."
    fi
    
    exit $exit_code
}

# Set up trap for cleanup on interruption
trap cleanup_on_exit EXIT INT TERM

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --max-iterations N   Max iteration count (default: $DEFAULT_MAX_ITERATIONS)
    --max-issues N       Max issues per iteration (default: $DEFAULT_MAX_ISSUES)
    --timeout N          Session completion timeout in seconds (default: $DEFAULT_TIMEOUT)
    --iteration N        Current iteration number (internal use)
    --log-dir DIR        Log directory (default: $LOG_DIR)
    --label LABEL        Session label for Issue filtering (auto-generated if not specified)
    --dry-run            Review only, do not create Issues
    --review-only        Show problems only (no Issue creation or execution)
    --auto-continue      Auto-continue without approval (skip confirmation)
    -v, --verbose        Show verbose logs
    -h, --help           Show this help

Description:
    Runs continuous improvement using 2-phase approach:
    1. Runs pi --print for project review and Issue creation (auto-exits)
    2. Fetches created Issues via GitHub API (filtered by session label)
    3. Starts parallel execution via run.sh --no-attach
    4. Monitors completion via wait-for-sessions.sh
    5. Recursively starts next iteration

    Issues are tagged with a session-specific label (e.g., pi-runner-20260201-082900)
    to ensure only Issues from this session are processed, enabling safe parallel runs.

Log files:
    Pi output is saved to: $LOG_DIR/iteration-N-YYYYMMDD-HHMMSS.log

Examples:
    $(basename "$0")
    $(basename "$0") --max-iterations 2 --max-issues 3
    $(basename "$0") --timeout 1800
    $(basename "$0") --log-dir /tmp/improve-logs
    $(basename "$0") --label my-custom-session
    $(basename "$0") --dry-run
    $(basename "$0") --review-only
    $(basename "$0") --auto-continue

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
    local session_label=""
    local dry_run=false
    local review_only=false
    local auto_continue=false

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
            --label)
                session_label="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --review-only)
                review_only=true
                shift
                ;;
            --auto-continue)
                auto_continue=true
                shift
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

    # Generate session label if not provided (only on first iteration)
    if [[ -z "$session_label" ]]; then
        session_label="$(generate_session_label)"
        log_debug "Generated session label: $session_label"
    fi

    # Create session label in GitHub (skip for dry-run/review-only modes)
    if [[ "$dry_run" != "true" && "$review_only" != "true" ]]; then
        create_label_if_not_exists "$session_label" "pi-issue-runner session: $session_label" || true
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
    echo "Session label: $session_label"
    echo "Log file: $log_file"
    echo ""

    local pi_command
    pi_command="$(get_config pi_command)"

    # Record start time for Issue filtering
    local start_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Phase 1: Run pi --print for review and Issue creation
    local prompt
    if [[ "$dry_run" == "true" || "$review_only" == "true" ]]; then
        # Dry-run or review-only mode: report problems without creating Issues
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題を報告してください（最大${max_issues}件）。
【重要】GitHub Issueは作成しないでください。問題の一覧を表示するのみにしてください。
問題が見つからない場合は「問題は見つかりませんでした」と報告してください。"
        echo "[PHASE 1] Running project review via pi --print (dry-run mode)..."
    else
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題からGitHub Issueを作成してください（最大${max_issues}件）。
【重要】Issueを作成する際は、必ず '--label ${session_label}' オプションを使用してラベル '${session_label}' を付けてください。
例: gh issue create --title \"...\" --body \"...\" --label \"${session_label}\"
Issueを作成しない場合は「問題は見つかりませんでした」と報告してください。"
        echo "[PHASE 1] Running project review via pi --print..."
    fi
    echo "[PHASE 1] This may take a few minutes..."
    
    # Run pi in --print mode and save output to log file while displaying
    if ! "$pi_command" --print --message "$prompt" 2>&1 | tee "$log_file"; then
        log_warn "pi command returned non-zero exit code"
    fi
    
    echo ""
    echo "[PHASE 1] Review complete. Log saved to: $log_file"

    # Exit early for review-only mode
    if [[ "$review_only" == "true" ]]; then
        echo ""
        echo "✅ Review-only mode complete. See log for details: $log_file"
        exit 0
    fi

    # Exit early for dry-run mode (after showing what would be done)
    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "✅ Dry-run mode complete. No Issues were created."
        echo "   Review results saved to: $log_file"
        exit 0
    fi

    # Phase 2: Fetch Issues via GitHub API
    echo ""
    echo "[PHASE 2] Fetching Issues created after $start_time with label '$session_label'..."
    
    local issues
    issues=$(get_issues_created_after "$start_time" "$max_issues" "$session_label") || true
    
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
        if "$SCRIPT_DIR/run.sh" "$issue" --no-attach; then
            # Track active session for cleanup on interruption
            ACTIVE_ISSUE_NUMBERS+=("$issue")
        else
            log_warn "Failed to start session for Issue #$issue"
        fi
    done

    # Phase 4: Wait for sessions to complete
    echo ""
    echo "[PHASE 4] Waiting for sessions to complete..."
    
    if ! "$SCRIPT_DIR/wait-for-sessions.sh" "${ACTIVE_ISSUE_NUMBERS[@]}" --timeout "$timeout" --cleanup; then
        log_warn "Some sessions failed or timed out"
    fi
    
    # Clear active sessions after completion (worktrees cleaned by --cleanup)
    ACTIVE_ISSUE_NUMBERS=()

    # Phase 5: Recursive call for next iteration
    echo ""
    echo "[PHASE 5] Starting next iteration..."
    
    # Confirmation before continuing (unless --auto-continue is set)
    if [[ "$auto_continue" != "true" ]]; then
        echo ""
        echo "Press Enter to continue to iteration $((iteration + 1)), or Ctrl+C to abort..."
        read -r
    fi
    
    # Build arguments for recursive call
    local args=(
        --max-iterations "$max_iterations"
        --max-issues "$max_issues"
        --timeout "$timeout"
        --log-dir "$log_dir"
        --iteration "$((iteration + 1))"
        --label "$session_label"
    )
    
    # Preserve --auto-continue flag
    if [[ "$auto_continue" == "true" ]]; then
        args+=(--auto-continue)
    fi
    
    exec "$0" "${args[@]}"
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
