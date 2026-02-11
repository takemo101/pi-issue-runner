#!/usr/bin/env bats

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    export TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT"

    # Initialize a git repo for testing
    git -C "$TEST_PROJECT" init -b main >/dev/null 2>&1
    git -C "$TEST_PROJECT" config user.email "test@example.com"
    git -C "$TEST_PROJECT" config user.name "Test User"

    # Create initial commit
    printf '# Test\n' > "$TEST_PROJECT/README.md"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "initial commit" >/dev/null 2>&1

    reset_config_state
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/knowledge-loop.sh"

    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_PROJECT/.worktrees" ;;
            *) echo "" ;;
        esac
    }

    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# extract_fix_commits
# ====================

@test "extract_fix_commits returns empty for no fix commits" {
    result="$(extract_fix_commits "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "extract_fix_commits finds fix: commits" {
    printf 'buggy\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: use perl instead of sed for macOS" >/dev/null 2>&1

    result="$(extract_fix_commits "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"fix: use perl instead of sed for macOS"* ]]
}

@test "extract_fix_commits ignores non-fix commits" {
    printf 'feature\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "feat: add new feature" >/dev/null 2>&1

    result="$(extract_fix_commits "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "extract_fix_commits respects since parameter" {
    printf 'old fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    # Commit with a past date
    GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
        git -C "$TEST_PROJECT" commit -m "fix: old fix" >/dev/null 2>&1

    result="$(extract_fix_commits "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "extract_fix_commits returns empty for non-git directory" {
    local non_git="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git"
    result="$(extract_fix_commits "1 week ago" "$non_git")"
    [ -z "$result" ]
}

# ====================
# get_commit_body
# ====================

@test "get_commit_body returns commit body" {
    printf 'fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: some fix" -m "This is the reason" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(get_commit_body "$hash" "$TEST_PROJECT")"
    [[ "$result" == *"This is the reason"* ]]
}

@test "get_commit_body returns empty for no body" {
    printf 'fix2\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: no body fix" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(get_commit_body "$hash" "$TEST_PROJECT")"
    [ -z "$result" ]
}

# ====================
# extract_new_decisions
# ====================

@test "extract_new_decisions returns empty when no decisions exist" {
    result="$(extract_new_decisions "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "extract_new_decisions finds new decision files" {
    mkdir -p "$TEST_PROJECT/docs/decisions"
    printf '# 005: Test Decision\n\nSome content\n' > "$TEST_PROJECT/docs/decisions/005-test.md"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "docs: add decision 005" >/dev/null 2>&1

    result="$(extract_new_decisions "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"docs/decisions/005-test.md"* ]]
}

@test "extract_new_decisions skips README.md" {
    mkdir -p "$TEST_PROJECT/docs/decisions"
    printf '# Decisions\n' > "$TEST_PROJECT/docs/decisions/README.md"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "docs: add decisions README" >/dev/null 2>&1

    result="$(extract_new_decisions "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

# ====================
# get_decision_title
# ====================

@test "get_decision_title extracts first heading" {
    mkdir -p "$TEST_PROJECT/docs/decisions"
    printf '# 005: Test Decision Title\n\nContent here\n' > "$TEST_PROJECT/docs/decisions/005-test.md"

    result="$(get_decision_title "docs/decisions/005-test.md" "$TEST_PROJECT")"
    [ "$result" = "005: Test Decision Title" ]
}

@test "get_decision_title returns empty for missing file" {
    result="$(get_decision_title "docs/decisions/nonexistent.md" "$TEST_PROJECT")"
    [ -z "$result" ]
}

# ====================
# check_agents_duplicate
# ====================

@test "check_agents_duplicate returns 1 when no AGENTS.md" {
    run check_agents_duplicate "some constraint" "$TEST_PROJECT/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "check_agents_duplicate returns 1 for non-duplicate" {
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

- Bats並列テスト: 16ジョブでハング
- マーカー検出: pipe-pane+grepで全出力を記録

## 注意事項
EOF

    run check_agents_duplicate "completely unrelated unique thing xyz123" "$TEST_PROJECT/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "check_agents_duplicate returns 0 for duplicate" {
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

- Bats並列テスト: 16ジョブでハング
- マーカー検出: pipe-pane+grepで全出力を記録

## 注意事項
EOF

    run check_agents_duplicate "Bats並列テスト ハング ジョブ" "$TEST_PROJECT/AGENTS.md"
    [ "$status" -eq 0 ]
}

# ====================
# extract_tracker_failures
# ====================

@test "extract_tracker_failures returns empty when no tracker file" {
    result="$(extract_tracker_failures "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "extract_tracker_failures counts error types" {
    mkdir -p "$TEST_PROJECT/.worktrees/.status"
    cat > "$TEST_PROJECT/.worktrees/.status/tracker.jsonl" << 'EOF'
{"issue":1,"result":"error","error_type":"test_failure","timestamp":"2026-02-10T00:00:00Z"}
{"issue":2,"result":"error","error_type":"test_failure","timestamp":"2026-02-10T00:00:00Z"}
{"issue":3,"result":"success","timestamp":"2026-02-10T00:00:00Z"}
{"issue":4,"result":"error","error_type":"merge_conflict","timestamp":"2026-02-10T00:00:00Z"}
EOF

    result="$(extract_tracker_failures "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"test_failure"* ]]
    [[ "$result" == *"merge_conflict"* ]]
}

# ====================
# _score_to_stars
# ====================

@test "_score_to_stars returns 3 stars for score >= 10" {
    result="$(_score_to_stars 10)"
    [ "$result" = "★★★" ]
    result="$(_score_to_stars 15)"
    [ "$result" = "★★★" ]
}

@test "_score_to_stars returns 2 stars for score >= 5" {
    result="$(_score_to_stars 5)"
    [ "$result" = "★★☆" ]
    result="$(_score_to_stars 9)"
    [ "$result" = "★★☆" ]
}

@test "_score_to_stars returns 1 star for score >= 2" {
    result="$(_score_to_stars 2)"
    [ "$result" = "★☆☆" ]
    result="$(_score_to_stars 4)"
    [ "$result" = "★☆☆" ]
}

@test "_score_to_stars returns 0 stars for score < 2" {
    result="$(_score_to_stars 1)"
    [ "$result" = "☆☆☆" ]
    result="$(_score_to_stars 0)"
    [ "$result" = "☆☆☆" ]
}

# ====================
# generate_knowledge_proposals
# ====================

@test "generate_knowledge_proposals outputs header" {
    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"Knowledge Loop Analysis"* ]]
}

@test "generate_knowledge_proposals reports no constraints when none found" {
    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"No new constraints found"* ]]
}

@test "generate_knowledge_proposals finds fix commit constraints" {
    printf 'bugfix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: prevent set -e from killing watcher" >/dev/null 2>&1

    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"prevent set -e from killing watcher"* ]]
    [[ "$result" == *"Top"* ]]
    [[ "$result" == *"insights"* ]]
}

@test "generate_knowledge_proposals skips duplicates in AGENTS.md" {
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

- prevent set from killing watcher process

## 注意事項
EOF

    printf 'bugfix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: prevent set -e from killing watcher" >/dev/null 2>&1

    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"No new constraints found"* ]]
}

# ====================
# apply_knowledge_proposals
# ====================

@test "apply_knowledge_proposals returns 2 when AGENTS.md missing" {
    run apply_knowledge_proposals "1 week ago" "$TEST_PROJECT"
    [ "$status" -eq 2 ]
}

@test "apply_knowledge_proposals returns 1 when no new constraints" {
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

## 注意事項
EOF

    run apply_knowledge_proposals "1 week ago" "$TEST_PROJECT"
    [ "$status" -eq 1 ]
}

@test "apply_knowledge_proposals appends constraints to AGENTS.md" {
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

- existing constraint

## 注意事項

- note 1
EOF

    printf 'bugfix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: use perl for macOS compatibility" >/dev/null 2>&1

    run apply_knowledge_proposals "1 week ago" "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    local content
    content="$(cat "$TEST_PROJECT/AGENTS.md")"
    [[ "$content" == *"use perl for macOS compatibility"* ]]
    [[ "$content" == *"existing constraint"* ]]
    [[ "$content" == *"注意事項"* ]]
}

# ====================
# collect_knowledge_context
# ====================

# ====================
# categorize_commit
# ====================

@test "categorize_commit returns テスト安定性 for test-only changes" {
    mkdir -p "$TEST_PROJECT/test"
    printf 'test\n' > "$TEST_PROJECT/test/foo.bats"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: stabilize flaky test" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(categorize_commit "$hash" "$TEST_PROJECT")"
    [ "$result" = "テスト安定性" ]
}

@test "categorize_commit returns マーカー検出 for marker.sh changes" {
    mkdir -p "$TEST_PROJECT/lib"
    printf 'marker\n' > "$TEST_PROJECT/lib/marker.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: improve marker detection" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(categorize_commit "$hash" "$TEST_PROJECT")"
    [ "$result" = "マーカー検出" ]
}

@test "categorize_commit returns CI関連 for ci files" {
    mkdir -p "$TEST_PROJECT/lib"
    printf 'ci\n' > "$TEST_PROJECT/lib/ci-fix.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: CI retry logic" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(categorize_commit "$hash" "$TEST_PROJECT")"
    [ "$result" = "CI関連" ]
}

@test "categorize_commit returns 一般 for unmatched files" {
    printf 'general\n' > "$TEST_PROJECT/something.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: some general fix" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    result="$(categorize_commit "$hash" "$TEST_PROJECT")"
    [ "$result" = "一般" ]
}

# ====================
# score_commit
# ====================

@test "score_commit gives higher score for issue references" {
    printf 'fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: handle edge case" -m "Refs #123" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    local score
    score="$(score_commit "$hash" "fix: handle edge case" "$TEST_PROJECT")"
    [ "$score" -ge 2 ]
}

@test "score_commit gives lower score for typo fixes" {
    printf 'typo\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: typo in readme" >/dev/null 2>&1

    local hash
    hash="$(git -C "$TEST_PROJECT" log -1 --format="%h")"
    local score
    score="$(score_commit "$hash" "fix: typo in readme" "$TEST_PROJECT")"
    [ "$score" -le 1 ]
}

# ====================
# group_commits_by_category
# ====================

@test "group_commits_by_category groups commits" {
    mkdir -p "$TEST_PROJECT/lib"
    printf 'fix1\n' > "$TEST_PROJECT/lib/marker.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: marker detection issue 1" >/dev/null 2>&1

    printf 'fix2\n' >> "$TEST_PROJECT/lib/marker.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: marker detection issue 2" >/dev/null 2>&1

    result="$(group_commits_by_category "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"CATEGORY:マーカー検出"* ]]
    [[ "$result" == *"COUNT:2"* ]]
}

@test "group_commits_by_category returns empty for no commits" {
    result="$(group_commits_by_category "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

# ====================
# generate_knowledge_proposals with top_n
# ====================

@test "generate_knowledge_proposals respects top_n limit" {
    # Create commits in different categories
    mkdir -p "$TEST_PROJECT/lib" "$TEST_PROJECT/test"

    printf 'a\n' > "$TEST_PROJECT/lib/marker.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: marker fix 1" >/dev/null 2>&1

    printf 'b\n' > "$TEST_PROJECT/lib/ci-fix.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: ci fix 1" >/dev/null 2>&1

    printf 'c\n' > "$TEST_PROJECT/something.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: general fix" >/dev/null 2>&1

    # With top_n=1, should only show 1 insight
    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT" 1)"
    [[ "$result" == *"Top 1 insights"* ]]
    # Should mention "Use --all"
    [[ "$result" == *"--all"* ]]
}

@test "generate_knowledge_proposals shows all with top_n=0" {
    mkdir -p "$TEST_PROJECT/lib"

    printf 'a\n' > "$TEST_PROJECT/lib/marker.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: marker fix" >/dev/null 2>&1

    printf 'b\n' > "$TEST_PROJECT/lib/ci-fix.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: ci fix" >/dev/null 2>&1

    result="$(generate_knowledge_proposals "1 week ago" "$TEST_PROJECT" 0)"
    [[ "$result" == *"Top 2 insights"* ]]
    [[ "$result" != *"--all"* ]]
}

# ====================
# collect_knowledge_context (updated)
# ====================

@test "collect_knowledge_context returns empty when nothing found" {
    result="$(collect_knowledge_context "1 week ago" "$TEST_PROJECT")"
    [ -z "$result" ]
}

@test "collect_knowledge_context includes fix commit context" {
    printf 'bugfix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: handle UTF-8 edge case" >/dev/null 2>&1

    result="$(collect_knowledge_context "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"知見"* ]]
    [[ "$result" == *"handle UTF-8 edge case"* ]]
}

@test "collect_knowledge_context includes decision context" {
    mkdir -p "$TEST_PROJECT/docs/decisions"
    printf '# 005: Important Decision\n\nContent\n' > "$TEST_PROJECT/docs/decisions/005-test.md"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "docs: add decision 005" >/dev/null 2>&1

    result="$(collect_knowledge_context "1 week ago" "$TEST_PROJECT")"
    [[ "$result" == *"設計判断"* ]]
    [[ "$result" == *"Important Decision"* ]]
}
