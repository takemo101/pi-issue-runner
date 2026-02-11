#!/usr/bin/env bash
# ============================================================================
# knowledge-loop.sh - Knowledge Loop: Extract constraints from fix commits
#
# 後方互換ラッパー: 実装は lib/knowledge-loop/ サブモジュールに分割済み
#
# サブモジュール構成:
#   - lib/knowledge-loop/commits.sh:   extract_fix_commits, get_commit_body,
#                                       categorize_commit, score_commit,
#                                       group_commits_by_category
#   - lib/knowledge-loop/decisions.sh: extract_new_decisions, get_decision_title
#   - lib/knowledge-loop/proposals.sh: generate_knowledge_proposals,
#                                       apply_knowledge_proposals
#   - lib/knowledge-loop/context.sh:   collect_knowledge_context
#   - lib/knowledge-loop/tracker.sh:   extract_tracker_failures,
#                                       check_agents_duplicate, _score_to_stars
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_KNOWLEDGE_LOOP_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_SH_SOURCED="true"

_KNOWLEDGE_LOOP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# サブモジュールの読み込み
source "$_KNOWLEDGE_LOOP_LIB_DIR/knowledge-loop/commits.sh"
source "$_KNOWLEDGE_LOOP_LIB_DIR/knowledge-loop/decisions.sh"
source "$_KNOWLEDGE_LOOP_LIB_DIR/knowledge-loop/tracker.sh"
source "$_KNOWLEDGE_LOOP_LIB_DIR/knowledge-loop/proposals.sh"
source "$_KNOWLEDGE_LOOP_LIB_DIR/knowledge-loop/context.sh"
