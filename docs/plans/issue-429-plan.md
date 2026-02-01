# Implementation Plan for Issue #429

## Summary
Fix a bug in `test/lib/cleanup-plans.bats` where test files are incorrectly created in the project root's `docs/plans/` directory instead of the test temporary directory.

## Problem
The test case `cleanup_closed_issue_plans shows count of deleted files` creates test files in the wrong location:

1. Lines 393-396 create files in the current working directory (project root)
2. Only after that does `cd "$BATS_TEST_TMPDIR"` change to the test directory
3. This leaves orphaned files in the project root that can cause worktree cleanup issues

## Impact
- Untracked files `docs/plans/issue-101-plan.md` and `docs/plans/issue-102-plan.md` remain in the project
- These files get copied when creating worktrees
- Causes worktree deletion failures (related to issue #427)

## Solution

### Step 1: Fix the test file
Remove the duplicate file creation lines (393-396) that create files in the wrong location before `cd`:

```diff
@test "cleanup_closed_issue_plans shows count of deleted files" {
    mock_gh_with_issues
    
-    # 複数のクローズ済みIssue用計画書
-    mkdir -p "docs/plans"
-    echo "# Plan" > "docs/plans/issue-101-plan.md"
-    echo "# Plan" > "docs/plans/issue-102-plan.md"
-    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-101-plan.md
    echo "# Plan" > docs/plans/issue-102-plan.md
    ...
}
```

### Step 2: Clean up orphaned files
Remove the incorrectly created files:
- `docs/plans/issue-101-plan.md`
- `docs/plans/issue-102-plan.md`

## Affected Files
- `test/lib/cleanup-plans.bats` - Fix the test case
- `docs/plans/issue-101-plan.md` - Delete orphaned file
- `docs/plans/issue-102-plan.md` - Delete orphaned file

## Testing
1. Run the specific test: `bats test/lib/cleanup-plans.bats -f "shows count of deleted files"`
2. Verify no files are created in project root's `docs/plans/`
3. Run all cleanup-plans tests to ensure no regressions

## Risk Assessment
- **Risk**: Low - Simple test fix, no production code changes
- **Rollback**: Easy - Can revert the commit if needed
