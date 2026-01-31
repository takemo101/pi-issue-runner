# 実装計画: Issue #175 - GitHub CLI非認証環境でのテストカバレッジ改善

## 概要

GitHub CLI（`gh`）が認証されていない環境（CI環境など）でも、主要なテストがスキップされずに実行されるよう、モック機能を拡充する。

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `test/helpers/mocks.sh` | `mock_gh`関数の拡充、関数エクスポート方式への変更 |
| `test/run_test.sh` | モックを活用したテスト実行への変更 |
| `test/github_test.sh` | モックを活用したテスト実行への変更 |

## 実装ステップ

### Step 1: `test/helpers/mocks.sh` の拡充

1. `mock_gh` 関数をファイルベース（`$MOCK_DIR/gh`スクリプト）から関数エクスポート方式（`export -f gh`）に変更
2. より多くのGitHub CLIコマンドをサポート:
   - `gh auth status` - 常に成功
   - `gh issue view <N>` - モックJSONを返す
   - `gh repo view` - モック結果を返す
3. `unmock_gh` 関数を追加
4. `USE_MOCK_GH` 環境変数のサポートを追加

### Step 2: `test/run_test.sh` の更新

1. 冒頭でモックライブラリを読み込み
2. `GH_AUTHENTICATED` チェックを `USE_MOCK_GH` との組み合わせに変更
3. 非認証時はモックを自動適用してテストを実行

### Step 3: `test/github_test.sh` の更新

1. モックライブラリを読み込み
2. 依存関係チェックテストでモックを活用

## テスト方針

1. モックが正しく動作することを確認
2. `USE_MOCK_GH=true` でモックモードを強制できることを確認
3. 全テストを実行し、スキップが減少していることを確認

```bash
# モック強制モードでテスト
USE_MOCK_GH=true ./test/run_test.sh
USE_MOCK_GH=true ./test/github_test.sh
```

## リスクと対策

| リスク | 対策 |
|--------|------|
| モックが実際のghと振る舞いが異なる | 主要なレスポンス形式を実際のghに合わせる |
| 既存テストが壊れる | 既存の`mock_gh`はファイルベース、新規は関数ベースで共存 |
| モック解除忘れ | `unmock_gh`関数を提供し、テスト末尾で呼び出す |

## 受け入れ条件

- [x] `test/helpers/mocks.sh` に拡張版 `mock_gh` 関数が追加されている
- [ ] GitHub CLI非認証環境でも主要なテストが実行される
- [ ] `USE_MOCK_GH=true` でモックモードを強制できる
- [ ] 全テストがパスする
