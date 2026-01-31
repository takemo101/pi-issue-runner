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
├── docs/              # ドキュメント
├── test/              # 単体テスト（*_test.sh形式）
├── tests/             # Batsテスト（fixtures, helpers含む）
└── .worktrees/        # 実行時に作成されるworktreeディレクトリ
```

## 開発コマンド

```bash
# スクリプト実行
./scripts/run.sh 42

# 単体テスト実行
./test/config_test.sh

# Batsテスト実行（Batsがインストールされている場合）
bats tests/

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

### Batsテストの書き方

```bash
#!/usr/bin/env bats

@test "run.sh requires issue number" {
    run ./scripts/run.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issue number is required"* ]]
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

## 注意事項

- すべてのスクリプトは `set -euo pipefail` で始める
- 外部コマンドの存在確認を行う
- エラーメッセージは stderr に出力
- 終了コードを適切に設定する
