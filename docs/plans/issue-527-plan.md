# Implementation Plan for Issue #527

## Overview
Fix hardcoded `docs/plans` paths to use `get_config plans_dir` for consistent configuration handling.

## Affected Files

### 1. `lib/notify.sh`
- **Line**: ~168 (in `handle_complete` function)
- **Current**: `local plan_file="docs/plans/issue-${issue_number}-plan.md"`
- **Fix**: Use `$(get_config plans_dir)` instead of hardcoded path

### 2. `lib/cleanup-plans.sh`
- **Line**: ~125 (in `cleanup_closed_issue_plans` function)
- **Current**: `local plans_dir="docs/plans"`
- **Fix**: Use `$(get_config plans_dir)` instead of hardcoded path

## Implementation Steps

1. **Fix `lib/notify.sh`**
   - Modify `handle_complete` to use `get_config plans_dir`
   - Ensure config is loaded before using get_config

2. **Fix `lib/cleanup-plans.sh`**
   - Modify `cleanup_closed_issue_plans` to use `get_config plans_dir`
   - The function already sources config.sh, so get_config should be available

3. **Update Tests**
   - Add test in `test/lib/notify.bats` for custom plans_dir
   - Add test in `test/lib/cleanup-plans.bats` for custom plans_dir

## Testing Strategy

- Test that `handle_complete` deletes plan files from custom plans_dir
- Test that `cleanup_closed_issue_plans` works with custom plans_dir
- Ensure existing tests still pass

## Risks and Mitigation

- **Risk**: Tests may fail if they rely on hardcoded paths
- **Mitigation**: Update tests to use mocked `get_config` with custom paths
