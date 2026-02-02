# Issue #561 Implementation Plan

## 概要
`test/scripts/run-watcher.bats` は `lib/daemon.sh` の関数をテストしているにもかかわらず、`test/scripts/` ディレクトリに配置されており、命名規則と実際のテスト対象が一致していない。

## 問題分析

### 現状
- `test/scripts/run-watcher.bats` が存在
- 対応する `scripts/run-watcher.sh` は存在しない
- このテストは実際には `lib/daemon.sh` の `daemonize` 関数をテスト
- `test/lib/daemon.bats` が既に存在し、類似のテストを含む

### 重複テスト
| run-watcher.bats | daemon.bats (既存) |
|-----------------|-------------------|
| daemonize function is available in run.sh context | daemonize function exists |
| watcher process survives parent shell termination | daemon process survives parent shell exit |
| watcher log file is created and written | daemonize writes output to log file |

### 移動が必要なユニークなテスト
- `Issue #553: watcher survives batch timeout scenario` - バッチタイムアウト時のwatcher生存テスト

## 実装ステップ

1. `test/lib/daemon.bats` に Issue #553 のテストケースを追加
2. `test/scripts/run-watcher.bats` を削除
3. テスト実行して全てパスすることを確認

## 影響範囲
- `test/lib/daemon.bats` - 1テストケース追加
- `test/scripts/run-watcher.bats` - 削除

## リスクと対策
- リスク: テストの誤った削除
- 対策: 移動前に内容を確認し、重複を検証

## 完了条件
- [ ] Issue #553のテストがdaemon.batsに移動済み
- [ ] run-watcher.batsが削除済み
- [ ] 全テストがパス
