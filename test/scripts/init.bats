#!/usr/bin/env bats
# init.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用ディレクトリを作成
    export TEST_REPO="$BATS_TEST_TMPDIR/test_repo"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init -q
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "init.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [[ "$output" == *"--full"* ]]
    [[ "$output" == *"--minimal"* ]]
    [[ "$output" == *"--force"* ]]
}

# ====================
# 標準モードでの初期化テスト
# ====================

@test "init.sh creates .pi-runner.yaml" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -f ".pi-runner.yaml" ]
}

@test "init.sh creates .worktrees/ directory" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -d ".worktrees" ]
}

@test "init.sh creates docs/plans/ directory" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -d "docs/plans" ]
}

@test "init.sh creates docs/decisions/ directory" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -d "docs/decisions" ]
}

@test "init.sh adds known-constraints section to AGENTS.md" {
    echo "# My Project" > AGENTS.md
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -qF "## 既知の制約" AGENTS.md
}

@test "init.sh skips AGENTS.md when not present" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENTS.md が見つかりません"* ]]
}

@test "init.sh does not duplicate known-constraints section" {
    cat > AGENTS.md << 'EOF'
# My Project

## 既知の制約
- 既存の制約
EOF
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    local count
    count=$(grep -c "## 既知の制約" AGENTS.md)
    [ "$count" -eq 1 ]
}

@test "init.sh --minimal does not create docs/plans/" {
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [ ! -d "docs/plans" ]
}

@test "init.sh --minimal does not create docs/decisions/" {
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [ ! -d "docs/decisions" ]
}

@test "init.sh creates .worktrees/.gitkeep" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -f ".worktrees/.gitkeep" ]
}

@test "init.sh creates/updates .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -f ".gitignore" ]
}

@test "init.sh adds .worktrees/ to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.worktrees/' ".gitignore"
}

@test "init.sh adds .improve-logs/ to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.improve-logs/' ".gitignore"
}

@test "init.sh adds .pi-runner.yaml to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.pi-runner\.yaml' ".gitignore"
}

@test "init.sh adds .pi-runner.yml to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.pi-runner\.yml' ".gitignore"
}

@test "init.sh adds .pi-prompt-phase*.md to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.pi-prompt-phase' ".gitignore"
}

@test "init.sh .pi-runner.yaml contains worktree section" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q 'worktree:' ".pi-runner.yaml"
}

@test "init.sh output shows success message" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"初期化完了"* ]] || [[ "$output" == *"initialized"* ]] || [[ "$output" == *"success"* ]]
}

# ====================
# --minimal モードテスト
# ====================

@test "init.sh --minimal creates .pi-runner.yaml" {
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [ -f ".pi-runner.yaml" ]
}

@test "init.sh --minimal does not create .worktrees/.gitkeep" {
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [ ! -f ".worktrees/.gitkeep" ]
}

@test "init.sh --minimal shows minimal completion message" {
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [[ "$output" == *"最小初期化完了"* ]] || [[ "$output" == *"minimal"* ]]
}

# ====================
# --full モードテスト
# ====================

@test "init.sh --full creates .pi-runner.yaml" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    [ -f ".pi-runner.yaml" ]
}

@test "init.sh --full creates .worktrees/" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    [ -d ".worktrees" ]
}

@test "init.sh --full creates agents/custom.md" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    [ -f "agents/custom.md" ]
}

@test "init.sh --full creates workflows/custom.yaml" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    [ -f "workflows/custom.yaml" ]
}

@test "init.sh --full agents/custom.md contains template variables" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    grep -q '{{issue_number}}' "agents/custom.md"
}

@test "init.sh --full workflows/custom.yaml contains steps" {
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    grep -q 'steps:' "workflows/custom.yaml"
}

# ====================
# 既存ファイルの警告テスト
# ====================

@test "init.sh shows warning for existing file" {
    echo "existing content" > ".pi-runner.yaml"
    run "$PROJECT_ROOT/scripts/init.sh"
    [[ "$output" == *"既に存在します"* ]] || [[ "$output" == *"exists"* ]]
}

@test "init.sh does not overwrite existing file without --force" {
    echo "existing content" > ".pi-runner.yaml"
    run "$PROJECT_ROOT/scripts/init.sh"
    grep -q "existing content" ".pi-runner.yaml"
}

# ====================
# --force による上書きテスト
# ====================

@test "init.sh --force overwrites existing file" {
    echo "existing content" > ".pi-runner.yaml"
    run "$PROJECT_ROOT/scripts/init.sh" --force
    [ "$status" -eq 0 ]
    grep -q 'worktree:' ".pi-runner.yaml"
}

@test "init.sh --force shows overwrite message" {
    echo "existing content" > ".pi-runner.yaml"
    run "$PROJECT_ROOT/scripts/init.sh" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"上書き"* ]] || [[ "$output" == *"overw"* ]] || [[ "$output" == *"force"* ]]
}

# ====================
# Git リポジトリ外でのエラーテスト
# ====================

@test "init.sh fails outside git repo" {
    non_git_dir="$BATS_TEST_TMPDIR/non_git"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"
    
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -ne 0 ] || [[ "$output" == *"Git"* ]]
}

# ====================
# .gitignore の重複エントリ防止テスト
# ====================

@test "init.sh does not duplicate .worktrees/ entry in .gitignore" {
    echo ".worktrees/" > ".gitignore"
    "$PROJECT_ROOT/scripts/init.sh" > /dev/null 2>&1 || true
    count=$(grep -c "^\.worktrees/$" ".gitignore" || echo "0")
    [ "$count" -eq 1 ]
}

# ====================
# 孤立ステータスファイル警告テスト
# ====================

@test "init.sh warns about orphaned status files" {
    # 孤立したステータスファイルを作成
    mkdir -p ".worktrees/.status"
    echo '{"issue": 999, "status": "complete"}' > ".worktrees/.status/999.json"
    
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    # 警告メッセージが表示されること
    [[ "$output" == *"孤立した"* ]] || [[ "$output" == *"orphan"* ]] || [[ "$output" == *"cleanup.sh --orphans"* ]]
}

@test "init.sh does not warn when no orphaned status files" {
    # worktreeとステータスファイルが対応している場合
    mkdir -p ".worktrees/.status"
    mkdir -p ".worktrees/issue-100-test"
    echo '{"issue": 100, "status": "running"}' > ".worktrees/.status/100.json"
    
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    # 孤立ファイルの警告が表示されないこと
    [[ "$output" != *"孤立した"* ]] || [[ "$output" != *"cleanup.sh --orphans"* ]]
}
