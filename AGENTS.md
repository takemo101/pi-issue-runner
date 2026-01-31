# Pi Issue Runner - Development Guide

## 概要

このプロジェクトは **シェルスクリプトベース** のpiスキルです。

## 技術スタック

- **言語**: Bash 4.0以上
- **依存ツール**: `gh` (GitHub CLI), `tmux`, `git`, `jq`, `yq` (YAMLパーサー、オプション)
- **テストフレームワーク**: シェルスクリプト形式（`*_test.sh`）

## ディレクトリ構造

```
pi-issue-runner/
├── SKILL.md           # スキル定義（必須）
├── AGENTS.md          # 開発ガイド（このファイル）
├── README.md          # プロジェクト説明
├── scripts/           # 実行スクリプト
│   ├── run.sh         # メインエントリーポイント
│   ├── list.sh        # セッション一覧
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションアタッチ
│   ├── stop.sh        # セッション停止
│   ├── cleanup.sh     # クリーンアップ
│   └── post-session.sh # セッション終了後処理
├── lib/               # 共通ライブラリ
│   ├── config.sh      # 設定読み込み
│   ├── github.sh      # GitHub CLI操作
│   ├── log.sh         # ログ出力
│   ├── tmux.sh        # tmux操作
│   ├── workflow.sh    # ワークフローエンジン
│   └── worktree.sh    # Git worktree操作
├── workflows/         # ビルトインワークフロー定義
│   ├── default.yaml   # 完全ワークフロー
│   └── simple.yaml    # 簡易ワークフロー
├── agents/            # エージェントテンプレート
│   ├── plan.md        # 計画エージェント
│   ├── implement.md   # 実装エージェント
│   ├── review.md      # レビューエージェント
│   └── merge.md       # マージエージェント
├── docs/              # ドキュメント
├── test/              # 単体テスト（*_test.sh形式、fixtures/helpers含む）
└── .worktrees/        # 実行時に作成されるworktreeディレクトリ
```

## 開発コマンド

```bash
# スクリプト実行
./scripts/run.sh 42

# 単体テスト実行
./test/config_test.sh

# 全テスト実行
for f in test/*_test.sh; do bash "$f"; done

# シェルスクリプトの構文チェック
shellcheck scripts/*.sh lib/*.sh

# 手動テスト
./scripts/list.sh -v
./scripts/status.sh 42
```

## コーディング規約

### シェルスクリプト

1. **shebang**: `#!/usr/bin/env bash`
2. **strict mode**: `set -euo pipefail`
3. **関数定義**: 小文字のスネークケース
4. **変数**: ローカル変数は `local` を使用
5. **引数チェック**: 必須引数は明示的にチェック

### ファイル構成

- `scripts/` - ユーザーが直接実行するスクリプト
- `lib/` - 共通関数（sourceで読み込み）
- `docs/` - ドキュメント

## テスト

### テストの書き方

```bash
#!/usr/bin/env bash
# example_test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

# テスト実行
echo "=== Example tests ==="
assert_equals "1+1=2" "2" "$((1+1))"

# 結果表示
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
exit $TESTS_FAILED
```

### 手動テスト

```bash
# モック環境でテスト
export PI_COMMAND="echo pi"  # 実際のpiを起動しない
./scripts/run.sh 999 --no-attach
```

## デバッグ

```bash
# Bashデバッグモード
bash -x ./scripts/run.sh 42

# 詳細ログ
DEBUG=1 ./scripts/run.sh 42
```

## ワークフローカスタマイズ

### 新しいワークフローの追加

1. `workflows/` ディレクトリに新しいYAMLファイルを作成:

```yaml
# workflows/thorough.yaml
name: thorough
description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan
  - implement
  - test
  - review
  - merge
```

2. 必要に応じて `agents/` ディレクトリにエージェントテンプレートを追加

### エージェントテンプレートの作成

```markdown
# agents/test.md
# Test Agent

GitHub Issue #{{issue_number}} のテストを実行します。

## コンテキスト
- **Issue番号**: #{{issue_number}}
- **ブランチ**: {{branch_name}}

## タスク
1. 単体テストを実行
2. 結合テストを実行
3. カバレッジレポートを確認
```

### テンプレート変数

| 変数 | 説明 |
|------|------|
| `{{issue_number}}` | GitHub Issue番号 |
| `{{branch_name}}` | ブランチ名 |
| `{{worktree_path}}` | worktreeのパス |

### ワークフロー検索順序

1. プロジェクトルートの `.pi-runner.yaml`
2. プロジェクトルートの `.pi/workflow.yaml`
3. ビルトイン（`workflows/` ディレクトリ）

## 注意事項

- すべてのスクリプトは `set -euo pipefail` で始める
- 外部コマンドの存在確認を行う
- エラーメッセージは stderr に出力
- 終了コードを適切に設定する
