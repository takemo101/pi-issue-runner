#!/usr/bin/env bats
# Issue #21, #22, #23 の修正テスト（回帰テスト）

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# Issue #23: 設定ファイル名テスト
# ====================

@test "Issue #23: config uses .pi-runner.yaml" {
    grep -q '.pi-runner.yaml' "$PROJECT_ROOT/lib/config.sh"
}

# ====================
# Issue #22: セッション名テスト
# ====================

@test "Issue #22: generate_session_name with pi-issue prefix" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="pi-issue"
    export _CONFIG_LOADED="true"
    
    result="$(generate_session_name 42)"
    [ "$result" = "pi-issue-42" ]
}

@test "Issue #22: generate_session_name with dev prefix" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="dev"
    export _CONFIG_LOADED="true"
    
    result="$(generate_session_name 42)"
    [ "$result" = "dev-issue-42" ]
}

@test "Issue #22: extract from pi-issue-42" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "Issue #22: extract from dev-issue-99" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "dev-issue-99")"
    [ "$result" = "99" ]
}

@test "Issue #22: extract from pi-issue-42-feature" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "pi-issue-42-feature")"
    [ "$result" = "42" ]
}

@test "Issue #22: extract from custom-issue-123-bugfix" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "custom-issue-123-bugfix")"
    [ "$result" = "123" ]
}

# 往復テスト
@test "Issue #22: round-trip for issue 1" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="pi-issue"
    export _CONFIG_LOADED="true"
    
    session="$(generate_session_name "1")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "1" ]
}

@test "Issue #22: round-trip for issue 42" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="pi-issue"
    export _CONFIG_LOADED="true"
    
    session="$(generate_session_name "42")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "42" ]
}

@test "Issue #22: round-trip for issue 99" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="pi-issue"
    export _CONFIG_LOADED="true"
    
    session="$(generate_session_name "99")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "99" ]
}

@test "Issue #22: round-trip for issue 123" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="pi-issue"
    export _CONFIG_LOADED="true"
    
    session="$(generate_session_name "123")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "123" ]
}

# ====================
# Issue #21: プロンプト構築テスト
# ====================

@test "Issue #21: run.sh gets issue body" {
    grep -q 'get_issue_body' "$PROJECT_ROOT/scripts/run.sh"
}

@test "Issue #21: run.sh creates prompt file" {
    grep -q '.pi-prompt.md' "$PROJECT_ROOT/scripts/run.sh"
}

@test "Issue #21: run.sh includes issue title in prompt" {
    grep -q 'issue_title' "$PROJECT_ROOT/scripts/run.sh"
}

@test "Issue #21: run.sh includes issue body in prompt" {
    grep -q 'issue_body' "$PROJECT_ROOT/scripts/run.sh"
}

@test "Issue #21: run.sh uses @ to reference prompt file" {
    grep -q '@.*prompt_file' "$PROJECT_ROOT/lib/agent.sh"
}

# ====================
# Issue #289: 計画書削除テスト
# ====================

@test "Issue #289: merge.md does not contain plan deletion step in worktree" {
    # merge.md にworktree内で計画書を削除するコードが含まれていないことを確認
    # 計画書削除はホスト環境（handle_complete）で行うべき
    ! grep -q 'rm -f docs/plans/issue-{{issue_number}}-plan.md' "$PROJECT_ROOT/agents/merge.md"
}

@test "Issue #289: handle_complete deletes plan file in host environment" {
    # watch-session.sh の handle_complete が計画書を削除することを確認
    # (Issue #883/#904: notify.sh から watch-session.sh に移動)
    grep -q 'issue-.*-plan.md' "$PROJECT_ROOT/scripts/watch-session.sh"
    grep -q 'rm -f "$plan_file"' "$PROJECT_ROOT/scripts/watch-session.sh"
}
