# Pi Issue Runner - Subagents

pi-issue-runner 用の専門家エージェント定義です。

## エージェント一覧

| エージェント | 役割 | メタデータ |
|------------|------|-----------|
| `orchestrator` | 全体統括・戦略立案 | `tools: read, grep, find, ls, bash` |
| `explorer` | コードベース探索 | `tools: read, grep, find, ls, bash` |
| `designer` | 設計・構成決定 | `tools: read, grep, find, ls, bash` |
| `implementer` | 実装 | `tools: read, write, edit, bash`, `skill: safe-bash` |
| `reviewer` | レビュー | `tools: read, grep, bash` |
| `tester` | テスト作成・実行 | `tools: read, bash` |
| `librarian` | ドキュメント管理 | `tools: read, write, edit` |
| `fixer` | 修正 | `tools: read, write, edit, bash` |

## メタデータ形式

各エージェントは YAML frontmatter で定義されています：

```yaml
---
name: agent-name
description: Brief description of the agent's role
tools: tool1, tool2, tool3
defaultProgress: true
skill: skill-name  # optional
---
```

| フィールド | 説明 | 必須 |
|-----------|------|------|
| `name` | エージェント名 | ✅ |
| `description` | エージェントの説明 | ✅ |
| `tools` | 使用可能なツール（カンマ区切り） | ✅ |
| `defaultProgress` | 進捗管理を有効化 | ✅ |
| `skill` | 注入するスキル（オプション） | ❌ |

## 使用方法

### 基本的な使い方

```javascript
// 単一エージェントの使用
subagent({
  agent: "implementer",
  task: "lib/new-module.sh を作成"
})
```

### 並列実行

```javascript
// 複数エージェントを並列実行
subagent({
  tasks: [
    { agent: "implementer", task: "lib/module/a.sh を作成" },
    { agent: "implementer", task: "lib/module/b.sh を作成" },
    { agent: "tester", task: "test/lib/module.bats を作成" }
  ]
})
```

### ワークフロー例

```javascript
// 完全な開発フロー
subagent({
  tasks: [
    { agent: "explorer", task: "コードベース構造を分析" },
    { agent: "designer", task: "実装設計を作成" },
    { 
      agent: "implementer", 
      task: "設計に基づいて実装"
    },
    { agent: "tester", task: "テストを作成・実行" },
    { agent: "reviewer", task: "実装をレビュー" },
    { agent: "librarian", task: "AGENTS.md を更新" }
  ]
})
```

## エージェント間の連携

1. **Orchestrator** が全体計画を立案
2. **Explorer** が構造を分析 → Designer/Implementer に情報提供
3. **Designer** が設計 → Implementer に設計書を引き渡し
4. **Implementer** が実装 → Reviewer/Tester にレビュー依頼
5. **Reviewer** が承認 → Librarian がドキュメント更新
6. **Fixer** がレビュー指摘やエラーを修正

## 注意事項

- 各エージェントは `.md` ファイルとして定義（YAML frontmatter + Markdown body）
- subagent の完了は自動的に検出されるため、明示的な完了マーカーは不要
- エージェント内でさらに subagent を呼び出すことで並列化が可能
