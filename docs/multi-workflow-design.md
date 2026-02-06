# 設計書: `.pi-runner.yaml` での複数ワークフロー定義

**作成日**: 2026-02-06
**ステータス**: Draft

---

## 1. 背景と動機

### 現状の課題

pi-issue-runnerでは、Issueの種類に関わらず同一のワークフローが適用される。実際のプロジェクトでは、Issueの性質によって最適なワークフローは異なる：

| Issueの種類 | 現状 | 理想 |
|------------|------|------|
| バグ修正（小規模） | plan → implement → review → merge | implement → merge |
| 新機能（大規模） | plan → implement → review → merge | plan → implement → test → review → merge |
| ドキュメント修正 | plan → implement → review → merge | implement → merge（レビュー不要） |
| リファクタリング | plan → implement → review → merge | plan → implement → test → review → merge |
| CI修正 | plan → implement → review → merge | ci-fix |

現在は `workflows/*.yaml` に個別ファイルを作成すれば `--workflow` で切り替え可能だが、ファイルが散在し管理しにくい。`.pi-runner.yaml` 一箇所で全ワークフローを定義・管理したい。

### oh-my-opencode からの着想

[oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) は「カテゴリ」という概念でタスクの性質に応じた実行戦略を切り替える：

| カテゴリ | 用途 | モデル |
|---------|------|--------|
| `visual-engineering` | フロントエンド・UI | Gemini 3 Pro |
| `ultrabrain` | 深い論理的推論 | GPT-5.3 Codex |
| `deep` | 自律的問題解決 | GPT-5.3 Codex |
| `quick` | 小規模タスク | Claude Haiku 4.5 |
| `writing` | ドキュメント | Gemini 3 Flash |

各カテゴリに対して以下がカスタマイズされている：

1. **使用するモデル** — タスクの複雑度に応じた最適なモデル
2. **プロンプト補足** — カテゴリ固有のコンテキスト・指示
3. **ツール制限** — エージェントが使えるツールの制御

この思想を pi-issue-runner に取り入れ、**ワークフロー（ステップ構成）をIssueの用途に応じて切り替え可能にする**。さらに将来的には、ワークフローごとにエージェント設定（モデル・プロンプト）もカスタマイズできる拡張ポイントを設ける。

---

## 2. 設計

### 2.1 設定形式

`.pi-runner.yaml` に `workflows`（複数形）セクションを新設する。

```yaml
# .pi-runner.yaml

# ============================
# デフォルトワークフロー（従来互換）
# ============================
# -w オプション未指定時に使用される
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# ============================
# 名前付きワークフロー（新機能）
# ============================
# -w オプションで選択
workflows:
  # 小規模バグ修正向け
  quick:
    description: 小規模な変更用（実装・マージのみ）
    steps:
      - implement
      - merge

  # 大規模機能開発向け
  thorough:
    description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
    steps:
      - plan
      - implement
      - test
      - review
      - merge

  # ドキュメント修正向け
  docs:
    description: ドキュメント更新用
    steps:
      - implement
      - merge

  # CI修正向け
  ci-fix:
    description: CI失敗の自動修正
    steps:
      - ci-fix
```

#### 使い方

```bash
# デフォルトワークフロー（workflow セクション）
./scripts/run.sh 42

# 名前付きワークフロー
./scripts/run.sh 42 -w quick        # 小規模修正
./scripts/run.sh 42 -w thorough     # 徹底ワークフロー
./scripts/run.sh 42 -w docs         # ドキュメント
./scripts/run.sh 42 -w ci-fix       # CI修正
```

### 2.2 `description` フィールド

各ワークフローにオプションの `description` フィールドを持たせる。これは `--list-workflows` で表示される説明文として使われる。

```bash
$ ./scripts/run.sh --list-workflows
default: 完全なワークフロー（計画・実装・レビュー・マージ）
simple: 簡易ワークフロー（実装・マージのみ）
thorough: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
ci-fix: CI失敗を検出し自動修正
--- Project workflows (.pi-runner.yaml) ---
quick: 小規模な変更用（実装・マージのみ）
docs: ドキュメント更新用
```

### 2.3 検索優先順位

#### `-w` 未指定時（デフォルトワークフロー）— 変更なし

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | `.pi-runner.yaml` の `workflow` セクション | デフォルトワークフロー |
| 2 | `.pi/workflow.yaml` | プロジェクト固有 |
| 3 | `workflows/default.yaml` | ファイルベース |
| 4 | pi-issue-runner の `workflows/default.yaml` | インストールディレクトリ |
| 5 | ビルトイン `default` | ハードコード |

#### `-w NAME` 指定時（名前付きワークフロー）— **変更あり**

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | **`.pi-runner.yaml` の `workflows.{NAME}`** | 🆕 設定ファイル内の名前付き定義 |
| 2 | `.pi/workflow.yaml` | プロジェクト固有（単一定義） |
| 3 | `workflows/{NAME}.yaml` | プロジェクトローカルのファイル |
| 4 | pi-issue-runner の `workflows/{NAME}.yaml` | インストールディレクトリ |
| 5 | ビルトイン `{NAME}` | ハードコード（default/simple） |

### 2.4 内部設計

#### 返り値の拡張

`find_workflow_file()` の返り値に新しい形式を追加する：

| 返り値の形式 | 意味 |
|-------------|------|
| `/path/to/file.yaml` | YAMLファイル（従来通り） |
| `builtin:NAME` | ビルトインワークフロー（従来通り） |
| **`config-workflow:NAME`** | 🆕 `.pi-runner.yaml` の `workflows.{NAME}` |

`get_workflow_steps()` は `config-workflow:NAME` を受け取ったとき、設定ファイルから `workflows.{NAME}.steps` を読み取る。

#### YAML パーサーの拡張

現在の簡易パーサー（`yaml.sh`）は2階層（`section.key`）までサポート。`workflows.quick.steps` は3階層になるため、簡易パーサーの拡張が必要。

**方針**: `yaml_get_array` と `yaml_exists` で3階層のドット区切りパスを処理できるよう拡張する。`yq` がインストールされている環境では追加対応不要（yqはネイティブに対応）。

##### 3階層のYAML構造

```yaml
workflows:        # レベル1: インデントなし
  quick:          # レベル2: 2スペース
    description: ... # レベル3: 4スペース（値あり）
    steps:        # レベル3: 4スペース（配列の親）
      - implement # レベル4: 6スペース（配列要素）
      - merge
```

簡易パーサーでは、インデントの深さでレベルを判定し、3階層目のキーとその配列値を取得できるようにする。

---

## 3. 影響範囲

### 変更が必要なファイル

| # | ファイル | 変更内容 | 規模 |
|---|---------|---------|------|
| 1 | `lib/yaml.sh` | 簡易パーサーで3階層パス対応 | 中 |
| 2 | `lib/workflow-finder.sh` | `find_workflow_file()` に `workflows.{NAME}` 検索追加 | 小 |
| 3 | `lib/workflow-loader.sh` | `get_workflow_steps()` で `config-workflow:NAME` 処理 | 小 |
| 4 | `lib/workflow.sh` | `list_available_workflows()` で `.pi-runner.yaml` の `workflows` も列挙 | 小 |
| 5 | `test/lib/yaml.bats` | 3階層パースのテスト追加 | 中 |
| 6 | `test/lib/workflow-finder.bats` | `workflows.{NAME}` 検索テスト追加 | 中 |
| 7 | `test/lib/workflow-loader.bats` | `config-workflow:NAME` 処理テスト追加 | 小 |
| 8 | `test/lib/workflow.bats` | 統合テスト追加 | 小 |
| 9 | `docs/configuration.md` | `workflows` セクションのドキュメント追加 | 中 |
| 10 | `docs/workflows.md` | ワークフロードキュメント更新 | 中 |

### 変更不要なファイル

| ファイル | 理由 |
|---------|------|
| `scripts/run.sh` | `--workflow` オプションのパースは既存のまま。`find_workflow_file()` → `get_workflow_steps()` のパイプラインは変わらない |
| `lib/workflow-prompt.sh` | ワークフロー名・ステップ取得後のプロンプト生成ロジックは変更不要 |
| `lib/config.sh` | `workflows` セクションは `config.sh` では読み込まない（workflow-finder/loaderが直接YAMLを読む） |
| `scripts/run-batch.sh` | バッチ実行は `--workflow` をそのまま渡すだけ |

---

## 4. 後方互換性

| 項目 | 互換性 | 説明 |
|------|--------|------|
| `workflow:` セクション（単数形） | ✅ 完全互換 | デフォルトワークフローとして引き続き動作 |
| `workflows/*.yaml` ファイル | ✅ 完全互換 | 検索順位は下がるが引き続き動作 |
| `-w` オプション | ✅ 互換 | 新たに `.pi-runner.yaml` 内も検索対象に追加 |
| 簡易YAMLパーサー（yqなし環境） | ✅ 対応 | 3階層サポートを追加 |
| `--list-workflows` | ✅ 拡張 | `.pi-runner.yaml` のワークフローも表示 |

**破壊的変更**: なし

---

## 5. 実装順序

```
Phase 1: 基盤（yaml.sh の3階層対応）
  ├── lib/yaml.sh の拡張
  └── test/lib/yaml.bats のテスト追加
      ↓
Phase 2: コアロジック
  ├── lib/workflow-finder.sh の変更
  ├── lib/workflow-loader.sh の変更
  ├── lib/workflow.sh の変更
  └── 対応するテスト追加
      ↓
Phase 3: ドキュメント
  ├── docs/configuration.md の更新
  └── docs/workflows.md の更新
```

---

## 6. テスト計画

### yaml.sh のテスト

```bash
# 3階層パスのテスト
@test "yaml_get_array parses 3-level path: workflows.quick.steps"
@test "yaml_get parses 3-level path: workflows.quick.description"
@test "yaml_exists checks 3-level path: workflows.quick"
@test "yaml_exists returns false for nonexistent 3-level path"
```

### workflow-finder.sh のテスト

```bash
# .pi-runner.yaml の workflows セクション
@test "find_workflow_file returns config-workflow:quick when workflows.quick defined"
@test "find_workflow_file prioritizes workflows section over workflows/*.yaml files"
@test "find_workflow_file falls back to file when workflow not in workflows section"
@test "find_workflow_file ignores workflows section for default (uses workflow section)"
```

### workflow-loader.sh のテスト

```bash
# config-workflow:NAME 処理
@test "get_workflow_steps returns steps for config-workflow:quick"
@test "get_workflow_steps returns builtin when config-workflow steps empty"
```

### workflow.sh のテスト

```bash
# 一覧表示
@test "list_available_workflows shows workflows from .pi-runner.yaml"
@test "list_available_workflows shows description from .pi-runner.yaml"
```

---

## 7. 将来の拡張ポイント（スコープ外）

oh-my-opencode のカテゴリシステムに着想を得た、将来的な拡張の可能性：

### 7.1 ワークフローごとのエージェント設定

```yaml
# 将来の構想（今回は実装しない）
workflows:
  quick:
    steps:
      - implement
      - merge
    agent:
      type: claude              # このワークフローではClaudeを使用
      args: ["--model", "haiku"]  # 軽量モデル

  thorough:
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    agent:
      type: claude
      args: ["--model", "opus"]  # 高性能モデル
```

### 7.2 ステップごとのエージェント設定

```yaml
# 将来の構想（今回は実装しない）
workflows:
  thorough:
    steps:
      - name: plan
        agent: agents/thorough-plan.md
      - name: implement
        agent: agents/thorough-implement.md
      - name: test
      - name: review
      - name: merge
```

### 7.3 Issue ラベルによるワークフロー自動選択

```yaml
# 将来の構想（今回は実装しない）
workflow_rules:
  - label: "bug"
    workflow: quick
  - label: "enhancement"
    workflow: thorough
  - label: "documentation"
    workflow: docs
  - default: default
```

これらはいずれも今回の `workflows` セクションの基盤の上に自然に構築できる。

---

## 8. まとめ

- `.pi-runner.yaml` に `workflows`（複数形）セクションを追加し、名前付き複数ワークフローを定義可能にする
- 既存の `workflow`（単数形）セクションとの後方互換性を完全に維持する
- 簡易YAMLパーサーの3階層対応が主な技術的課題
- oh-my-opencode のカテゴリシステムを参考に、将来的なエージェント設定のカスタマイズにも拡張可能な設計とする
