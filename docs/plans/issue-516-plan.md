# Implementation Plan for Issue #516

## Issue Summary
chore: dependency.batsのテストが存在しない

## Analysis

### Investigation Results
Upon investigation, `test/lib/dependency.bats` **already exists** and contains comprehensive tests for `lib/dependency.sh`.

### File Status
- **File Location**: `test/lib/dependency.bats`
- **File Size**: ~7KB
- **Test Count**: 12 tests
- **Test Status**: All passing ✅

### Test Coverage

The existing test file covers all major functions in `lib/dependency.sh`:

1. **get_issue_blockers_numbers** (2 tests)
   - Returns blocker numbers correctly
   - Returns empty when no blockers

2. **build_dependency_graph** (2 tests)
   - Outputs tsort format correctly
   - Handles issues without dependencies

3. **detect_cycles** (2 tests)
   - Returns 0 when no cycles
   - Returns 1 when cycle exists

4. **compute_layers** (2 tests)
   - Assigns correct depth
   - Handles independent issues

5. **group_layers** (1 test)
   - Formats layer output correctly

6. **get_issues_in_layer** (1 test)
   - Returns issues for specific layer

7. **get_max_layer** (2 tests)
   - Returns maximum layer number
   - Returns 0 for single layer

### Test Results
```
$ bats test/lib/dependency.bats
1..12
ok 1 get_issue_blockers_numbers returns blocker numbers
ok 2 get_issue_blockers_numbers returns empty when no blockers
ok 3 build_dependency_graph outputs tsort format
ok 4 build_dependency_graph handles issues without dependencies
ok 5 detect_cycles returns 0 when no cycles
ok 6 detect_cycles returns 1 when cycle exists
ok 7 compute_layers assigns correct depth
ok 8 compute_layers handles independent issues
ok 9 group_layers formats layer output
ok 10 get_issues_in_layer returns issues for specific layer
ok 11 get_max_layer returns maximum layer number
ok 12 get_max_layer returns 0 for single layer
```

### Full Test Suite Results
All 521 library tests pass:
```
$ ./scripts/test.sh lib
=== Running Bats Tests ===
1..521
ok 1 ...
...
ok 521 yaml_get_array handles empty array section
```

## Conclusion

No implementation is required as the file already exists with comprehensive test coverage. The issue can be closed with a note that the tests were already implemented.

## Action Items

- [x] Verified file exists at `test/lib/dependency.bats`
- [x] Verified all 12 tests pass
- [x] Verified full test suite (521 tests) passes
- [x] Document findings in this plan

## References

- `lib/dependency.sh` - The library being tested (315 lines)
- `test/lib/dependency.bats` - The test file (already exists)
