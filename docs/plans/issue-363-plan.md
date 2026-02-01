# Issue #363 実装計画書

## 概要

`scripts/init.sh` の `GITIGNORE_ENTRIES` に、pi-issue-runner が生成する可能性のあるファイル/ディレクトリのエントリを追加する。

## 現状分析

### 現在の `GITIGNORE_ENTRIES`
```bash
GITIGNORE_ENTRIES="
# pi-issue-runner
.worktrees/
.pi-runner.yaml.local
*.swp
"
```

### 追加が必要なエントリ

| エントリ | 説明 | 生成元 |
|---------|------|--------|
| `.improve-logs/` | improve.sh のログディレクトリ | `scripts/improve.sh` |
| `.pi-runner.yml` | 設定ファイル（yml形式） | ユーザー作成の可能性 |
| `.pi-prompt.md` | プロンプトファイル | ユーザー作成の可能性 |

## 影響範囲

1. **scripts/init.sh** - `GITIGNORE_ENTRIES` 変数の更新
2. **test/scripts/init.bats** - 新しいエントリのテスト追加

## 実装ステップ

1. `scripts/init.sh` の `GITIGNORE_ENTRIES` を更新
2. `test/scripts/init.bats` にテストを追加
3. 全テストを実行して確認

## テスト方針

- 既存テストがすべてパスすること
- 新しいエントリが `.gitignore` に追加されることを確認するテスト追加:
  - `.improve-logs/` のテスト
  - `.pi-runner.yml` のテスト
  - `.pi-prompt.md` のテスト

## リスクと対策

- **リスク**: なし（単純な設定値の追加）
- **対策**: 既存テストの実行で後方互換性を確認
