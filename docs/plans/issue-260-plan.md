# Issue #260 実装計画書

## 概要

ドキュメントの不整合を修正する。

## 調査結果

### 1. AGENTS.md の `github.bats` について

**現状**: ✅ 既に修正済み

AGENTS.md のディレクトリ構造には既に `github.bats` が含まれている：
```
│   ├── lib/           # ライブラリのユニットテスト
│   │   ├── config.bats
│   │   ├── github.bats  ← 既に存在
│   │   ├── log.bats
```

このIssueが作成された後に、別のPRで修正された可能性がある。

### 2. README.md の `--pi-args` オプションについて

**現状**: ❌ 未修正

`run.sh --help` には `--pi-args ARGS` オプションが表示されるが、README.md の「Issue実行」セクションには記載がない。

## 影響範囲

- `README.md` - Issue実行セクションにオプション説明を追加

## 実装ステップ

1. README.md の「Issue実行」セクションに `--pi-args` オプションの説明を追加

## テスト方針

- ドキュメント変更のみのため、追加テストは不要
- 変更後にMarkdownの構文を確認

## リスクと対策

- リスク: なし（ドキュメントのみの変更）
