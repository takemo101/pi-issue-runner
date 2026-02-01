# Implementation Plan for Issue #427

## Overview
Fix the bug where `cleanup.sh` fails to remove worktrees with untracked files but incorrectly reports success.

## Issue Analysis

### Root Cause
1. When `remove_worktree` is called without `force=true`, it runs `git worktree remove "$worktree_path"` without `--force`
2. If the worktree has untracked files, git fails with exit code 128
3. The function checks if the worktree still exists using `git worktree list --porcelain | grep -q "^worktree $worktree_path$"`
4. Due to path normalization issues (symlinks like `/var` vs `/private/var` on macOS), the grep might fail even though the worktree still exists
5. When grep fails, the else branch incorrectly logs "Worktree already removed" and returns success

### Affected Files
- `lib/worktree.sh` - Main fix needed in `remove_worktree` function

## Implementation Steps

1. **Fix path comparison in `remove_worktree`**
   - Normalize the worktree path before comparison using `pwd -P` to resolve symlinks
   - Normalize paths from `git worktree list` for accurate comparison

2. **Ensure proper error reporting**
   - Only report "Worktree already removed" when we're certain it no longer exists
   - Fix the logic to properly detect when removal actually succeeded vs failed

3. **Add test coverage**
   - Add test for the path normalization edge case

## Testing Strategy

1. Run existing tests to ensure no regression
2. Test the fix with actual worktree containing untracked files
3. Verify error is properly reported when removal fails

## Risk and Mitigation

- **Risk**: Path normalization might have edge cases on different platforms
- **Mitigation**: Use standard `pwd -P` which is POSIX-compliant

## Expected Result

After the fix:
- When worktree has untracked files and removal fails, it should correctly report the failure
- The function should return non-zero exit code on failure
- `cleanup.sh` should properly detect the failure and report it
