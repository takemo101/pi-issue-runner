# Implementation Plan: Issue #572 - Test Timeout Investigation and Improvement

## Overview

GitHub Issue #572 aims to investigate and resolve test timeouts that occur when running `./scripts/test.sh`. The tests are taking over 60 seconds, which causes timeouts. This plan outlines the investigation findings and the implementation approach to reduce test execution time.

## Investigation Findings

### Test File Count
- **lib/**: 24 test files
- **scripts/**: 14 test files
- **Total**: 38 test files

### Identified Slow Tests

Timing measurements for slowest test files:
| Test File | Execution Time |
|-----------|---------------|
| test/lib/config.bats | ~12s |
| test/lib/workflow.bats | ~12s |
| test/lib/github.bats | ~9s |
| test/lib/tmux.bats | ~7s |
| test/lib/agent.bats | ~6s |
| test/lib/daemon.bats | ~6s |

### Root Causes

1. **daemon.bats**: Contains tests with long sleep durations (2-5 seconds) for daemon process testing
   - `daemonize runs command in background`: sleep 2 + sleep 0.2
   - `stop_daemon terminates running daemon`: sleep 5 + sleep 0.2 + sleep 0.2
   - `daemon process survives parent shell exit`: sleep 3 + sleep 0.3
   - `daemonize with setsid on Linux or double fork on macOS`: sleep 2 + sleep 0.2
   - `find_daemon_pid finds running process by pattern`: sleep 3 + sleep 0.3

2. **cleanup-plans.bats**: Multiple small sleeps (0.05-0.2s) for file ordering guarantees

3. **Existing fast mode support**: One test in daemon.bats (`Issue #553: watcher survives batch timeout scenario`) already supports fast mode skipping

## Implementation Steps

### Step 1: Add Fast Mode Support to daemon.bats

Add fast mode skipping to all slow tests in daemon.bats that involve long-running processes:

```bash
# Add to each slow test:
if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
    skip "Skipping slow test in fast mode"
fi
```

Tests to modify:
1. `daemonize runs command in background` (~2.2s)
2. `daemonize writes output to log file` (~0.3s) - optional, less critical
3. `stop_daemon terminates running daemon` (~5.4s)
4. `daemon process survives parent shell exit` (~3.3s)
5. `daemonize with setsid on Linux or double fork on macOS` (~2.2s)
6. `find_daemon_pid finds running process by pattern` (~3.3s)

### Step 2: Add Fast Mode Support to cleanup-plans.bats

Add fast mode skipping to tests with cumulative sleep delays:
- `cleanup_old_plans dry_run=false deletes old files`
- `cleanup_old_plans shows deleted message`
- `cleanup_old_plans with keep_count=1 keeps only newest`
- `cleanup_old_plans uses default keep_count from config`

### Step 3: Verify test.sh Fast Mode Implementation

The test.sh already has fast mode support via:
- `--fast` command line flag
- `BATS_FAST_MODE` environment variable

Verify the environment variable is properly exported to test subprocesses.

### Step 4: Update Documentation

Update AGENTS.md or relevant documentation to mention:
- `--fast` flag availability
- `BATS_FAST_MODE` environment variable
- Which tests are skipped in fast mode

## Testing Strategy

### Before Optimization
```bash
time ./scripts/test.sh
# Expected: >60s (timeout)
```

### After Optimization
```bash
# Fast mode
time ./scripts/test.sh --fast
# Target: <60s

# Full mode (default)
time ./scripts/test.sh
# Should still work but may timeout
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Reduced test coverage in fast mode | Medium | Fast mode is optional; full CI runs use default mode |
| Tests may fail if sleeps are too short | Low | Keep existing sleep durations; only skip in fast mode |
| Documentation not updated | Low | Include documentation update in implementation |

## Success Criteria

- [x] Slow tests identified and documented
- [ ] Fast mode skipping added to daemon.bats slow tests
- [ ] Fast mode skipping added to cleanup-plans.bats slow tests
- [ ] `./scripts/test.sh --fast` completes in under 60 seconds
- [ ] All tests pass in both normal and fast modes

## Estimated Time Savings

With fast mode:
- daemon.bats: ~16.7s → ~0s (all slow tests skipped)
- cleanup-plans.bats: ~1s → ~0s (sleep-heavy tests skipped)
- **Total estimated savings**: ~17-20 seconds

This should bring the total test execution time under 60 seconds in fast mode.
