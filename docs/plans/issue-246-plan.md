# Implementation Plan for Issue #246

## 概要

README.mdとAGENTS.mdのテスト構造記載を実際のディレクトリ構造に合わせて更新する。

## 現状分析

### 実際のテスト構造

```
test/
├── lib/                         # ライブラリのユニットテスト（8ファイル）
│   ├── config.bats
│   ├── github.bats
│   ├── log.bats
│   ├── notify.bats
│   ├── status.bats
│   ├── tmux.bats
│   ├── workflow.bats
│   └── worktree.bats
├── scripts/                     # スクリプトの統合テスト（10ファイル）
│   ├── attach.bats
│   ├── cleanup.bats
│   ├── improve.bats
│   ├── init.bats
│   ├── list.bats
│   ├── run.bats
│   ├── status.bats
│   ├── stop.bats
│   ├── wait-for-sessions.bats
│   └── watch-session.bats
├── regression/                  # 回帰テスト
│   └── critical-fixes.bats
├── fixtures/                    # テスト用フィクスチャ
│   └── sample-config.yaml
└── test_helper.bash             # Bats共通ヘルパー（モック関数含む）
```

### 現在の問題点

1. **README.md**: test/lib/ と test/scripts/ のファイル一覧が不完全（3ファイルのみ記載）
2. **AGENTS.md**: 個別のテストファイルが列挙されていない

## 影響範囲

- README.md (テスト構造セクション: 約20行)
- AGENTS.md (ディレクトリ構造セクション: 約5行)

## 実装ステップ

1. README.md のテスト構造セクション（lines 352-373）を全てのテストファイルを含むように更新
2. AGENTS.md のディレクトリ構造は既に regression/ を含んでいるため、詳細情報の追加のみ

## テスト方針

- ドキュメントのみの変更のため、静的検証のみ
- 実際のディレクトリ構造と照合

## リスクと対策

- 低リスク: ドキュメント変更のみ
- 検証: find コマンドで実際の構造と一致を確認
