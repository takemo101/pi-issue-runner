#!/bin/bash
set -euo pipefail

# ============================================================================
# ci-wait.sh - CI完了待機スクリプト
#
# PRのCIチェックが完了するまでポーリングで待機する。
# 成功・失敗・タイムアウトを終了コードで返す。
#
# Usage: bash .pi/skills/ci-workflow/scripts/ci-wait.sh <pr-number> [timeout-seconds]
# Example: bash .pi/skills/ci-workflow/scripts/ci-wait.sh 42 600
#
# Exit codes:
#   0 - All CI checks passed
#   1 - One or more CI checks failed
#   2 - Timeout reached
#   3 - Invalid arguments or gh CLI error
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

usage() {
    echo "Usage: $0 <pr-number> [timeout-seconds]"
    echo ""
    echo "Waits for CI checks to complete on a pull request."
    echo ""
    echo "Arguments:"
    echo "  pr-number        PR number to check (e.g., 42)"
    echo "  timeout-seconds  Maximum wait time in seconds (default: 600)"
    echo ""
    echo "Exit codes:"
    echo "  0 - All CI checks passed"
    echo "  1 - One or more CI checks failed"
    echo "  2 - Timeout reached"
    echo "  3 - Invalid arguments or gh CLI error"
    echo ""
    echo "Example:"
    echo "  $0 42         # Wait up to 10 minutes"
    echo "  $0 42 1800    # Wait up to 30 minutes"
    exit 3
}

if [ $# -lt 1 ]; then
    log_error "PR number is required"
    usage
fi

PR_NUMBER="$1"
TIMEOUT="${2:-600}"
POLL_INTERVAL=30

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    log_error "PR number must be a number: $PR_NUMBER"
    exit 3
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    log_error "Timeout must be a number: $TIMEOUT"
    exit 3
fi

if ! command -v gh &> /dev/null; then
    log_error "gh CLI is not installed"
    exit 3
fi

if ! gh auth status &> /dev/null; then
    log_error "gh CLI is not authenticated"
    exit 3
fi

if ! gh pr view "$PR_NUMBER" &> /dev/null; then
    log_error "PR #${PR_NUMBER} not found"
    exit 3
fi

log_info "Waiting for CI checks on PR #${PR_NUMBER}..."
log_info "Timeout: ${TIMEOUT}s, Poll interval: ${POLL_INTERVAL}s"

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    CHECKS_JSON=$(gh pr checks "$PR_NUMBER" --json state,name 2>/dev/null) || {
        log_warn "Failed to get CI status, retrying..."
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        continue
    }

    if [ -z "$CHECKS_JSON" ] || [ "$CHECKS_JSON" = "[]" ]; then
        log_warn "No CI checks found, waiting for checks to start..."
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        continue
    fi

    PENDING=$(echo "$CHECKS_JSON" | jq '[.[] | select(.state == "PENDING" or .state == "QUEUED" or .state == "IN_PROGRESS")] | length')
    FAILED=$(echo "$CHECKS_JSON" | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length')
    SUCCESS=$(echo "$CHECKS_JSON" | jq '[.[] | select(.state == "SUCCESS")] | length')
    TOTAL=$(echo "$CHECKS_JSON" | jq 'length')

    log_step "Progress: ${SUCCESS}/${TOTAL} passed, ${FAILED} failed, ${PENDING} pending (${ELAPSED}s elapsed)"

    if [ "$FAILED" -gt 0 ]; then
        log_error "CI checks failed!"
        echo ""
        echo "Failed checks:"
        echo "$CHECKS_JSON" | jq -r '.[] | select(.state == "FAILURE" or .state == "ERROR") | "  - \(.name): \(.state)"'
        echo ""
        log_info "View full logs: gh pr checks ${PR_NUMBER}"
        log_info "View failed run: gh run view --log-failed"
        exit 1
    fi

    if [ "$PENDING" -eq 0 ] && [ "$SUCCESS" -gt 0 ]; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN} All CI checks passed!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "PR #${PR_NUMBER} is ready to merge"
        echo "Total checks: ${TOTAL}"
        echo "Time elapsed: ${ELAPSED}s"
        echo ""
        exit 0
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

log_error "Timeout reached (${TIMEOUT}s)"
log_info "CI checks are still pending. You can:"
log_info "  1. Continue waiting: $0 $PR_NUMBER $((TIMEOUT * 2))"
log_info "  2. Check status manually: gh pr checks $PR_NUMBER"
exit 2
