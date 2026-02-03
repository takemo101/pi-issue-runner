#!/usr/bin/env bats
# test/lib/priority.bats - Tests for lib/priority.sh

load '../test_helper'

setup() {
    # 各テストで独立したtmpdirを作成
    export BATS_TEST_TMPDIR="$(mktemp -d)"
    export TEST_CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    # デフォルト設定ファイル作成（正しいYAML階層構造）
    cat > "$TEST_CONFIG_FILE" <<CFGEOF
worktree:
  base_dir: "${BATS_TEST_TMPDIR}/.worktrees"
pi:
  command: "echo pi"
default_branch: "main"
CFGEOF
    
    # ステータスディレクトリ作成
    mkdir -p "$BATS_TEST_TMPDIR/.worktrees/.status"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "get_priority_score_from_labels: priority:high returns 100" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:high"},{"name":"feature"}]'
    result=$(get_priority_score_from_labels "$labels_json")
    
    [ "$result" = "100" ]
}

@test "get_priority_score_from_labels: priority:medium returns 50" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:medium"}]'
    result=$(get_priority_score_from_labels "$labels_json")
    
    [ "$result" = "50" ]
}

@test "get_priority_score_from_labels: priority:low returns 10" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:low"}]'
    result=$(get_priority_score_from_labels "$labels_json")
    
    [ "$result" = "10" ]
}

@test "get_priority_score_from_labels: no priority label returns default 50" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"bug"},{"name":"feature"}]'
    result=$(get_priority_score_from_labels "$labels_json")
    
    [ "$result" = "50" ]
}

@test "get_priority_score_from_labels: empty labels returns default 50" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[]'
    result=$(get_priority_score_from_labels "$labels_json")
    
    [ "$result" = "50" ]
}

@test "calculate_issue_priority: layer 0 with high priority" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:high"}]'
    result=$(calculate_issue_priority "999" "0" "$labels_json")
    
    [ "$result" = "100" ]
}

@test "calculate_issue_priority: layer 1 reduces score by 10" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:high"}]'
    result=$(calculate_issue_priority "999" "1" "$labels_json")
    
    [ "$result" = "90" ]
}

@test "calculate_issue_priority: layer 2 reduces score by 20" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local labels_json='[{"name":"priority:medium"}]'
    result=$(calculate_issue_priority "999" "2" "$labels_json")
    
    [ "$result" = "30" ]
}

@test "filter_non_running_issues: filters out running issues" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/priority.sh"
    
    # Issue 42をrunning状態に設定
    save_status "42" "running" "test-session"
    
    local issues="40 41 42 43"
    result=$(filter_non_running_issues "$issues")
    
    # 42は除外されるべき
    [[ "$result" == *"40"* ]]
    [[ "$result" == *"41"* ]]
    [[ ! "$result" =~ (^| )42( |$) ]]
    [[ "$result" == *"43"* ]]
}

@test "filter_non_running_issues: all non-running returns all" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local issues="40 41 42"
    result=$(filter_non_running_issues "$issues")
    
    [[ "$result" == *"40"* ]]
    [[ "$result" == *"41"* ]]
    [[ "$result" == *"42"* ]]
}

@test "sort_issues_by_priority: sorts by score descending" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local issues_json='[
        {"number":1,"score":50,"layer":0},
        {"number":2,"score":100,"layer":0},
        {"number":3,"score":10,"layer":1}
    ]'
    
    result=$(sort_issues_by_priority "$issues_json")
    
    # 最初の要素が最高スコア（100）
    first_score=$(echo "$result" | jq -r '.[0].score')
    [ "$first_score" = "100" ]
    
    # 最後の要素が最低スコア（10）
    last_score=$(echo "$result" | jq -r '.[-1].score')
    [ "$last_score" = "10" ]
}

@test "sort_issues_by_priority: same score sorts by issue number ascending" {
    source "$PROJECT_ROOT/lib/priority.sh"
    
    local issues_json='[
        {"number":50,"score":100,"layer":0},
        {"number":30,"score":100,"layer":0},
        {"number":40,"score":100,"layer":0}
    ]'
    
    result=$(sort_issues_by_priority "$issues_json")
    
    # 同じスコアの場合は番号順
    first_num=$(echo "$result" | jq -r '.[0].number')
    [ "$first_num" = "30" ]
    
    second_num=$(echo "$result" | jq -r '.[1].number')
    [ "$second_num" = "40" ]
    
    third_num=$(echo "$result" | jq -r '.[2].number')
    [ "$third_num" = "50" ]
}
