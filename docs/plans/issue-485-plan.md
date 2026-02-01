# Issue #485 Implementation Plan

## Overview
Add comprehensive tests for the dependency check functionality in `run.sh` to `test/scripts/run.bats`.

## Impact Scope
- **Target File**: `test/scripts/run.bats`
- **Related Files**: 
  - `scripts/run.sh` (the script being tested)
  - `lib/github.sh` (contains `check_issue_blocked` function)
  - `test/test_helper.bash` (mocking utilities)

## Implementation Steps

1. **Analyze existing tests**: Review current test structure and mocking patterns
2. **Add missing test cases**:
   - Exit code 2 when issue is blocked
   - Shows blocking issues when blocked
   - Shows blocker details with issue number and title
   - Suggests --ignore-blockers when blocked
   - Proceeds with --ignore-blockers even when blocked
   - Shows warning when using --ignore-blockers
   - --help shows --ignore-blockers option (already exists, verify)

3. **Mock strategy**:
   - Create mock `gh` command that simulates blocked issue scenarios
   - Mock `check_issue_blocked` to return exit code 1 with blocker JSON
   - Source github.sh and override functions for isolated testing

4. **Run tests** to verify all pass

## Test Design

### Mock Approach
Since testing `run.sh` directly would require full integration setup (tmux, git worktree), we'll:
1. Source `lib/github.sh` directly to test `check_issue_blocked` behavior
2. Create mock `gh` that returns blocked issue data
3. Verify exit codes and output content

### Test Cases Detail

1. **exit code 2 when blocked**: Verify `check_issue_blocked` returns 1, which causes run.sh to exit 2
2. **shows blocking issues**: Verify output contains blocker issue numbers
3. **shows blocker details**: Verify output format includes `#number: title (state)`
4. **suggests --ignore-blockers**: Verify output contains the suggestion message
5. **proceeds with --ignore-blockers**: Verify the flag bypasses the check
6. **shows warning with --ignore-blockers**: Verify warning message is displayed
7. **help shows option**: Already implemented, verify existing test passes

## Risk and Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mock complexity | Medium | Use existing test_helper patterns |
| Test isolation | Low | Use BATS_TEST_TMPDIR for isolation |
| CI environment | Low | Mocks don't require real GitHub access |

## Estimated Lines
~40-50 lines of test code
