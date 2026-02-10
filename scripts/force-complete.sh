#!/usr/bin/env bash
# ============================================================================
# force-complete.sh - DEPRECATED: Use stop.sh --cleanup instead
#
# This script is deprecated and will be removed in a future release.
# It now redirects to stop.sh --cleanup.
#
# Usage: ./scripts/stop.sh <session-name|issue-number> --cleanup
# ============================================================================

set -euo pipefail

echo "WARNING: force-complete.sh is deprecated. Use: stop.sh ${1:-<target>} --cleanup" >&2
exec "$(dirname "$0")/stop.sh" "${1:?Session name or issue number is required}" --cleanup
