# アーキテクチャ設計

## システム構成

```
┌─────────────────────────────────────────────────────────────┐
│                     CLI Interface                           │
│  scripts/run.sh  list.sh  status.sh  attach.sh  cleanup.sh │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                    共通ライブラリ (lib/)                    │
│  ┌────────────────────┬────────────────────┬──────────────┐ │
│  │    agent.sh        │     batch.sh       │  ci-classifier│ │
│  │  - マルチエージェン│  - バッチ処理コア  │  - CI失敗分類│ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │    ci-fix.sh       │  ci-monitor.sh     │  ci-retry.sh │ │
│  │  - CI自動修正      │  - CI状態監視      │  - リトライ  │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │cleanup-improve-logs│ cleanup-orphans.sh │cleanup-plans │ │
│  │  - improve-logs削除│  - 孤立削除        │ - 計画ローテ │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │    config.sh       │   compat.sh        │  context.sh  │ │
│  │  - 設定読込        │  - 互換性ヘルパー  │  - コンテキスト│ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │    daemon.sh       │  dashboard.sh      │  dependency.sh│ │
│  │  - デーモン化      │  - ダッシュボード  │  - 依存解析  │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │    github.sh       │    hooks.sh        │     log.sh   │ │
│  │  - GitHub CLI      │  - Hook機能        │  - ログ出力  │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │  multiplexer.sh    │multiplexer-tmux.sh │multiplexer-  │ │
│  │  - マルチプレクサ  │  - tmux実装        │  zellij.sh   │ │
│  │    抽象化          │                    │  - Zellij実装│ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │    notify.sh       │   priority.sh      │  status.sh   │ │
│  │  - 通知機能        │  - 優先度計算      │  - 状態管理  │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │   template.sh      │  multiplexer.sh    │  workflow.sh │ │
│  │  - テンプレ        │  - セッション      │  - ワーク    │ │
│  │                    │    (tmux/Zellij)   │    フロー    │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │ workflow-loader.sh │workflow-prompt.sh  │workflow-selector│ │
│  │  - WF読み込み      │  - プロンプト      │  - WF自動選択│ │
│  │                    │                    │    (auto)    │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │   worktree.sh      │     yaml.sh        │              │ │
│  │  - worktree        │  - YAMLパーサ      │              │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │ cleanup-trap.sh    │ generate-config.sh │  marker.sh   │ │
│  │  - クリーンアップ  │  - 設定自動生成    │  - マーカー  │ │
│  │    トラップ管理    │                    │    検出      │ │
│  ├────────────────────┼────────────────────┼──────────────┤ │
│  │session-resolver.sh │  improve.sh        │              │ │
│  │  - セッション名    │  - 継続的改善      │              │ │
│  │    解決            │    オーケストレータ│              │ │
│  └────────────────────┴────────────────────┴──────────────┘ │
│  ├── ci-fix/             # CI修正サブモジュール群          │
│  │   ├── common.sh       # 共通ユーティリティ              │
│  │   ├── detect.sh       # プロジェクトタイプ検出          │
│  │   ├── bash.sh         # Bash固有の修正・検証ロジック    │
│  │   ├── go.sh           # Go固有の修正・検証ロジック      │
│  │   ├── node.sh         # Node固有の修正・検証ロジック    │
│  │   ├── python.sh       # Python固有の修正・検証ロジック  │
│  │   ├── rust.sh         # Rust固有の修正・検証ロジック    │
│  │   └── escalation.sh   # エスカレーション処理            │
│  ├── improve/            # 継続的改善サブモジュール群      │
│  │   ├── args.sh         # 引数解析                        │
│  │   ├── deps.sh         # 依存関係チェック                │
│  │   ├── env.sh          # 環境セットアップ                │
│  │   ├── execution.sh    # 実行・監視フェーズ              │
│  │   └── review.sh       # レビューフェーズ                │
└──────────────────────────────────────────────────────────────┘
         │                    │                    │
┌────────▼────────┐  ┌────────▼────────┐  ┌───────▼──────┐
│   Git Worktree  │  │ Multiplexer     │  │  Pi Process  │
│                 │  │ (tmux/Zellij)   │  │              │
│ .worktrees/     │  │ pi-issue-42     │  │ pi running   │
│   issue-42-*/   │  │ pi-issue-43     │  │              │
│   issue-43-*/   │  │ pi-issue-44     │  │              │
└─────────────────┘  └─────────────────┘  └──────────────┘
```

## ディレクトリ構造

```
pi-issue-runner/
├── scripts/           # ユーザー実行可能なスクリプト
│   ├── run.sh         # メインエントリーポイント
│   ├── run-batch.sh   # 複数Issueバッチ実行
│   ├── restart-watcher.sh  # Watcher再起動
│   ├── init.sh        # プロジェクト初期化
│   ├── list.sh        # セッション一覧表示
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションにアタッチ
│   ├── stop.sh        # セッション停止
│   ├── sweep.sh       # 全セッションのマーカーチェック・cleanup
│   ├── mux-all.sh     # 全セッション表示（マルチプレクサ対応）
│   ├── cleanup.sh     # クリーンアップ
│   ├── ci-fix-helper.sh  # CI修正ヘルパー
│   ├── context.sh     # コンテキスト管理
│   ├── dashboard.sh   # ダッシュボード表示
│   ├── generate-config.sh  # プロジェクト解析・設定生成
│   ├── force-complete.sh  # セッション強制完了
│   ├── improve.sh     # 継続的改善
│   ├── next.sh        # 次のタスク取得
│   ├── nudge.sh       # メッセージ送信
│   ├── test.sh        # テスト実行
│   ├── verify-config-docs.sh  # 設定ドキュメントの整合性検証
│   ├── tracker.sh     # プロンプト効果測定（集計・表示）
│   ├── knowledge-loop.sh  # 知識ループ（fixコミットから知見抽出・AGENTS.md更新提案）
│   ├── wait-for-sessions.sh  # 複数セッション待機
│   └── watch-session.sh      # セッション監視
├── lib/               # 共通ライブラリ
│   ├── agent.sh       # マルチエージェント対応
│   ├── batch.sh       # バッチ処理コア機能
│   ├── ci-classifier.sh   # CI失敗タイプ分類
│   ├── ci-fix.sh      # CI失敗検出・自動修正
│   ├── ci-fix/            # CI修正サブモジュール群
│   │   ├── bash.sh        # Bash固有の修正・検証ロジック
│   │   ├── common.sh      # 共通ユーティリティ
│   │   ├── detect.sh      # プロジェクトタイプ検出
│   │   ├── escalation.sh  # エスカレーション処理
│   │   ├── go.sh          # Go固有の修正・検証ロジック
│   │   ├── node.sh        # Node固有の修正・検証ロジック
│   │   ├── python.sh      # Python固有の修正・検証ロジック
│   │   └── rust.sh        # Rust固有の修正・検証ロジック
│   ├── ci-monitor.sh      # CI状態監視
│   ├── ci-retry.sh        # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh  # improve-logsのクリーンアップ
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
│   ├── cleanup-trap.sh     # エラー時クリーンアップトラップ管理
│   ├── config.sh      # 設定管理
│   ├── context.sh     # コンテキスト管理
│   ├── daemon.sh      # プロセスデーモン化
│   ├── dashboard.sh   # ダッシュボード機能
│   ├── dependency.sh  # 依存関係解析・レイヤー計算
│   ├── generate-config.sh  # プロジェクト解析・設定自動生成
│   ├── github.sh      # GitHub CLI操作
│   ├── hooks.sh       # Hook機能
│   ├── improve.sh     # 継続的改善ライブラリ（オーケストレーター）
│   ├── improve/       # 継続的改善サブモジュール群
│   │   ├── args.sh    # 引数解析
│   │   ├── deps.sh    # 依存関係チェック
│   │   ├── env.sh     # 環境セットアップ
│   │   ├── execution.sh # 実行・監視フェーズ
│   │   └── review.sh  # レビューフェーズ
│   ├── log.sh         # ログ出力
│   ├── marker.sh      # マーカー検出ユーティリティ
│   ├── multiplexer.sh      # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── notify.sh      # 通知機能
│   ├── priority.sh    # 優先度計算
│   ├── session-resolver.sh # セッション名解決ユーティリティ
│   ├── status.sh      # 状態管理
│   ├── template.sh    # テンプレート処理
│   ├── tracker.sh     # プロンプト効果測定（記録コア）
│   ├── knowledge-loop.sh  # 知識ループコアライブラリ
│   ├── tmux.sh        # 後方互換ラッパー
│   ├── workflow.sh    # ワークフローエンジン
│   ├── workflow-finder.sh   # ワークフロー検索
│   ├── workflow-loader.sh   # ワークフロー読み込み
│   ├── workflow-prompt.sh   # プロンプト処理
│   ├── workflow-selector.sh # ワークフロー自動選択（autoモード）
│   ├── worktree.sh    # Git worktree操作
│   └── yaml.sh        # YAMLパーサー
├── workflows/         # ワークフロー定義
│   ├── ci-fix.yaml    # CI修正ワークフロー
│   ├── default.yaml   # 完全ワークフロー
│   ├── simple.yaml    # 簡易ワークフロー
│   └── thorough.yaml  # 徹底ワークフロー
├── agents/            # エージェントテンプレート
│   ├── ci-fix.md      # CI修正エージェント
│   ├── improve-review.md  # improve.sh レビュープロンプト
│   ├── plan.md        # 計画エージェント
│   ├── implement.md   # 実装エージェント
│   ├── review.md      # レビューエージェント
│   ├── test.md        # テストエージェント
│   └── merge.md       # マージエージェント
├── test/              # Batsテスト
│   ├── lib/           # ライブラリテスト
│   ├── scripts/       # スクリプトテスト
│   ├── regression/    # 回帰テスト
│   ├── fixtures/      # テスト用フィクスチャ
│   └── test_helper.bash
├── .worktrees/        # worktree作業ディレクトリ（実行時生成）
│   ├── issue-42-*/
│   └── .status/       # ステータスファイル
└── .pi-runner.yaml    # 設定ファイル
```

## レイヤー構成

### 1. CLI Layer (scripts/)

**責務**: ユーザーインターフェース、引数パース、処理の調整

**主要スクリプト**:

| スクリプト | 機能 |
|-----------|------|
| `run.sh` | Issue番号を受け取り、worktree作成からpi起動まで実行 |
| `run-batch.sh` | 複数Issueを依存関係順にバッチ実行 |
| `list.sh` | 実行中のセッション一覧を表示 |
| `status.sh` | 特定Issueの状態を確認 |
| `attach.sh` | 実行中セッションにアタッチ |
| `mux-all.sh` | 全セッションをタイル表示（tmux/Zellij対応） |
| `dashboard.sh` | プロジェクト全体のステータスを表示 |
| `next.sh` | 依存関係を考慮した次のタスクを推奨 |
| `nudge.sh` | セッションへメッセージ送信 |
| `force-complete.sh` | セッション強制完了 |
| `tracker.sh` | ワークフロー別成功率の集計・表示 |
| `knowledge-loop.sh` | fixコミットから知見抽出・AGENTS.md更新提案 |
| `cleanup.sh` | worktreeとセッションをクリーンアップ |

**共通パターン**:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ライブラリ読み込み
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
# ...

main() {
    # 引数パース
    # ビジネスロジック実行
}

main "$@"
```

### 2. Library Layer (lib/)

**責務**: 再利用可能な機能の提供

#### config.sh

設定ファイルの読み込みとデフォルト値の管理:

```bash
# 設定読み込み
load_config

# 設定値取得
worktree_base="$(get_config worktree_base_dir)"  # デフォルト: .worktrees
max_concurrent="$(get_config parallel_max_concurrent)"  # デフォルト: 0 (無制限)
```

**設定優先順位**:
1. 環境変数 (`PI_RUNNER_*`)
2. 設定ファイル (`.pi-runner.yaml`)
3. デフォルト値

#### worktree.sh

Git worktreeの操作:

```bash
# Worktree作成（ブランチ名を引数に）
worktree_path="$(create_worktree "issue-42-feature-name" "main")"

# Worktree削除
remove_worktree "$worktree_path" true  # force=true

# Issue番号からworktreeを検索
existing="$(find_worktree_by_issue 42)"
```

#### multiplexer.sh (tmux.sh)

マルチプレクサセッションの管理（tmux/Zellij対応）:

> **Note**: `tmux.sh` は後方互換性のためのラッパーです。実際の実装は `multiplexer.sh` および `multiplexer-tmux.sh`、`multiplexer-zellij.sh` にあります。

```bash
# セッション名生成
session_name="$(generate_session_name 42)"  # → "pi-issue-42"

# セッション作成＆コマンド実行（multiplexer設定に基づき自動選択）
create_session "$session_name" "$worktree_path" "$command"

# セッション存在確認
if session_exists "$session_name"; then
    attach_session "$session_name"
fi

# 並列実行数チェック
if ! check_concurrent_limit; then
    exit 1
fi
```

#### status.sh

タスク状態の管理:

```bash
# ステータス保存
save_status 42 "running" "$session_name"
save_status 42 "error" "$session_name" "エラーメッセージ"
save_status 42 "complete" "$session_name"

# ステータス取得
status="$(get_status 42)"  # "running", "error", "complete", "unknown"

# エラーメッセージ取得
error="$(get_error_message 42)"
```

#### workflow.sh

ワークフローとプロンプト生成（静的生成方式）:

Pi Issue Runnerは**静的プロンプト生成方式**を採用しています。ワークフロー定義から全ステップのプロンプトを一度に生成し、`.pi-prompt.md` ファイルとして保存します。piエージェントはこのプロンプトファイルを読み込み、各ステップを順次実行します。

```bash
# プロンプトファイル生成（全ステップを含む）
write_workflow_prompt \
    "$prompt_file" \
    "default" \
    "$issue_number" \
    "$issue_title" \
    "$issue_body" \
    "$branch_name" \
    "$worktree_path"
```

> **Note**: 過去には動的ワークフロー実行機能（`run_workflow`, `run_step`, `parse_step_result`）が実装されていましたが、静的プロンプト生成方式の方がシンプルで保守性が高いため、動的実行機能は削除されました（Issue #849）。

### 3. Infrastructure Layer

**責務**: 外部システムとの連携

**依存ツール**:
- `git` - バージョン管理、worktree操作
- `gh` - GitHub CLI、Issue情報取得
- `tmux` または `zellij` - ターミナルマルチプレクサ（いずれか必須）
- `jq` - JSON処理（オプション）
- `yq` - YAML処理（オプション）

## データフロー

### タスク実行フロー

```
1. ユーザー入力
   ./scripts/run.sh 42

2. scripts/run.sh
   - 引数パース
   - load_config() で設定読み込み
   - check_concurrent_limit() で並列数チェック

3. lib/github.sh
   - get_issue_title(42) でタイトル取得
   - get_issue_body(42) で本文取得

4. lib/worktree.sh
   - create_worktree("issue-42-feature") でworktree作成
   - copy_files_to_worktree() で.envコピー

5. lib/workflow.sh
   - write_workflow_prompt() でプロンプトファイル生成

6. lib/multiplexer.sh (tmux.sh)
   - create_session() でセッション作成（tmux/Zellij）
   - send-keys でpiコマンド実行

7. scripts/watch-session.sh (バックグラウンド)
   - セッション状態監視
   - 完了マーカー検出時にクリーンアップ

8. 完了時
   - scripts/cleanup.sh でworktree/セッション削除
```

### run:/call: ステップの実行アーキテクチャ

ワークフローにはAIステップ（plan, implement等）と非AIステップ（`run:`, `call:`）を混在させることができます。以下はその内部アーキテクチャです。

#### ステップグループの分割

`workflow-loader.sh` の `get_step_groups()` が、ワークフローの全ステップを**連続する同種ステップのグループ**に分割します。

```
ワークフロー定義:
  steps:
    - plan              ─┐
    - implement          │→ ai_group: "plan implement"
    - run: npm test     ─┐
    - call: code-review  │→ non_ai_group: "run\tnpm test..." + "call\tcode-review..."
    - merge             ─┘→ ai_group: "merge"

分割結果（_STEP_GROUPS_DATA）:
  グループ0: ai_group      → "plan implement"
  グループ1: non_ai_group  → run/call ステップ群
  グループ2: ai_group      → "merge"
```

連続するAIステップ同士、連続する非AIステップ同士がそれぞれ1つのグループにまとめられます。

#### フェーズ追跡の仕組み

`watch-session.sh` はグローバル変数 `_CURRENT_PHASE_INDEX` でフェーズの進行を追跡します。

```
_CURRENT_PHASE_INDEX = 0（初期値）

[1] AI が plan → implement を実行
    → "###PHASE_COMPLETE_42###" マーカーを出力
    → watch-session.sh が output_log をポーリングして検出
    → handle_phase_complete() が呼ばれる
    → _CURRENT_PHASE_INDEX を +1 → グループ1（non_ai_group）

[2] _run_non_ai_steps() が run/call ステップを順次実行
    ├── 成功 → _CURRENT_PHASE_INDEX を +1 → グループ2（ai_group）
    │         → AIセッションに次のステップのプロンプトを nudge（send_keys）
    └── 失敗 → エラー内容を AIセッションに nudge
              → AIが修正して再度 PHASE_COMPLETE を出力すると再実行

[3] AI が merge を実行
    → "###TASK_COMPLETE_42###" マーカーを出力（最終グループ）
    → handle_complete() でタスク完了処理
```

#### マーカーの種類と役割

| マーカー | 出力元 | 検出先 | 役割 |
|----------|--------|--------|------|
| `###PHASE_COMPLETE_<issue>###` | AIセッション | watch-session.sh | 非AIステップ群の実行をトリガー |
| `###TASK_COMPLETE_<issue>###` | AIセッション | watch-session.sh | タスク全体の完了 |
| `###TASK_ERROR_<issue>###` | AIセッション | watch-session.sh | エラー通知 |

AIのプロンプトには「フェーズ完了時にマーカーを出力すること」が指示されますが、`run:`/`call:` コマンドの具体的な内容はプロンプトに含まれません。**何を実行するかの判断は全て `watch-session.sh` 側がインデックスで決定します**。

#### run: と call: の実行方式

- **`run:`** — `run_command_step()` が worktree 内で `bash -c` によりシェルコマンドを直接実行
- **`call:`** — `run_call_step()` が別のAIインスタンスを `--print` モード（非インタラクティブ）で起動。プロンプトファイルを一時生成し、完了後にマーカーで成否を判定

#### セッション間の独立性

`run.sh` はIssueごとに `watch-session.sh` を `daemonize` で**別プロセス**として起動します。`_CURRENT_PHASE_INDEX` や `_STEP_GROUPS_DATA` は各プロセスのシェル変数として保持されるため、**複数セッションが同時に動いていても互いの状態が干渉することはありません**。

```
Issue #42: run.sh → daemonize → watch-session.sh (PID 1234)
             └── _CURRENT_PHASE_INDEX, _STEP_GROUPS_DATA（プロセス固有）

Issue #43: run.sh → daemonize → watch-session.sh (PID 5678)
             └── _CURRENT_PHASE_INDEX, _STEP_GROUPS_DATA（プロセス固有）
```

### 並列実行フロー

```
1. 複数Issueを連続実行
   ./scripts/run.sh 42 --no-attach
   ./scripts/run.sh 43 --no-attach
   ./scripts/run.sh 44 --no-attach

2. 各スクリプトで
   - check_concurrent_limit() が現在のセッション数をチェック
   - max_concurrent を超えていたらエラー

3. 全セッション完了待機
   ./scripts/wait-for-sessions.sh 42 43 44

4. 結果確認
   ./scripts/status.sh 42
   ./scripts/status.sh 43
   ./scripts/status.sh 44
```

## 状態管理

### ステータスファイル

**保存先**: `.worktrees/.status/{issue_number}.json`

**形式**:
```json
{
  "issue": 42,
  "status": "running",
  "session": "pi-issue-42",
  "timestamp": "2024-01-30T09:00:00Z"
}
```

### 状態遷移

```
    run.sh開始
        ↓
    [running]
      ↙    ↘
  成功      失敗
   ↓         ↓
[complete] [error]
   ↓         ↓
 cleanup   cleanup
```

## エラーハンドリング

### エラー時の動作

```bash
# scripts/run.sh での例
set -euo pipefail  # エラー時即座に終了

# クリーンアップトラップ設定
setup_cleanup_trap cleanup_worktree_on_error

# 成功時はトラップ解除
unregister_worktree_for_cleanup
```

### リカバリー戦略

| エラー種別 | 対処 |
|-----------|------|
| Worktree作成失敗 | 既存worktreeを `--force` で削除後再試行 |
| マルチプレクサセッション作成失敗 | 既存セッションをkillして再試行 |
| GitHub API失敗 | エラーメッセージを表示して終了 |
| Pi実行失敗 | ステータスを "error" にマーク |

## ログ管理

### ログレベル

```bash
# lib/log.sh
log_debug "詳細なデバッグ情報"  # DEBUG=1 時のみ出力
log_info "一般的な情報"
log_warn "警告"
log_error "エラー"
```

### ログ出力先

1. **標準出力/エラー出力** - リアルタイムフィードバック
2. **マルチプレクサペイン** - セッション内でのpi出力（tmux/Zellij）
3. **監視ログ** - `/tmp/pi-watcher-{session}.log`

## セキュリティ考慮事項

### 機密情報の取り扱い

1. **環境変数**: `.env` ファイルはworktreeにコピーするがログには記録しない
2. **GitHub Token**: `gh` CLI の認証機構を使用
3. **Issue本文**: `sanitize_issue_body()` でサニタイズ処理

### ファイルアクセス

- Worktreeは親リポジトリと同じ権限
- ステータスファイルは通常のファイル権限

## テスト戦略

### Batsテスト

```bash
# 全テスト実行
./scripts/test.sh

# 特定カテゴリ
./scripts/test.sh lib        # lib/*.shのテスト
./scripts/test.sh scripts    # scripts/*.shのテスト

# ShellCheck
./scripts/test.sh --shellcheck
```

### テスト種別

| 種別 | 場所 | 内容 |
|------|------|------|
| ユニット | `test/lib/` | 各lib関数のテスト |
| 統合 | `test/scripts/` | スクリプト全体のテスト |
| 回帰 | `test/regression/` | バグ修正の回帰テスト |

## ベストプラクティス

1. **スクリプト作成時**
   - `set -euo pipefail` を必ず使用
   - 引数チェックを明示的に実施
   - エラーメッセージは stderr に出力

2. **並列実行時**
   - `parallel_max_concurrent` で上限設定
   - `--no-attach` オプションでバックグラウンド実行
   - `wait-for-sessions.sh` で完了待機

3. **クリーンアップ**
   - 完了マーカー検出で自動クリーンアップ
   - 手動クリーンアップは `cleanup.sh` を使用
