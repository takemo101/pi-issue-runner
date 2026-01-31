# Implementation Plan: Issue #201 - scriptsディレクトリのBatsテスト追加

## 概要

scriptsディレクトリに存在するスクリプトのうち、Batsテストが不足している7つのスクリプトに対してテストファイルを作成する。

## 影響範囲

### 新規作成ファイル
- `test/scripts/attach.bats`
- `test/scripts/init.bats`
- `test/scripts/improve.bats`
- `test/scripts/status.bats`
- `test/scripts/stop.bats`
- `test/scripts/wait-for-sessions.bats`
- `test/scripts/watch-session.bats`

### 参照ファイル（変更なし）
- `test/test_helper.bash` - 共通ヘルパー・モック関数
- `scripts/*.sh` - テスト対象スクリプト

## 実装ステップ

### 1. attach.bats
- ヘルプ表示テスト (--help, -h)
- 引数エラーテスト（セッション名/Issue番号なし）
- オプション解析テスト

### 2. init.bats
- ヘルプ表示テスト (--help, -h)
- オプションテスト (--full, --minimal, --force)
- Gitリポジトリチェックテスト

### 3. improve.bats
- ヘルプ表示テスト (--help, -h)
- オプションテスト (--max-iterations, --max-issues, --dry-run, --review-only)
- 引数バリデーションテスト

### 4. status.bats
- ヘルプ表示テスト (--help, -h)
- 引数エラーテスト（セッション名/Issue番号なし）
- オプションテスト (--output)

### 5. stop.bats
- ヘルプ表示テスト (--help, -h)
- 引数エラーテスト（セッション名/Issue番号なし）
- オプションバリデーションテスト

### 6. wait-for-sessions.bats
- ヘルプ表示テスト (--help, -h)
- 引数エラーテスト（Issue番号なし）
- オプションテスト (--timeout, --interval, --fail-fast, --quiet)
- 終了コードテスト

### 7. watch-session.bats
- ヘルプ表示テスト (--help, -h)
- 引数エラーテスト（セッション名なし）
- オプションテスト (--marker, --interval, --no-auto-attach)

## テスト方針

1. **ヘルプ表示テスト**: 全スクリプトで --help と -h オプションをテスト
2. **引数バリデーションテスト**: 必須引数が欠けた場合のエラーハンドリング
3. **オプション解析テスト**: ヘルプ出力から各オプションの存在を確認
4. **モック使用**: tmux, gh, git コマンドをモックして外部依存を排除

## リスクと対策

| リスク | 対策 |
|--------|------|
| 外部コマンド依存 | test_helper.bashのモック関数を活用 |
| 既存テストとの重複 | 旧形式(*_test.sh)との棲み分けを明確化 |
| テスト実行時間 | 実際のコマンド実行は避けモックを使用 |

## 完了条件

- [x] 7つのBatsテストファイルが作成されている
- [x] `bats test/scripts/*.bats` が正常に実行できる
- [x] 各テストファイルにヘルプ表示、引数エラーのテストが含まれている
