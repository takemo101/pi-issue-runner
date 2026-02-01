# Implementation Plan for Issue #413

## Issue Summary

The `docs/workflows.md` file references `workflows/thorough.yaml` in multiple places:
- Line 69: As a custom workflow example
- Line 192: Another reference to the example
- Line 227: In the recommended configuration section

However, the `thorough.yaml` file does not actually exist in the `workflows/` directory.

## Analysis

The documentation presents `thorough.yaml` as:
1. An example of a custom workflow with a `test` step
2. Part of the recommended project structure for thorough workflows

The example shows:
```yaml
name: thorough
description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan
  - implement
  - test      # カスタムステップ: agents/test.md が必要
  - review
  - merge
```

## Solution

Create the `workflows/thorough.yaml` file based on the documented example. This approach:
1. Makes the documentation accurate and consistent
2. Provides users with a ready-to-use thorough workflow
3. Follows the pattern established by `default.yaml` and `simple.yaml`

## Implementation Steps

1. Create `workflows/thorough.yaml` with the content matching the documentation
2. The workflow should include the `test` step as documented
3. Document that the `test` step requires a custom agent template

## Testing

- Verify the YAML syntax is valid
- Verify the file is created in the correct location
- Verify the content matches the documentation

## Risks and Mitigation

- **Risk**: Users might expect the `test` step to work out of the box
- **Mitigation**: The documentation already notes that `test` is a custom step requiring `agents/test.md`. We'll keep this note in the workflow description.
