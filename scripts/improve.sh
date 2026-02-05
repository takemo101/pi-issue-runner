#!/usr/bin/env bash
# ============================================================================
# improve.sh - Continuous improvement script
#
# Performs continuous improvement using a 2-phase approach:
# 1. Review phase: Uses pi --print for code review
# 2. Execution phase: Uses GitHub API for issue retrieval and execution
#
# This is a thin CLI wrapper around lib/improve.sh
#
# Usage: ./scripts/improve.sh [options]
#
# Options:
#   --max-iterations N   Max iteration count (default: 3)
#   --max-issues N       Max issues per iteration (default: 5)
#   --timeout N          Session completion timeout in seconds (default: 3600)
#   --iteration N        Current iteration number (internal use)
#   --log-dir DIR        Log directory (default: .improve-logs)
#   --label LABEL        Session label for Issue filtering
#   --dry-run            Review only, do not create Issues
#   --review-only        Show problems only (no Issue creation or execution)
#   --auto-continue      Auto-continue without approval
#   -v, --verbose        Show verbose logs
#   -h, --help           Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/improve.sh
#   ./scripts/improve.sh --max-iterations 1
#   ./scripts/improve.sh --dry-run
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Handle --help early (before sourcing library)
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
Usage: improve.sh [options]

Options:
    --max-iterations N   Max iteration count (default: 3)
    --max-issues N       Max issues per iteration (default: 5)
    --timeout N          Session completion timeout in seconds (default: 3600)
    --iteration N        Current iteration number (internal use)
    --log-dir DIR        Log directory (default: .improve-logs in current directory)
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
    Pi output is saved to: .improve-logs/iteration-N-YYYYMMDD-HHMMSS.log

Examples:
    improve.sh
    improve.sh --max-iterations 1
    improve.sh --dry-run
    improve.sh --review-only
    improve.sh --auto-continue
    improve.sh --label my-session
EOF
        exit 0
    fi
done

# Source the library
source "$SCRIPT_DIR/../lib/improve.sh"

# Call main function
improve_main "$@"
