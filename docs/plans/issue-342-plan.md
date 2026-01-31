# 実装計画: Issue #342

## 概要

ドキュメントに記載された未実装ステップ（`test`, `security-check`）を整理し、ドキュメントとコードの整合性を確保する。

**採用方針**: B案（ドキュメントを修正）

## 問題分析

### 現状の問題点

1. **docs/configuration.md**
   - 行100付近: `利用可能: plan, implement, review, merge, test, security-check`
   - 「徹底ワークフロー」例で `test`, `security-check` を使用

2. **docs/workflows.md**
   - 行69-80付近: `thorough` ワークフロー例で `test` ステップを使用

3. **実装状況**
   - `agents/` には `plan.md`, `implement.md`, `review.md`, `merge.md` のみ存在
   - `lib/template.sh` のビルトインは上記4ステップのみ対応
   - `workflows/` には `default.yaml`, `simple.yaml` のみ存在

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `docs/configuration.md` | 未実装ステップの記載を削除・修正 |
| `docs/workflows.md` | thorough ワークフロー例を修正 |

## 実装ステップ

### 1. docs/configuration.md の修正

- [ ] `# 利用可能` の行から `test, security-check` を削除
- [ ] 「徹底ワークフロー」例をカスタムワークフローの説明として修正
- [ ] カスタムステップを使用する場合は対応するエージェントテンプレートが必要であることを明記

### 2. docs/workflows.md の修正

- [ ] `thorough` ワークフロー例にカスタムステップ使用時の注意書きを追加
- [ ] ビルトインで利用可能なステップを明確化

### 3. テスト

- [ ] ShellCheck実行
- [ ] Batsテスト実行

## テスト方針

- ドキュメントのみの変更のため、コードテストへの影響なし
- ShellCheck、Batsテストを実行して既存機能に影響がないことを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存ユーザーがこれらのステップを使用していた場合 | ドキュメントでカスタムステップの作成方法を明確に説明 |
| ドキュメント間の整合性不足 | 両ファイルを同時に修正し、相互参照を確認 |

## 見積もり

30分
