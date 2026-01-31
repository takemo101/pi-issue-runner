# Implementation Plan: Issue #337

## 概要

README.md と AGENTS.md のディレクトリ構造の記載を実際のファイル構造と一致させる。

## 発見された不一致

### 実際のファイル構造（lib/）

```
lib/
├── agent.sh              # ← ドキュメントに記載なし
├── config.sh
├── github.sh
├── hooks.sh
├── log.sh
├── notify.sh
├── status.sh
├── template.sh
├── tmux.sh
├── workflow-finder.sh    # ← README.md に記載なし
├── workflow-loader.sh    # ← README.md に記載なし
├── workflow-prompt.sh    # ← README.md に記載なし
├── workflow.sh
├── worktree.sh
└── yaml.sh
```

### 実際のファイル構造（test/lib/）

```
test/lib/
├── agent.bats            # ← ドキュメントに記載なし
├── config.bats
├── github.bats
├── hooks.bats
├── log.bats
├── notify.bats
├── status.bats
├── template.bats
├── tmux.bats
├── workflow-finder.bats  # ← ドキュメントに記載なし
├── workflow-loader.bats  # ← ドキュメントに記載なし
├── workflow-prompt.bats  # ← ドキュメントに記載なし
├── workflow.bats
├── worktree.bats
└── yaml.bats
```

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| README.md | lib/ に4ファイル追加、test/lib/ に4ファイル追加 |
| AGENTS.md | lib/ に1ファイル追加、test/lib/ に4ファイル追加 |

## 実装ステップ

1. **README.md の修正**
   - lib/ セクションに `agent.sh`, `workflow-finder.sh`, `workflow-loader.sh`, `workflow-prompt.sh` を追加
   - test/lib/ セクションに `agent.bats`, `workflow-finder.bats`, `workflow-loader.bats`, `workflow-prompt.bats` を追加

2. **AGENTS.md の修正**
   - lib/ セクションに `agent.sh` を追加
   - test/lib/ セクションに `agent.bats`, `workflow-finder.bats`, `workflow-loader.bats`, `workflow-prompt.bats` を追加

3. **ファイル順序**
   - アルファベット順を維持（既存のスタイルに合わせる）

## テスト方針

- ドキュメント変更のみのため、自動テストは不要
- 変更後のディレクトリ構造が実際のファイルと一致することを手動で確認

## リスクと対策

- **リスク**: 将来的に同様の不整合が発生する可能性
- **対策**: Issue内で提案された通り、将来的にファイル構造チェックスクリプトの追加を検討（本Issueの範囲外）
