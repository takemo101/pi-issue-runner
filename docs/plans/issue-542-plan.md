# Issue #542 Implementation Plan

## Overview

Enhance test coverage for `scripts/run-batch.sh` by adding comprehensive behavioral tests that verify actual execution flows, not just code existence.

## Current State

- 41 tests exist, all passing
- Many tests only check if code/strings exist in the script
- Behavioral tests mostly use `--dry-run` mode

## Required Enhancements

### 1. Enhanced --dry-run Tests
- Add verification of execution plan structure
- Test layer grouping output format

### 2. Sequential Execution Tests
- Test actual sequential execution behavior (with mocked run.sh)
- Verify issues are processed in order

### 3. Continue-on-error Tests
- Test that execution continues after a layer failure
- Test error aggregation at the end

### 4. Timeout Tests
- Test timeout handling with short timeouts
- Verify proper error message on timeout

### 5. Circular Dependency Tests
- Already covered well - no changes needed

### 6. Empty Issue List Tests
- Already covered well - no changes needed

### 7. Additional Edge Cases
- Test single issue execution
- Test all issues in same layer (no dependencies)
- Test workflow option passing
- Test base branch option passing

## Implementation Steps

1. Review existing tests for gaps
2. Add behavioral test helpers to test_helper.bash if needed
3. Add new comprehensive tests to run-batch.bats
4. Run all tests to verify
5. Commit changes

## Files to Modify

- `test/scripts/run-batch.bats` - Add new behavioral tests

## Acceptance Criteria

- [x] All existing 41 tests continue to pass
- [x] New behavioral tests added for sequential execution (tests 42-46)
- [x] New behavioral tests added for continue-on-error (tests 26-27 enhanced)
- [x] New behavioral tests added for timeout handling (tests 47-50)
- [x] New tests for edge cases (single issue, same layer, etc.) (tests 51-61)
