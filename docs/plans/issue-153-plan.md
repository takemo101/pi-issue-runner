# Issue #153 実装計画書

## 概要

`scripts/` ディレクトリ内の4つのスクリプトに対応するテストファイルを作成し、テストカバレッジを向上させます。

## 影響範囲

### 新規作成ファイル

| ファイル | 対象スクリプト |
|---------|---------------|
| `test/attach_test.sh` | `scripts/attach.sh` |
| `test/list_test.sh` | `scripts/list.sh` |
| `test/stop_test.sh` | `scripts/stop.sh` |
| `test/improve_test.sh` | `scripts/improve.sh` |

### 既存ファイルへの影響

なし（新規テストファイルの追加のみ）

## 実装ステップ

### 1. attach_test.sh
- ヘルプ出力テスト (`--help`, `-h`)
- 引数パースのテスト（不明なオプション、引数なしのエラー）
- セッション名の正規化テスト（数字のみ → `pi-issue-XXX`）
- スクリプトソースコードの構造確認

### 2. list_test.sh
- ヘルプ出力テスト (`--help`, `-h`)
- `-v, --verbose` オプションの動作確認
- 不明なオプションのエラーテスト
- スクリプトソースコードの構造確認

### 3. stop_test.sh
- ヘルプ出力テスト (`--help`, `-h`)
- 引数パースのテスト（不明なオプション、引数なしのエラー）
- セッション名の正規化テスト（数字のみ → `pi-issue-XXX`）
- スクリプトソースコードの構造確認

### 4. improve_test.sh
- ヘルプ出力テスト (`--help`, `-h`)
- オプションパースのテスト
  - `--max-iterations N`
  - `--max-issues N`
  - `--auto-continue`
  - `--dry-run`
  - `--timeout <sec>`
  - `--review-only`
  - `-v, --verbose`
- 依存関係チェック関数のテスト
- スクリプトソースコードの構造確認

## テスト方針

### テストパターン

既存のテスト（`run_test.sh`, `cleanup_test.sh`, `status_test.sh`）と同じパターンを使用：

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() { ... }
assert_contains() { ... }
assert_success() { ... }
assert_failure() { ... }

# テスト実行
# ...

# 結果表示
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
exit $TESTS_FAILED
```

### テストの種類

1. **Usage/Helpテスト**: `--help` オプションの出力を検証
2. **オプションパーステスト**: 各オプションが正しく認識されることを確認
3. **エラーケーステスト**: 不正な入力に対するエラー処理を検証
4. **ソースコード構造テスト**: 必要な関数やロジックが存在することを確認

### モック戦略

- tmuxコマンドのモックは不要（ヘルプと引数パースのテストが中心）
- 実際のセッション操作は既存の `tmux_test.sh` でカバーされている
- `improve.sh` は複雑なため、オプションパースとヘルプのテストに集中

## リスクと対策

| リスク | 対策 |
|-------|-----|
| tmuxセッションが実際に作成される | モックを使用するか、構文/ヘルプテストのみを実行 |
| GitHub CLI認証が必要 | 認証チェックを行い、未認証時はスキップ |
| 実行環境による差異 | 環境依存テストをスキップ可能にする |

## 受け入れ条件

- [ ] `test/attach_test.sh` が作成され、主要なケースがテストされている
- [ ] `test/list_test.sh` が作成され、主要なケースがテストされている
- [ ] `test/stop_test.sh` が作成され、主要なケースがテストされている
- [ ] `test/improve_test.sh` が作成され、主要なケースがテストされている
- [ ] 全テストが `for f in test/*_test.sh; do bash "$f"; done` で実行可能
- [ ] 全テストがパスする
