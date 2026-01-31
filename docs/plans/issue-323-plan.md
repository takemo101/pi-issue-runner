# Issue #323 実装計画書

## 概要

AGENTS.mdに記載されているディレクトリ構造を実際のプロジェクト構造と一致させる。

## 影響範囲

- `AGENTS.md` のみ（ドキュメント更新）

## 現状分析

### 実際のlib/ディレクトリ（14ファイル）
1. config.sh
2. github.sh
3. hooks.sh
4. log.sh
5. notify.sh
6. status.sh
7. template.sh
8. tmux.sh
9. workflow.sh
10. **workflow-finder.sh** ← 記載なし
11. **workflow-loader.sh** ← 記載なし
12. **workflow-prompt.sh** ← 記載なし
13. worktree.sh
14. yaml.sh

### 実際のtest/lib/ディレクトリ（11ファイル）
- すべて記載済み ✓

### 実際のtest/scripts/ディレクトリ（11ファイル）
1. attach.bats
2. cleanup.bats
3. improve.bats
4. init.bats
5. list.bats
6. run.bats
7. status.bats
8. stop.bats
9. **test.bats** ← 記載なし
10. wait-for-sessions.bats
11. watch-session.bats

## 実装ステップ

1. AGENTS.mdのlib/セクションに以下を追加:
   - workflow-finder.sh（ワークフロー検索）
   - workflow-loader.sh（ワークフロー読み込み）
   - workflow-prompt.sh（プロンプト処理）

2. AGENTS.mdのtest/scripts/セクションに以下を追加:
   - test.bats（test.shのテスト）

3. ファイルはアルファベット順で配置

## テスト方針

- 手動確認: 更新後のディレクトリ構造が実際のファイル構成と一致することを確認

## リスクと対策

- **リスク**: なし（ドキュメントのみの変更）
- **対策**: 特になし
