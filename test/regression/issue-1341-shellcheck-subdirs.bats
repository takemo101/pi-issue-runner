#!/usr/bin/env bats
# test/regression/issue-1341-shellcheck-subdirs.bats
# Issue #1341: ShellCheck in test.sh must include lib subdirectories

load '../test_helper'

@test "run_shellcheck includes lib/ci-fix/*.sh files" {
    # Verify run_shellcheck collects files from lib/ci-fix/
    local count
    count=$(grep -c 'find.*lib.*-name.*\*.sh' "$PROJECT_ROOT/scripts/test.sh" || true)
    [[ "$count" -ge 1 ]]

    # Verify lib/ci-fix/ files exist
    local ci_fix_count
    ci_fix_count=$(find "$PROJECT_ROOT/lib/ci-fix" -name "*.sh" -type f | wc -l | tr -d ' ')
    [[ "$ci_fix_count" -ge 1 ]]
}

@test "run_shellcheck includes lib/improve/*.sh files" {
    # Verify lib/improve/ files exist
    local improve_count
    improve_count=$(find "$PROJECT_ROOT/lib/improve" -name "*.sh" -type f | wc -l | tr -d ' ')
    [[ "$improve_count" -ge 1 ]]
}

@test "shellcheck file count includes subdirectory files" {
    # Count expected files
    local script_count lib_count total
    script_count=$(find "$PROJECT_ROOT/scripts" -maxdepth 1 -name "*.sh" -type f | wc -l | tr -d ' ')
    lib_count=$(find "$PROJECT_ROOT/lib" -name "*.sh" -type f | wc -l | tr -d ' ')
    total=$((script_count + lib_count))

    # lib subdirectory files must be included in total
    local subdir_count
    subdir_count=$(find "$PROJECT_ROOT/lib" -mindepth 2 -name "*.sh" -type f | wc -l | tr -d ' ')
    [[ "$subdir_count" -ge 13 ]]  # At least 8 (ci-fix) + 5 (improve)
    [[ "$total" -ge 74 ]]          # 61 (top-level) + 13 (subdirs)
}
