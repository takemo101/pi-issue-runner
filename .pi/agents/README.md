# Pi Issue Runner - Subagents

pi-issue-runner 用の専門家エージェント定義です。

## エージェント一覧

| エージェント | 役割 | 使用タイミング |
|------------|------|--------------|
| `orchestrator` | 全体統括・戦略立案 | Issue開始時 |
| `explorer` | コードベース探索 | 構造把握が必要な時 |
| `designer` | 設計・構成決定 | 実装前の設計時 |
| `implementer` | 実装 | コーディング時 |
| `reviewer` | レビュー | 実装完了後 |
| `tester` | テスト作成・実行 | 品質保証時 |
| `librarian` | ドキュメント更新 | ドキュメント整備時 |
| `fixer` | 修正 | エラー/指摘対応時 |

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
      task: "設計に基づいて実装",
      // 並列サブタスク
      subtasks: [
        "lib/module/core.sh",
        "lib/module/utils.sh",
        "scripts/script.sh"
      ]
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

## 完了マーカー

各エージェントは完了時に固有のマーカーを出力します：

| エージェント | 完了マーカー |
|------------|------------|
| orchestrator | `###ORCHESTRATION_COMPLETE###` |
| explorer | `###EXPLORATION_COMPLETE###` |
| designer | `###DESIGN_COMPLETE###` |
| implementer | `###IMPLEMENTATION_COMPLETE###` |
| reviewer | `###REVIEW_COMPLETE###` |
| tester | `###TESTING_COMPLETE###` |
| librarian | `###DOCUMENTATION_COMPLETE###` |
| fixer | `###FIX_COMPLETE###` |

## 注意事項

- 各エージェントは `.md` ファイルとして定義
- テンプレート変数は展開されてから subagent に渡される
- エージェント内でさらに subagent を呼び出すことで並列化が可能
