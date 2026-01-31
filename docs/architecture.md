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
│  ┌────────────────┬──────────────────┬───────────────────┐  │
│  │   config.sh    │   worktree.sh    │     tmux.sh       │  │
│  │                │                  │                   │  │
│  │ - 設定読み込み │ - worktree作成   │ - セッション作成  │  │
│  │ - YAML解析     │ - ファイルコピー │ - セッション監視  │  │
│  │ - 環境変数     │ - クリーンアップ │ - コマンド実行    │  │
│  └────────────────┴──────────────────┴───────────────────┘  │
│  ┌────────────────┬──────────────────┬───────────────────┐  │
│  │   github.sh    │    status.sh     │    workflow.sh    │  │
│  │                │                  │                   │  │
│  │ - Issue取得    │ - 状態管理       │ - ワークフロー    │  │
│  │ - gh CLI連携   │ - JSON永続化     │ - プロンプト生成  │  │
│  └────────────────┴──────────────────┴───────────────────┘  │
│  ┌────────────────┬──────────────────────────────────────┐  │
│  │    log.sh      │         notify.sh                    │  │
│  │                │                                      │  │
│  │ - ログ出力     │ - 通知機能                           │  │
│  │ - デバッグ     │ - 完了/エラー通知                    │  │
│  └────────────────┴──────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
         │                    │                    │
┌────────▼────────┐  ┌────────▼────────┐  ┌───────▼──────┐
│   Git Worktree  │  │  Tmux Sessions  │  │  Pi Process  │
│                 │  │                 │  │              │
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
│   ├── list.sh        # セッション一覧表示
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションにアタッチ
│   ├── stop.sh        # セッション停止
│   ├── cleanup.sh     # クリーンアップ
│   ├── init.sh        # プロジェクト初期化
│   ├── improve.sh     # 継続的改善
│   ├── wait-for-sessions.sh  # 複数セッション待機
│   ├── watch-session.sh      # セッション監視
│   └── test.sh        # テスト実行
├── lib/               # 共通ライブラリ
│   ├── config.sh      # 設定管理
│   ├── github.sh      # GitHub CLI操作
│   ├── log.sh         # ログ出力
│   ├── notify.sh      # 通知機能
│   ├── status.sh      # 状態管理
│   ├── tmux.sh        # tmux操作
│   ├── workflow.sh    # ワークフローエンジン
│   └── worktree.sh    # Git worktree操作
├── workflows/         # ワークフロー定義
│   ├── default.yaml   # 完全ワークフロー
│   └── simple.yaml    # 簡易ワークフロー
├── agents/            # エージェントテンプレート
│   ├── plan.md        # 計画エージェント
│   ├── implement.md   # 実装エージェント
│   ├── review.md      # レビューエージェント
│   └── merge.md       # マージエージェント
├── test/              # Batsテスト
│   ├── lib/           # ライブラリテスト
│   ├── scripts/       # スクリプトテスト
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
| `list.sh` | 実行中のセッション一覧を表示 |
| `status.sh` | 特定Issueの状態を確認 |
| `attach.sh` | 実行中セッションにアタッチ |
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

#### tmux.sh

Tmuxセッションの管理:

```bash
# セッション名生成
session_name="$(generate_session_name 42)"  # → "pi-issue-42"

# セッション作成＆コマンド実行
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

ワークフローとプロンプト生成:

```bash
# プロンプトファイル生成
write_workflow_prompt \
    "$prompt_file" \
    "default" \
    "$issue_number" \
    "$issue_title" \
    "$issue_body" \
    "$branch_name" \
    "$worktree_path"
```

### 3. Infrastructure Layer

**責務**: 外部システムとの連携

**依存ツール**:
- `git` - バージョン管理、worktree操作
- `gh` - GitHub CLI、Issue情報取得
- `tmux` - ターミナルマルチプレクサ
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

6. lib/tmux.sh
   - create_session() でtmuxセッション作成
   - send-keys でpiコマンド実行

7. scripts/watch-session.sh (バックグラウンド)
   - セッション状態監視
   - 完了マーカー検出時にクリーンアップ

8. 完了時
   - scripts/cleanup.sh でworktree/セッション削除
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
| Tmuxセッション作成失敗 | 既存セッションをkillして再試行 |
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
2. **Tmuxペイン** - セッション内でのpi出力
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
