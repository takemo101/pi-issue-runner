# 実装計画書: Issue #291

## 概要

AGENTS.md のディレクトリ構造セクションに、未記載のファイル（`lib/hooks.sh` と `test/lib/hooks.bats`）を追加する。

## 現状分析

### 実際のファイル状況
- `lib/hooks.sh` - 存在する
- `test/lib/github.bats` - 存在する
- `test/lib/hooks.bats` - 存在する

### AGENTS.md の記載状況
- `lib/hooks.sh` - **未記載** ← 修正必要
- `test/lib/github.bats` - 記載済み
- `test/lib/hooks.bats` - **未記載** ← 修正必要

> Note: Issue では `test/lib/github.bats` も未記載と報告されていますが、実際には AGENTS.md に記載されています。

## 影響範囲

- `AGENTS.md` - ディレクトリ構造セクションのみ

## 実装ステップ

### 1. lib/ セクションの更新
`github.sh` の後に `hooks.sh` エントリを追加:
```
│   ├── github.sh      # GitHub CLI操作
│   ├── hooks.sh       # Hook機能    ← 追加
│   ├── log.sh         # ログ出力
```

### 2. test/lib/ セクションの更新
`github.bats` の後に `hooks.bats` エントリを追加:
```
│   │   ├── github.bats
│   │   ├── hooks.bats              ← 追加
│   │   ├── log.bats
```

## テスト方針

- ドキュメントのみの変更のため、テストコードの追加は不要
- 変更後の AGENTS.md が構文的に正しいことを確認

## リスクと対策

- **リスク**: なし（ドキュメントの軽微な更新のみ）
- **対策**: 差分を確認してから commit

## 受け入れ条件

- [x] lib/hooks.sh が AGENTS.md のディレクトリ構造に追加されている
- [ ] test/lib/github.bats が AGENTS.md のディレクトリ構造に追加されている → 既に記載済み
- [x] test/lib/hooks.bats が AGENTS.md のディレクトリ構造に追加されている
