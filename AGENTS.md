# Pi Issue Runner - Development Guide

## 概要

このプロジェクトは **シェルスクリプトベース** のpiスキルです。

## 技術スタック

- **言語**: Bash 4.0以上
- **依存ツール**: `gh` (GitHub CLI), `tmux`, `git`, `jq`, `yq` (YAMLパーサー、オプション)
- **テストフレームワーク**: Bats (Bash Automated Testing System)

## ディレクトリ構造

```
pi-issue-runner/
├── SKILL.md           # スキル定義（必須）
├── AGENTS.md          # 開発ガイド（このファイル）
├── README.md          # プロジェクト説明
├── scripts/           # 実行スクリプト
│   ├── run.sh         # メインエントリーポイント
│   ├── init.sh        # プロジェクト初期化
│   ├── list.sh        # セッション一覧
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションアタッチ
│   ├── stop.sh        # セッション停止
│   ├── cleanup.sh     # クリーンアップ
│   ├── improve.sh     # 継続的改善スクリプト
│   ├── wait-for-sessions.sh  # 複数セッション完了待機
│   ├── watch-session.sh  # セッション監視
│   └── test.sh        # テスト一括実行
├── lib/               # 共通ライブラリ
│   ├── config.sh      # 設定読み込み
│   ├── github.sh      # GitHub CLI操作
│   ├── log.sh         # ログ出力
│   ├── notify.sh      # 通知機能
│   ├── status.sh      # 状態管理
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
├── test/              # Batsテスト（*.bats形式）
│   ├── lib/           # ライブラリのユニットテスト
│   ├── scripts/       # スクリプトの統合テスト
│   ├── helpers/       # テストヘルパー・モック
│   ├── fixtures/      # テスト用フィクスチャ
│   └── test_helper.bash  # Bats共通ヘルパー
└── .worktrees/        # 実行時に作成されるworktreeディレクトリ
```

## 開発コマンド

```bash
# スクリプト実行
./scripts/run.sh 42

# テスト実行（推奨）
./scripts/test.sh              # 全テスト実行
./scripts/test.sh -v           # 詳細ログ付き
./scripts/test.sh -f           # fail-fast モード
./scripts/test.sh lib          # test/lib/*.bats のみ
./scripts/test.sh scripts      # test/scripts/*.bats のみ

# Batsテスト直接実行
bats test/lib/*.bats test/scripts/*.bats

# 特定のテストファイル実行
bats test/lib/config.bats

# シェルスクリプトの構文チェック
shellcheck scripts/*.sh lib/*.sh

# 手動テスト
./scripts/list.sh -v
./scripts/status.sh 42

# 継続的改善
./scripts/improve.sh --dry-run

# 複数セッション待機
./scripts/wait-for-sessions.sh 42 43
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

### Batsテストの書き方

```bash
#!/usr/bin/env bats
# test/lib/example.bats

load '../test_helper'

setup() {
    # テストごとのセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
}

teardown() {
    # テストごとのクリーンアップ
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "get_config returns default value" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    [ "$result" = ".worktrees" ]
}

@test "run.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
```

### テスト実行

```bash
# 全テスト実行
./scripts/test.sh

# 特定のディレクトリを実行
./scripts/test.sh lib
./scripts/test.sh scripts

# 詳細出力
./scripts/test.sh -v
```

### モックの使用

```bash
# test_helper.bash のモック関数を使用
@test "example with mocks" {
    mock_gh      # ghコマンドをモック
    mock_tmux    # tmuxコマンドをモック
    enable_mocks # モックをPATHに追加
    
    # テストコード
}
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

| 変数 | 説明 | ビルトイン使用 |
|------|------|----------------|
| `{{issue_number}}` | GitHub Issue番号 | ✅ |
| `{{issue_title}}` | Issueタイトル | ✅ |
| `{{branch_name}}` | ブランチ名 | ✅ |
| `{{worktree_path}}` | worktreeのパス | ✅ |
| `{{step_name}}` | 現在のステップ名 | *カスタム用 |
| `{{workflow_name}}` | ワークフロー名 | *カスタム用 |

> **Note**: 「カスタム用」の変数は `lib/workflow.sh` でサポートされていますが、ビルトインのエージェントテンプレート（`agents/*.md`）では使用していません。カスタムワークフローでロギングやデバッグ用途に活用できます。

### ワークフロー検索順序

1. プロジェクトルートの `.pi-runner.yaml`
2. プロジェクトルートの `.pi/workflow.yaml`
3. ビルトイン（`workflows/` ディレクトリ）

## 注意事項

- すべてのスクリプトは `set -euo pipefail` で始める
- 外部コマンドの存在確認を行う
- エラーメッセージは stderr に出力
- 終了コードを適切に設定する
