# Coding Standards for pi-issue-runner

## Shell Script Header Format

All shell scripts (`.sh` files) in this project should follow this standardized header format:

### Template

> **Note**: The following is a template for creating new scripts.
> Replace `script-name` with your actual script name (e.g., `run.sh`, `cleanup.sh`, etc.).

```bash
#!/usr/bin/env bash
# ============================================================================
# script-name.sh - Brief description (Japanese or English)
#
# Detailed description (multiple lines allowed)
# - Purpose of the script
# - Main functionality
# - Special notes
#
# Usage: ./scripts/script-name.sh [options]
#        ./scripts/script-name.sh <required-arg> [optional-arg]
#
# Arguments:
#   required-arg    Description of required argument
#   optional-arg    Description of optional argument
#
# Options:
#   -h, --help      Show help message
#   -v, --verbose   Enable verbose output
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - Dependency error
#
# Examples:
#   ./scripts/script-name.sh 42
#   ./scripts/script-name.sh 42 --verbose
# ============================================================================
```

### Header Components

#### 1. Shebang
```bash
#!/usr/bin/env bash
```
- Always use `#!/usr/bin/env bash` for portability

#### 2. Script Name and Brief Description
```bash
# script-name.sh - Brief description
```
- Keep it concise (one line)
- Can be in Japanese or English

#### 3. Detailed Description
```bash
#
# Detailed description (multiple lines allowed)
# - Purpose of the script
# - Main functionality
# - Special notes
#
```
- Explain what the script does
- List main features
- Include any important notes

#### 4. Usage
```bash
# Usage: ./scripts/script-name.sh [options]
#        ./scripts/script-name.sh <required-arg> [optional-arg]
#
```
- Show command syntax
- Use `<arg>` for required arguments
- Use `[arg]` for optional arguments

#### 5. Arguments
```bash
# Arguments:
#   required-arg    Description of required argument
#   optional-arg    Description of optional argument
#
```
- List all arguments with descriptions
- Include type/format information if relevant

#### 6. Options
```bash
# Options:
#   -h, --help      Show help message
#   -v, --verbose   Enable verbose output
#
```
- List all command-line options
- Show both short and long forms if available

#### 7. Exit Codes
```bash
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - Dependency error
#
```
- Document all non-zero exit codes
- Explain what each code means

#### 8. Examples
```bash
# Examples:
#   ./scripts/script-name.sh 42
#   ./scripts/script-name.sh 42 --verbose
# ============================================================================
```
- Provide practical usage examples
- Show common use cases

### Style Guidelines

1. **Line Width**: Keep comments within 80 characters when possible
2. **Language**: Japanese or English (consistent within a file)
3. **Indentation**: Use 2 spaces for alignment within comments
4. **Separators**: Use `# ===...` for the top and bottom borders

### Example: Simple Script

```bash
#!/usr/bin/env bash
# ============================================================================
# attach.sh - Attach to a tmux session
#
# Connects to an existing pi-issue-runner tmux session by session name
# or issue number.
#
# Usage: ./scripts/attach.sh <session-name|issue-number>
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Successfully attached to session
#   1 - Session not found or error occurred
#
# Examples:
#   ./scripts/attach.sh pi-issue-42
#   ./scripts/attach.sh 42
# ============================================================================
```

### Example: Complex Script

```bash
#!/usr/bin/env bash
# ============================================================================
# run.sh - Execute GitHub Issue in isolated worktree
#
# Creates a Git worktree from a GitHub Issue and launches a coding agent
# in a tmux session. Supports multiple agent types including pi,
# Claude Code, OpenCode, and custom agents.
#
# Usage: ./scripts/run.sh <issue-number> [options]
#
# Arguments:
#   issue-number    GitHub Issue number to process
#
# Options:
#   -b, --branch NAME   Custom branch name (default: issue-<num>-<title>)
#   --base BRANCH       Base branch (default: HEAD)
#   -w, --workflow NAME Workflow name (default: default)
#   --no-attach         Don't attach to session after creation
#   --no-cleanup        Disable auto-cleanup after agent exits
#   --reattach          Attach to existing session if available
#   --force             Remove and recreate existing session/worktree
#   --agent-args ARGS   Additional arguments for the agent
#   --list-workflows    List available workflows
#   --ignore-blockers   Skip dependency check and force execution
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success or attached to existing session
#   1 - General error or invalid arguments
#   2 - Issue blocked by dependencies
#
# Examples:
#   ./scripts/run.sh 42
#   ./scripts/run.sh 42 -w simple
#   ./scripts/run.sh 42 --no-attach
#   ./scripts/run.sh 42 --force
# ============================================================================
```

## Additional Coding Standards

### Strict Mode
Always include at the beginning of the script (after the header):
```bash
set -euo pipefail
```

### Script Directory
Define script directory for sourcing libraries:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Function Definitions
- Use lowercase with underscores: `my_function_name`
- Add brief comments for complex functions
- Use `local` for local variables

### Error Handling
- Use `log_error` function from `lib/log.sh`
- Always provide meaningful error messages
- Exit with appropriate exit codes
