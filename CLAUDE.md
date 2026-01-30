# Pi Issue Runner - Claude Development Guide

## Technology Stack

This project uses **Bun** as the primary JavaScript runtime and build tool.

## Commands

### Development
```bash
# Run in development mode
bun run dev run --issue 42

# Watch mode for tests
bun test --watch
```

### Build
```bash
# Build to JavaScript
bun run build

# Build standalone binary
bun run build:binary
```

### Testing
```bash
# Run all tests
bun test

# Run specific test file
bun test src/core/worktree.test.ts
```

## Bun-specific APIs

- Use `Bun.file()` for file operations (preferred over `node:fs`)
- Use `Bun.spawn()` for process execution
- Use `Bun.write()` for writing files
- Use `Bun.sleep()` for delays
- Native TypeScript support (no transpilation needed)

## File Structure

```
src/
├── cli.ts              # CLI entry point
├── commands/           # Command implementations
├── core/               # Core business logic
└── utils/              # Utility functions
```

## Development Guidelines

1. **TypeScript**: Use strict mode, explicit types
2. **Error Handling**: Use custom error classes from `core/errors.ts`
3. **Logging**: Use the centralized logger from `core/logger.ts`
4. **Testing**: Write tests using `bun:test`
5. **Documentation**: Update docs/ when adding features

## Running Examples

```bash
# Create a task from Issue #42
bun run dev run --issue 42

# Run multiple issues in parallel
bun run dev run --issues 42,43,44

# Check status
bun run dev status

# View logs
bun run dev logs --task pi-issue-42
```

## Debugging

```bash
# Verbose logging
bun run dev run --issue 42 --verbose

# Show configuration
bun run dev config --show

# Validate configuration
bun run dev config --validate
```

## Notes for AI Assistants

- Default to Bun APIs over Node.js APIs
- Use `bun` command instead of `node` or `npm`
- TypeScript runs directly, no compilation step needed
- Tests use `bun:test` framework
- Build process uses `bun build` for bundling
