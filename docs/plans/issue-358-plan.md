# Issue #358 Implementation Plan

## 概要

AGENTS.mdのtest/lib/*.batsファイルリストが実際のファイル構成と一致しているか確認し、サンプルコードと実際のディレクトリ構造の区別を明確化する。

## 現状分析

### 実際のファイル (test/lib/*.bats)
- agent.bats
- config.bats
- github.bats
- hooks.bats
- log.bats
- notify.bats
- status.bats
- template.bats
- tmux.bats
- workflow-finder.bats
- workflow-loader.bats
- workflow-prompt.bats
- workflow.bats
- worktree.bats
- yaml.bats

### AGENTS.mdのディレクトリ構造セクション
✅ 既に実際のファイルリストと一致している（github.batsも含まれている）

### 問題点
- サンプルコード（Batsテストの書き方）で `test/lib/example.bats` というファイル名を使用
- これが実際のファイルと誤解される可能性がある

## 影響範囲

- `AGENTS.md` のサンプルコードセクション

## 実装ステップ

1. サンプルコードのファイル名を明確に架空のものとわかるように修正
   - `test/lib/example.bats` → `test/lib/your-module.bats`
2. サンプルコードの前に「以下は架空の例です」という注釈を追加

## テスト方針

- 変更はドキュメントのみのため、技術的なテストは不要
- 手動で変更内容を確認

## リスクと対策

- リスク: 特になし（ドキュメント変更のみ）
