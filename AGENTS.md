# Pi Issue Runner - Development Guide

## 概要

このプロジェクトは **シェルスクリプトベース** のpiスキルです。

## 技術スタック

- **言語**: Bash 4.3以上
- **依存ツール**: `gh` (GitHub CLI), `tmux`, `git`, `jq`, `yq` (YAMLパーサー、オプション)
- **テストフレームワーク**: Bats (Bash Automated Testing System)
- **静的解析**: ShellCheck

## ディレクトリ構造

```
pi-issue-runner/
├── .github/
│   ├── actions/
│   │   └── setup-deps/
│   │       └── action.yaml    # CI依存セットアップ（Bats, yq, tmux）
│   └── workflows/
│       └── ci.yaml    # CI設定
├── SKILL.md           # スキル定義（必須）
├── AGENTS.md          # 開発ガイド（このファイル）
├── README.md          # プロジェクト説明
├── install.sh         # グローバルインストール
├── uninstall.sh       # アンインストール
├── scripts/           # 実行スクリプト
│   ├── run.sh         # メインエントリーポイント
│   ├── run-batch.sh   # 複数Issueを依存関係順にバッチ実行
│   ├── restart-watcher.sh  # Watcher再起動
│   ├── init.sh        # プロジェクト初期化
│   ├── list.sh        # セッション一覧
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションアタッチ
│   ├── stop.sh        # セッション停止
│   ├── sweep.sh       # 全セッションのマーカーチェック・cleanup
│   ├── mux-all.sh     # 全セッション表示（マルチプレクサ対応）
│   ├── cleanup.sh     # クリーンアップ
│   ├── ci-fix-helper.sh  # CI修正ヘルパー（lib/ci-fix.shのラッパー）
│   ├── context.sh     # コンテキスト管理
│   ├── dashboard.sh   # ダッシュボード表示
│   ├── generate-config.sh  # プロジェクト解析・設定生成
│   ├── force-complete.sh  # セッション強制完了
│   ├── improve.sh     # 継続的改善スクリプト
│   ├── knowledge-loop.sh  # 知識ループ（fixコミットから知見抽出・AGENTS.md更新提案）
│   ├── next.sh        # 次のタスク取得
│   ├── nudge.sh       # セッションへメッセージ送信
│   ├── test.sh        # テスト一括実行
│   ├── tracker.sh     # プロンプト効果測定（集計・表示）
│   ├── verify-config-docs.sh  # 設定ドキュメントの整合性検証
│   ├── wait-for-sessions.sh  # 複数セッション完了待機
│   └── watch-session.sh  # セッション監視
├── lib/               # 共通ライブラリ
│   ├── agent.sh       # マルチエージェント対応
│   ├── batch.sh       # バッチ処理コア機能
│   ├── ci-classifier.sh   # CI失敗タイプ分類
│   ├── ci-fix.sh      # CI失敗検出・自動修正（※ci-fix-helper.sh経由で使用）
│   ├── ci-fix/            # CI修正サブモジュール群
│   │   ├── bash.sh        # Bash固有の修正・検証ロジック
│   │   ├── common.sh      # 共通ユーティリティ
│   │   ├── detect.sh      # プロジェクトタイプ検出
│   │   ├── escalation.sh  # エスカレーション処理
│   │   ├── go.sh          # Go固有の修正・検証ロジック
│   │   ├── node.sh        # Node固有の修正・検証ロジック
│   │   ├── python.sh      # Python固有の修正・検証ロジック
│   │   └── rust.sh        # Rust固有の修正・検証ロジック
│   ├── cleanup-trap.sh    # エラー時クリーンアップトラップ管理
│   ├── ci-monitor.sh      # CI状態監視
│   ├── ci-retry.sh        # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh  # improve-logsのクリーンアップ
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
│   ├── compat.sh      # クロスプラットフォーム互換性ヘルパー
│   ├── config.sh      # 設定読み込み
│   ├── context.sh     # コンテキスト管理
│   ├── daemon.sh      # プロセスデーモン化
│   ├── dashboard.sh   # ダッシュボード機能
│   ├── dependency.sh  # 依存関係解析・レイヤー計算
│   ├── generate-config.sh  # プロジェクト解析・設定生成（ライブラリ関数）
│   ├── github.sh      # GitHub CLI操作
│   ├── hooks.sh       # Hook機能
│   ├── improve.sh     # 継続的改善ライブラリ（オーケストレーター）
│   ├── knowledge-loop.sh  # 知識ループコアライブラリ
│   ├── improve/       # 継続的改善モジュール群
│   │   ├── args.sh    # 引数解析
│   │   ├── deps.sh    # 依存関係チェック
│   │   ├── env.sh     # 環境セットアップ
│   │   ├── execution.sh # 実行・監視フェーズ
│   │   └── review.sh  # レビューフェーズ
│   ├── log.sh         # ログ出力
│   ├── marker.sh      # マーカー検出ユーティリティ
│   ├── notify.sh      # 通知機能
│   ├── priority.sh    # 優先度計算
│   ├── session-resolver.sh  # セッション名解決ユーティリティ
│   ├── status.sh      # 状態管理
│   ├── template.sh    # テンプレート処理
│   ├── tracker.sh     # プロンプト効果測定（記録コア）
│   ├── tmux.sh        # マルチプレクサ操作（後方互換ラッパー）
│   ├── multiplexer.sh      # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── workflow.sh    # ワークフローエンジン
│   ├── workflow-finder.sh   # ワークフロー検索
│   ├── workflow-loader.sh   # ワークフロー読み込み
│   ├── workflow-prompt.sh   # プロンプト処理
│   ├── workflow-selector.sh # ワークフロー自動選択（auto モード）
│   ├── worktree.sh    # Git worktree操作
│   └── yaml.sh        # YAMLパーサー
├── workflows/         # ビルトインワークフロー定義
│   ├── ci-fix.yaml    # CI修正ワークフロー
│   ├── default.yaml   # 完全ワークフロー
│   ├── simple.yaml    # 簡易ワークフロー
│   └── thorough.yaml  # 徹底ワークフロー
├── agents/            # エージェントテンプレート
│   ├── ci-fix.md      # CI修正エージェント
│   ├── improve-review.md  # improve.sh レビュープロンプト（カスタマイズ可能）
│   ├── plan.md        # 計画エージェント
│   ├── implement.md   # 実装エージェント
│   ├── review.md      # レビューエージェント
│   ├── test.md        # テストエージェント
│   └── merge.md       # マージエージェント
├── schemas/           # JSON Schema
│   └── pi-runner.schema.json  # .pi-runner.yaml のスキーマ
├── docs/              # ドキュメント
│   ├── README.md          # ドキュメント索引
│   ├── CHANGELOG.md       # 変更履歴
│   ├── SPECIFICATION.md   # 仕様書
│   ├── architecture.md    # アーキテクチャ
│   ├── coding-standards.md # コーディング規約
│   ├── configuration.md   # 設定リファレンス
│   ├── hooks.md           # Hook機能
│   ├── multi-workflow-design.md # マルチワークフロー設計
│   ├── overview.md        # 概要
│   ├── parallel-execution.md # 並列実行
│   ├── public-api.md        # 公開APIリファレンス
│   ├── security.md        # セキュリティ
│   ├── state-management.md # 状態管理
│   ├── multiplexer-integration.md # マルチプレクサ統合（tmux/Zellij）
│   ├── workflows.md       # ワークフロー
│   ├── worktree-management.md # Worktree管理
│   ├── memos/             # メモ・作業記録
│   │   └── README.md
│   └── plans/             # 計画書
│       └── README.md
├── test/              # Batsテスト（*.bats形式）
│   ├── lib/           # ライブラリのユニットテスト
│   │   ├── agent.bats
│   │   ├── batch.bats
│   │   ├── ci-classifier.bats  # ci-classifier.sh のテスト
│   │   ├── ci-fix.bats
│   │   ├── ci-fix/             # ci-fix サブモジュールのテスト
│   │   │   ├── bash.bats
│   │   │   ├── common.bats
│   │   │   ├── detect.bats
│   │   │   ├── escalation.bats
│   │   │   ├── go.bats
│   │   │   ├── node.bats
│   │   │   ├── python.bats
│   │   │   └── rust.bats
│   │   ├── ci-monitor.bats     # ci-monitor.sh のテスト
│   │   ├── ci-retry.bats       # ci-retry.sh のテスト
│   │   ├── cleanup-trap.bats
│   │   ├── cleanup-orphans.bats
│   │   ├── cleanup-improve-logs.bats  # cleanup-improve-logs.sh のテスト
│   │   ├── cleanup-plans.bats
│   │   ├── compat.bats
│   │   ├── config.bats
│   │   ├── context.bats
│   │   ├── daemon.bats
│   │   ├── dashboard.bats
│   │   ├── dependency.bats       # dependency.sh のテスト
│   │   ├── github.bats      # github.sh のテスト
│   │   ├── hooks.bats
│   │   ├── improve/       # improve サブモジュールのテスト
│   │   │   ├── args.bats
│   │   │   ├── deps.bats
│   │   │   ├── env.bats
│   │   │   ├── execution.bats
│   │   │   └── review.bats
│   │   ├── improve.bats
│   │   ├── knowledge-loop.bats  # knowledge-loop.sh のテスト
│   │   ├── log.bats
│   │   ├── marker.bats           # marker.sh のテスト
│   │   ├── notify.bats
│   │   ├── priority.bats
│   │   ├── session-resolver.bats
│   │   ├── status.bats
│   │   ├── template.bats
│   │   ├── tracker.bats
│   │   ├── multiplexer.bats
│   │   ├── multiplexer-tmux.bats
│   │   ├── multiplexer-zellij.bats
│   │   ├── tmux.bats
│   │   ├── workflow.bats
│   │   ├── workflow-finder.bats
│   │   ├── workflow-loader.bats
│   │   ├── workflow-prompt.bats
│   │   ├── workflow-selector.bats
│   │   ├── worktree.bats
│   │   └── yaml.bats
│   ├── scripts/       # スクリプトの統合テスト
│   │   ├── attach.bats
│   │   ├── ci-fix-helper.bats  # ci-fix-helper.sh のテスト
│   │   ├── cleanup.bats
│   │   ├── context.bats
│   │   ├── dashboard.bats
│   │   ├── force-complete.bats  # force-complete.sh のテスト
│   │   ├── generate-config.bats  # generate-config.sh のテスト
│   │   ├── improve.bats
│   │   ├── knowledge-loop.bats  # knowledge-loop.sh のテスト
│   │   ├── init.bats
│   │   ├── list.bats
│   │   ├── mux-all.bats         # mux-all.sh のテスト
│   │   ├── next.bats
│   │   ├── nudge.bats
│   │   ├── run.bats
│   │   ├── run-batch.bats        # run-batch.sh のテスト
│   │   ├── restart-watcher.bats  # restart-watcher.sh のテスト
│   │   ├── status.bats
│   │   ├── stop.bats
│   │   ├── sweep.bats            # sweep.sh のテスト
│   │   ├── test.bats
│   │   ├── tracker.bats
│   │   ├── verify-config-docs.bats
│   │   ├── wait-for-sessions.bats
│   │   └── watch-session.bats
│   ├── regression/    # 回帰テスト
│   │   ├── applescript-injection.bats
│   │   ├── cleanup-race-condition.bats
│   │   ├── config-master-table-dry.bats
│   │   ├── critical-fixes.bats
│   │   ├── escalation-literal-newline.bats
│   │   ├── eval-injection.bats
│   │   ├── hooks-env-sanitization.bats
│   │   ├── issue-1066-spaces-in-filenames.bats
│   │   ├── issue-1129-session-label-arg.bats
│   │   ├── issue-1145-duplicate-agent-override.bats
│   │   ├── issue-1198-duplicate-label-usage.bats
│   │   ├── issue-1211-uninstall-missing-commands.bats
│   │   ├── issue-1220-inline-hook-env.bats
│   │   ├── issue-1259-ci-fix-bash-spaces.bats
│   │   ├── issue-1260-daemon-set-e-corruption.bats
│   │   ├── issue-1261-validate-bash-timeout.bats
│   │   ├── issue-1262-bash-source-guard.bats
│   │   ├── issue-1270-node-grep-pattern.bats
│   │   ├── issue-1280-echo-dash-flags.bats
│   │   ├── multiline-json-grep.bats
│   │   ├── pr-merge-timeout.bats
│   │   ├── shfmt-hardcoded-indent.bats
│   │   ├── workflow-name-template.bats
│   │   └── yaml-bulk-multiline.bats
│   ├── fixtures/      # テスト用フィクスチャ
│   │   └── sample-config.yaml
│   └── test_helper.bash  # Bats共通ヘルパー
└── .worktrees/        # 実行時に作成されるworktreeディレクトリ
```

## 開発コマンド

```bash
# スクリプト実行
./scripts/run.sh 42

# 名前付きワークフローを指定
./scripts/run.sh 42 -w quick
./scripts/run.sh 42 -w frontend

# AI が自動的にワークフローを選択
./scripts/run.sh 42 -w auto

# 利用可能なワークフロー一覧
./scripts/run.sh --list-workflows

# テスト実行（推奨）
./scripts/test.sh              # 全テスト実行
./scripts/test.sh -v           # 詳細ログ付き
./scripts/test.sh -f           # fail-fast モード
./scripts/test.sh lib          # test/lib/*.bats のみ
./scripts/test.sh scripts      # test/scripts/*.bats のみ
./scripts/test.sh regression   # test/regression/*.bats のみ

# Batsテスト直接実行（--jobs で並列化推奨）
bats --jobs 4 test/**/*.bats

# 特定のテストファイル実行
bats test/lib/config.bats

# ShellCheck（静的解析）
./scripts/test.sh --shellcheck    # ShellCheckのみ実行
./scripts/test.sh --all           # Bats + ShellCheck
shellcheck -x scripts/*.sh lib/*.sh  # 直接実行

# 手動テスト
./scripts/list.sh -v
./scripts/status.sh 42

# 全セッションのマーカーチェック
./scripts/sweep.sh --dry-run
./scripts/sweep.sh --force

# 継続的改善
./scripts/improve.sh --max-iterations 1

# 複数セッション待機
./scripts/wait-for-sessions.sh 42 43
```

## コーディング規約

### シェルスクリプト

1. **shebang**: `#!/usr/bin/env bash`
2. **strict mode**: `set -euo pipefail`
   - **全てのファイル**（`scripts/` と `lib/` の両方）で使用する
   - `lib/` ファイルでも設定し、source先の環境に適用することで一貫性を保証する
   - これによりエラーの早期検出とデバッグの容易化を実現する
3. **関数定義**: 小文字のスネークケース
4. **変数**: ローカル変数は `local` を使用
5. **引数チェック**: 必須引数は明示的にチェック

### ファイル構成

- `scripts/` - ユーザーが直接実行するスクリプト
- `lib/` - 共通関数（sourceで読み込み）
- `docs/` - ドキュメント

## テスト

### Batsテストの書き方

> **Note**: 以下はサンプルコードです。`your-module.bats` は実際には存在しません。

```bash
#!/usr/bin/env bats
# test/lib/your-module.bats（架空の例）

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

#### 方法1: `.pi-runner.yaml` の `workflows` セクション（推奨）

複数のワークフローを一箇所で管理できます：

```yaml
# .pi-runner.yaml
workflows:
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  thorough:
    description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
  
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      ## 技術スタック
      - React / Next.js / TypeScript
      - TailwindCSS
      
      ## 重視すべき点
      - レスポンシブデザイン
      - アクセシビリティ
      - コンポーネントの再利用性
```

**使用例**:
```bash
./scripts/run.sh 42 -w quick
./scripts/run.sh 42 -w frontend
./scripts/run.sh 42 -w auto  # AI が自動選択
```

#### 方法2: `workflows/` ディレクトリ（ファイル分散管理）

従来の方法も引き続きサポートされます：

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

> **Note**: `-w NAME` 指定時、`.pi-runner.yaml` の `workflows.{NAME}` が `workflows/{NAME}.yaml` より優先されます。

#### エージェントテンプレートの追加

必要に応じて `agents/` ディレクトリにエージェントテンプレートを追加します

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
| `{{pr_number}}` | PR番号 | ✅（ci-fix） |
| `{{issue_title}}` | Issueタイトル | ✅ |
| `{{branch_name}}` | ブランチ名 | ✅ |
| `{{worktree_path}}` | worktreeのパス | ✅ |
| `{{plans_dir}}` | 計画書ディレクトリパス | ✅ |
| `{{signal_dir}}` | シグナルファイルディレクトリパス | ✅ |
| `{{step_name}}` | 現在のステップ名 | *カスタム用 |
| `{{workflow_name}}` | ワークフロー名 | *カスタム用 |

> **Note**: 「カスタム用」の変数は `lib/workflow.sh` でサポートされていますが、ビルトインのエージェントテンプレート（`agents/*.md`）では使用していません。カスタムワークフローでロギングやデバッグ用途に活用できます。

### ワークフロー検索順序

#### `-w` オプション未指定時（デフォルトワークフロー）

1. `.pi-runner.yaml` の `workflow` セクション
2. `.pi/workflow.yaml`
3. `workflows/default.yaml`
4. ビルトイン `default`

#### `-w NAME` 指定時（名前付きワークフロー）

1. **`.pi-runner.yaml` の `workflows.{NAME}`**（最優先）
2. `.pi/workflow.yaml`
3. `workflows/{NAME}.yaml`
4. ビルトイン `{NAME}`

#### `-w auto` 指定時（AI 自動選択）

`.pi-runner.yaml` の `workflows` セクション全体を読み取り、AI が Issue 内容に基づいて最適なワークフローを選択します。

> **推奨**: 複数のワークフローを使用する場合、`.pi-runner.yaml` の `workflows` セクションで一箇所管理するのが推奨されます。

## ShellCheck

### インストール

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
sudo apt-get install shellcheck

# その他
# https://github.com/koalaman/shellcheck#installing
```

### 実行方法

```bash
# test.shから実行（推奨）
./scripts/test.sh --shellcheck    # ShellCheckのみ
./scripts/test.sh --all           # Bats + ShellCheck

# 直接実行
shellcheck -x scripts/*.sh lib/*.sh
```

### 設定ファイル

プロジェクトルートの `.shellcheckrc` で設定を管理しています：

```bash
# ソースファイルを追跡
external-sources=true

# 無効化している警告
# SC1091: ソースファイルが見つからない（-x オプションで対応）
# SC2016: シングルクォート内で変数展開されない（正規表現で意図的に使用）
```

### CI統合

GitHub Actions で自動的にShellCheckが実行されます。
PRをマージする前に警告が解消されている必要があります。

## 既知の制約

<!-- エージェントが重要な知見を発見した際、ここに1行サマリーとリンクを追加する -->
<!-- 例: - playwright-cli 0.0.63+: デフォルトセッション使用必須 → [詳細](docs/decisions/001-playwright-session.md) -->
- Bats並列テスト: 16ジョブでハング、デフォルト2ジョブ推奨 → [詳細](docs/decisions/001-test-parallel-jobs-limit.md)
- マーカー検出: pipe-pane+grepで全出力を記録・検索、代替パターンも検出 → [詳細](docs/decisions/002-marker-detection-reliability.md)
- 完了検出: シグナルファイル最優先、テキストマーカーはフォールバック → [詳細](docs/decisions/003-signal-file-completion.md)
- ファイル誤上書き防止: コミット前に `git diff --stat` で無関係な変更がないか必ず確認 → [詳細](docs/decisions/004-accidental-file-overwrite.md)
- include test/lib/ci-fix/*.bats in CI and scripts/test.sh (b298b57)
- escape quotes in force-complete.sh send_keys calls (d38f8a3)
- add safeguards against accidental file overwrite in agent prompts (4fa9de3)
- restore run.sh accidentally overwritten by 56c461e (519c24f)
- implement scripts/wait-for-sessions.sh (was stub) (56c461e)
- include lib subdirectories in ShellCheck scanning (3bfd7e7)
- include stale session detection fix from f9db959 (8f3ccb5)
- restore full wait-for-sessions.sh implementation (81d3654)
- restore full wait-for-sessions.sh implementation (be670a9)
- wait-for-sessions.sh の実装を復元 (6d38a57)
- shellcheck warning in wait-for-sessions.sh stub (f3f8d18)
- ShellCheck SC2145 -  を  に修正 (09caaed)
- CI修正 - ShellCheck SC2145対応 (b780672)
- add source guard to lib/generate-config.sh (ec09f7a)
- force-complete.sh にシグナルファイル作成を追加 (2b7d335)
- consolidate duplicate log file reads in check_session_markers() (48367bf)
- replace sed with perl in _strip_ansi() for macOS compatibility (93c2336)
- add safe_timeout wrapper for macOS compatibility (985257b)
- optimize sweep.sh marker verification using grep context extraction (4b15fd3)
- update status to error when session disappears without completion marker (35a2680)
- remove dead code in watch-session.sh pipe-pane mode (acd5e9c)
- use perl instead of sed for ANSI stripping in pipe-pane (e4d3e5c)
- find_orphaned_statuses() の glob パターンを find_worktree_by_issue() と一致させる (d4dc31b)
- add test step to .pi-runner.yaml workflows (default, test) (1133a63)
- detect stale running sessions in wait-for-sessions.sh (f9db959)
- use portable inode check in TOCTOU test (ls -di) (d8a9cce)
- replace echo with printf in has_dangerous_patterns() and classify_ci_failure() (855dd29)
- acquire_cleanup_lock() のステールロック回復の TOCTOU 競合を修正 (302699e)
- strip trailing newline from yq bulk output for multiline YAML values (012c66c)
- remove false error notification when PR is not yet merged (61241f5)
- cleanup.sh がシグナルファイルと pipe-pane 出力ログを削除しない (19f8a98)
- ci-fix/node.sh のフォールバック grep パターンが部分マッチする問題を修正 (53d8b0b)
- sweep.sh がシグナルファイル検出後にファイルを削除しない (99bf36c)
- use trap RETURN for tmpfile cleanup in mux_get_session_output() (2e34010)
- stop checking error markers via capture-pane (false positive source) (fddc043)
- add timeout to _validate_bash() bats execution (92c1e32)
- ci-fix/bash.sh の find | xargs をスペース対応に修正 (37dc3fa)
- daemon.sh の is_daemon_running/stop_daemon が set +e/set -e で呼び出し元のエラー処理を破壊する問題を修正 (b5c7766)
- prevent false error marker detection from merge.md template (49c6513)
- add capture-pane fallback in pipe-pane mode watch loop (dde61d8)
- prevent set -e from killing watcher on check_initial_markers return 1 (21f7f16)
- _validate_bash() bats のハードコードされたパスを動的検出に変更 (c249cb7)
- add explicit source of ci-classifier.sh in ci-fix/common.sh (3fd51fc)
- use perl setpgrp to isolate watcher process group on macOS (e1700a3)
- _validate_bash()と_fix_format_bash()でglob展開失敗時のエラーハンドリング追加 (f5f0c45)
- add improve-related hook events to check_hooks_config() (81d6ce4)
- classify_ci_failure() の分類パターンを厳密化 (a777246)
- remove hardcoded -i 4 from shfmt in _fix_format_bash() (d64766c)
- add watcher/auto/workflow/workflows sections to check_document_structure() (f37d6b6)
- escalate_to_manual() のPRコメントでheredocを使用し改行を正しく出力 (9090910)
- unify inline hook env var to PI_RUNNER_HOOKS_ALLOW_INLINE (52e5163)
- remove duplicate log_debug line in _execute_hook() (6d7871a)
- strip ANSI codes in verification step (defense-in-depth) (f53f905)
- get_failed_ci_logs() が pr_number から --branch フィルタを使用するよう修正 (f127611)
- classify_ci_failure() に Bash/Node/Go/Python のCI失敗パターンを追加 (a97cfde)
- strip ANSI escape codes from pipe-pane output (Issue #1210) (017e005)
- ShellCheck SC2145 - wait-for-sessions.sh の配列展開を修正 (a80b81c)
- pr-merge-timeout.bats テストを現在の実装に合わせて更新 (b853b43)
- 既存のテスト失敗を修正 (e48ac77)
- restore full wait-for-sessions.sh implementation (1ea0697)
- ShellCheck error in wait-for-sessions.sh (4c24d3e)
- add 6 missing commands to uninstall.sh (cd5be17)
- remove duplicate -l, --label option from run.sh usage() (dcec4b2)
- sweep.sh check_session_markers で pipe-pane ログを優先検索し行数を500に引き上げ (6e88667)
- move output_log cleanup trap from run_watch_loop() to main() (469bde7)
- use pipe-pane for reliable marker detection (Issue #1068) (0275e60)
- fallback to default notification on hook script failure too (65e4316)
- fall back to default notification when inline hooks are blocked (35a752e)
- detect alternative marker patterns (COMPLETE_TASK/ERROR_TASK) (9d4ecda)
- replace hardcoded 'tmux session' with 'session' in workflow-prompt.sh (3e7fbda)
- update env.bats tests to match current implementation (4ea969e)
- merge duplicate apply_workflow_agent_override() definitions (15e7c67)
- worktree作成前にgit fetchを実行してorigin/mainを最新化する (b13c14f)
- pass session_label as explicit argument to start_agent_session (7233191)
- インラインフックをデフォルトで有効化 (f386e92)
- ShellCheck警告の修正 (2a1cbb0)
- copy_files_to_worktree のワードスプリッティング処理を修正 (8414b57)
- add improve-related hooks to JSON Schema (cf43991)
- sanitize hook environment variables to prevent command injection (5a07029)
- worktree.sh の copy_files_to_worktree で未クォート変数を修正 (47a13fc)
- テストスイートのタイムアウト問題を修正 (23a4798)
- update regression test to match config-based retry logic (e8fc0ab)
- isolate cleanup lock trap in subshell to prevent overwriting parent traps (6bb120a)
- improve error marker detection accuracy in watch-session.sh (58ad64e)
- add require_config_file checks to main scripts (30434b1)
- add --verbose/-v and --quiet options to run.sh (4c0815c)
- /tmp ハードコードパスを TMPDIR 環境変数対応にする (49bd172)
- pass actual workflow_name to template instead of hardcoded 'default' (8322b60)
- prevent concurrent cleanup race condition between sweep.sh and watch-session.sh (b536e26)
- escape regex metacharacters in marker matching (fa0e608)
- AppleScript injection vulnerability in notify.sh (20eff6f)
- simplify grep pattern in _validate_node for multi-line JSON (b06366d)
- copy_files_to_worktree が空白を含むファイルパスを処理できない問題を修正 (4167013)
- cleanup watcher log regardless of worktree existence (53f3715)
- align CI retry file path with lib/ci-retry.sh (4a347b2)
- remove duplicate pi-sweep entries in install.sh and README.md (c99b9e0)
- improve モジュール合計行数テストの上限を800→900に調整 (#1062) (1b9ffce)
- resolve config associative array scope issues in bats tests (0f435f0)
- multiplexer テストの setup を修正 (2268fa2)
- multiplexer-tmux/zellij の generate_session_name テストを修正 (501b9e7)
- CI回帰テスト・ユニットテストの複数失敗を修正 (6e7d52b)
- improve関連hookの_CONFIG_KEY_MAP・_ENV_OVERRIDE_MAP登録漏れを修正 (f816726)
- install.sh/uninstall.sh に pi-sweep コマンドを追加 (fb47f99)
- improve code block detection in marker.sh (6477219)
- 回帰テストがtest.shとCIで実行されるように修正 (4f14494)
- gh CLI インストールをキャッシュ条件から分離 (fc37164)
- map rule-based workflow categories to real workflow names (a7f1458)
- prevent watcher exit on PR merge timeout (5f408f5)
- optimize sanitize_issue_body sed pipeline (ddaedc4)
- improve daemon.sh macOS compatibility mode reliability (fb948ed)
- disable nounset temporarily for associative array access (d50125d)
- PI_RUNNER_ALLOW_INLINE_HOOKS のデフォルト値を false に修正 (d6cb8be)
- quote $! variable in daemon.sh (8ebbf02)
- lib/improve/execution.sh が未定義のグローバル変数 SCRIPT_DIR に依存している (34cab5f)
- max_wait パラメータを実際の秒数と一致させる (a13eaf3)
- escape variable expansion in improve.bats tests (6345e70)
- accept validation failures in CI environments (f86dd44)
- use schema-compliant config in validation test (5cc9ee2)
- escape variable expansion in improve.bats tests (7b1a724)
- update test expectation for configuration items count (106fece)
- use generate_session_name() in lib/improve/execution.sh (c289341)
- correct status value check in lib/improve/execution.sh (99f4fbb)
- auto選択のデフォルトモデル名を claude-haiku-4-5 に修正 (fba928d)
- improve実行時に完了済みセッションを自動クリーンアップしてスロット解放 (6e3758d)
- .pi-runner.yaml から workflow:(単数形)を削除し workflows.default に移行 (025b445)
- workflows.default を優先し、workflow:(単数形)の生成を廃止 (4d9aff1)
- save initial 'running' status in run.sh to avoid race condition (b408514)
- address review issues in generate-config.sh and schema (404b05e)
- support CONFIG_FILE env var for backward compatibility (3d74fe6)
- replace undefined CONFIG_FILE with config_file_found() API (0136979)
- .pi-runner.yaml の hook 設定でテンプレート変数を環境変数に移行 (4663637)
- prefix unused variables with underscore in workflow-selector.sh (1496dcf)
- clarify branch deletion logic in cleanup-orphans.sh (#941) (d3f4281)
- remove unsupported 'conclusion' field from gh pr checks JSON query (#938) (d42bdbe)
- auto モードで context の複数行テキストがワークフローテーブルを破壊する問題を修正 (3b42713)
- add input validation for numeric arguments in improve/args.sh (#930) (85a7af9)
- 診断テストにも yq キャッシュリセットを追加 (b87a7b0)
- 各テストでYAML/yqキャッシュを明示的にリセット (70f4921)
- テストセットアップでYAMLキャッシュをリセット (778befc)
- load_configの不要な呼び出しを削除 (d12f46d)
- CONFIG_FILE環境変数の扱いを改善 (9307019)
- ShellCheck警告を修正 (d75c289)
- replace log_warn with notify_error in check_pr_merge_status (b6182fc)
- support hyphenated keys in YAML parser (84ef827)
- replace undefined send_notification with log_warn in watch-session.sh (53e6611)
- 単一引用符エスケープパターンを修正 (d5ed2d7)
- run.sh の fetch_issue_data でシングルクォートのエスケープ方法を統一 (78a2fc1)
- replace eval with printf -v in config.sh for safer variable assignment (463069f)
- eval用文字列出力でシングルクォートをエスケープ (a4fa54b)
- escape single quotes in eval contexts to prevent injection (da93836)
- replace eval with bash -c in hooks execution (54308ec)
- implement atomic file writes in status.sh (a9495c4)
- make run_local_validation() multi-project compatible (2ec3755)
- improve workflow respects improve_logs.dir configuration (307477f)
- eval "$(func)" がサブ関数のexit codeを握り潰す問題を修正 (071df42)
- escape single quotes in improve argument parsing (0a4e575)
- Isolate destructive tests to prevent CI race conditions (dcd07a4)
- verify-config-docs.bats にロックメカニズムを追加して並列実行時の競合を防止 (328a590)
- CI並列実行時のテスト競合を修正 (41574e6)
- daemon.bats の不安定なテストを修正 (fd08777)
- properly handle exit codes in parse functions (ee285ab)
- handle --help flag before eval to avoid test failures (6d30bb6)
- resolve ShellCheck warnings in next.sh (36bfc37)
- wait-for-sessions.sh に lib/tmux.sh の source を追加 (aed3bce)
- use absolute path for rm in mock_*_not_installed functions (8ed4afb)
- improve multiplexer test mocks for CI environment (762c9b1)
- テストでマルチプレクサタイプをtmuxに固定 (14b2229)
- tmuxモックが-Fフラグを正しく処理するように修正 (690357d)
- remove unused INTERVAL and LINES variables in mux-all.sh (c7a6ad9)
- .gitignoreに.pi-runner.yamlと.pi-runner.ymlを両方追加 (2a3c420)
- テスト文言をビルトインプロンプトに合わせて修正 (8a9f0ad)
- address ShellCheck warning in verify-config-docs.sh (23373b0)
- ビルトインエージェントプロンプトにtestとci-fixを追加 (d1cdf18)
- list_available_workflows()がビルトインのthoroughとci-fixワークフローを正しく表示するように修正 (ef7c1a6)
- release-workflowテストのMOCK_DIR未設定を修正 (3c0afb8)
- implement sanitize.sh to fix all test failures (5b7505b)
- daemon.sh の find_daemon_pid テスト失敗を修正 (b084d23)
- move variable initialization before sourcing lib/batch.sh (a85498b)
- context.sh tests failing in CI (621e847)
- change log_info to echo for stdout output in context.sh (7b6c144)
- improve worktree cleanup reliability to prevent ENOENT errors (568cddc)
- dashboard.sh JSONモードでの算術エラーを修正 (979cf86)
- Use setup_file() for Bash version check in dashboard tests (72ca171)
- improve context.sh output for better testability (fe1b237)
- Move Bash 4.0+ check to setup() function in dashboard tests (b786552)
- ワークフロー完了前の早期クリーンアップを防止 (417504c)
- 全エージェントテンプレートに gh issue close 禁止事項を追加 (0ccc4bc)
- PRが存在する場合はIssueを直接Closeしない (6923e93)
- 完了時にIssueを明示的にCloseする (f6118cb)
- コードブロック内のマーカーを除外する検出ロジックを追加 (141ec31)
- マーカー検出で最大2空白まで許可 (fa0ab90)
- マーカー検出を厳密化し、エージェント指示を統一 (23f8dcb)
- 004: AIエージェントによるファイル誤上書き事故 (2026-02-10) -> [詳細](docs/decisions/004-accidental-file-overwrite.md)
- 003: シグナルファイルによる完了検出 (2026-02-10) -> [詳細](docs/decisions/003-signal-file-completion.md)
- 002: マーカー検出の信頼性とパフォーマンス改善 (2026-02-08) -> [詳細](docs/decisions/002-marker-detection-reliability.md)

## 注意事項

- すべてのスクリプトは `set -euo pipefail` で始める
- 外部コマンドの存在確認を行う
- エラーメッセージは stderr に出力
- 終了コードを適切に設定する
- ShellCheck警告は意図的な場合を除き修正する
