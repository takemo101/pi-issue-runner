# Issue #379 Implementation Plan

docs: .pi-runner.yamlのworkflowセクションとworkflowファイルの違いが不明確

## 概要

.pi-runner.yaml の `workflow` セクションと `workflows/*.yaml` ファイルの違い・使い分けを明確に説明するため、ドキュメントを改善します。

## 現状の問題分析

### 1. 機能の実際の動作

`lib/workflow-finder.sh` の検索順序:
1. `.pi-runner.yaml` の `workflow` セクション（`-w` 未指定時のデフォルト）
2. `.pi/workflow.yaml`
3. `workflows/{name}.yaml`（`-w <name>` 指定時に使用）
4. ビルトイン定義

### 2. 問題点

- `workflow.name` in `.pi-runner.yaml` は実質的に機能していない（`-w` で指定した名前が優先される）
- 「ワークフロー設定」として `workflow` セクションを説明しているが、実際には `workflows/*.yaml` を作成する方法も並行して存在
- `.pi-runner.yaml` の `workflow` セクションが「デフォルトワークフロー」として機能することを明確に説明していない

## 影響範囲

- `docs/configuration.md` - workflowセクションの説明を明確化
- `docs/workflows.md` - 両者の違いと使い分けを追加

## 実装ステップ

### Step 1: docs/configuration.md の更新

1. 「ワークフロー設定」セクションを以下のように再構成:
   - 「デフォルトワークフロー設定」として `.pi-runner.yaml` の `workflow` セクションを説明
   - `-w` オプション使用時の挙動を明確に説明
   - `workflow.name` は無視されることを注記

2. 設定例の修正:
   - `workflow.name` を削除または注記追加
   - 「この設定は `-w` オプション未指定時に使用される」ことを明記

3. 「ワークフローファイルの検索順序」セクションの更新:
   - `.pi-runner.yaml` の `workflow` セクションが「デフォルト」として機能することを明確化
   - `-w` オプション使用時は `workflows/*.yaml` が優先されることを追加

### Step 2: docs/workflows.md の更新

1. 「ワークフロー検索順序」セクションの改善:
   - 検索順序と各パターンの使用条件を表形式で明確化
   - `-w` オプション有無による動作の違いを追加

2. 「プロジェクト設定でのワークフロー定義」セクションの改善:
   - 「デフォルトワークフロー」としての役割を明確化
   - `workflows/*.yaml` との使い分けを説明

3. 新規セクション「デフォルトワークフロー vs 名前付きワークフロー」の追加:
   - 概念図または表による比較
   - 使用シナリオの例示

## テスト方針

- ドキュメントの変更のみのため、単体テストは不要
- 手動確認: 更新したドキュメントのプレビューと内容の確認
- ShellCheck: スクリプト変更がないため対象外

## リスクと対策

| リスク | 対策 |
|--------|------|
| ドキュメントの誤解を招く表現 | 複数人でのレビュー、明確な例示 |
| 既存ユーザーへの混乱 | 「変更点」ではなく「明確化」であることを強調 |
| 情報の重複 | configuration.md と workflows.md の重複を最小限に抑え、相互リンクを設置 |

## 受け入れ条件

- [x] `workflow` セクションの正確な動作を確認済み
- [ ] `docs/configuration.md` を更新
- [ ] `docs/workflows.md` と整合性を取る
- [ ] 両ドキュメントの内容が正確で、ユーザーが混乱しない
