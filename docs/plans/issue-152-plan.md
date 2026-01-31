# 実装計画書: Issue #152

## 概要

`docs/configuration.md` の内容を実際の `lib/config.sh` 実装に合わせて修正します。

## 影響範囲

- **変更ファイル**: `docs/configuration.md`
- **参照ファイル**: `lib/config.sh`（変更なし、参照のみ）

## 問題点の詳細

### 1. TypeScript実装コード（L280-L370付近）
- `ConfigManager` クラスのTypeScriptコードが記載されている
- 実際は `lib/config.sh` でBashスクリプトとして実装

### 2. 未実装の設定項目
ドキュメントに記載されているが、`lib/config.sh` に実装されていない設定：

| 設定項目 | ドキュメント | 実装 |
|---------|------------|------|
| `worktree.base_dir` | ✅ | ✅ |
| `worktree.copy_files` | ✅ | ✅ |
| `worktree.symlink_node_modules` | ✅ | ❌ |
| `tmux.session_prefix` | ✅ | ✅ |
| `tmux.start_in_session` | ✅ | ✅ |
| `tmux.log_output` | ✅ | ❌ |
| `tmux.capture_interval` | ✅ | ❌ |
| `pi.command` | ✅ | ✅ |
| `pi.args` | ✅ | ✅ |
| `pi.timeout` | ✅ | ❌ |
| `parallel.max_concurrent` | ✅ | ✅ |
| `parallel.queue_strategy` | ✅ | ❌ |
| `parallel.auto_cleanup` | ✅ | ❌ |
| `parallel.resolve_dependencies` | ✅ | ❌ |
| `github` セクション | ✅ | ❌ |
| `logging` セクション | ✅ | ❌ |
| `data` セクション | ✅ | ❌ |
| `resources` セクション | ✅ | ❌ |
| `error` セクション | ✅ | ❌ |
| `notifications` セクション | ✅ | ❌ |

### 3. 環境変数の不一致
実装されている環境変数（`lib/config.sh`）:
- `PI_RUNNER_WORKTREE_BASE_DIR`
- `PI_RUNNER_WORKTREE_COPY_FILES`
- `PI_RUNNER_TMUX_SESSION_PREFIX`
- `PI_RUNNER_TMUX_START_IN_SESSION`
- `PI_RUNNER_PI_COMMAND`
- `PI_RUNNER_PI_ARGS`
- `PI_RUNNER_PARALLEL_MAX_CONCURRENT`

ドキュメントに記載されているが未実装の環境変数:
- `PI_RUNNER_MAX_CONCURRENT`（実装は `PI_RUNNER_PARALLEL_MAX_CONCURRENT`）
- `PI_RUNNER_AUTO_CLEANUP`
- `PI_RUNNER_LOG_LEVEL`
- `PI_RUNNER_DATA_DIR`
- `GITHUB_TOKEN`
- `TMUX_SESSION_PREFIX`（実装は `PI_RUNNER_TMUX_SESSION_PREFIX`）

### 4. 未実装のCLIオプション
- `--config` オプション
- `--max-concurrent` オプション
- `--no-auto-cleanup` オプション
- `pi-run config --show-path`
- `pi-run config --show`
- `pi-run config --validate`
- `pi-run config --init`

## 実装ステップ

### Step 1: 設定ファイルの場所セクション修正
- `--config` オプションの記載を削除
- 検索順序を実装に合わせて修正

### Step 2: YAML形式サンプルの修正
- 実装されている設定項目のみに絞り込む
- 未実装項目はコメントで「将来実装予定」と明記

### Step 3: JSON形式サンプルの修正
- YAML形式と同様に修正

### Step 4: 設定項目の詳細セクション修正
- 未実装項目を削除またはステータスを明記
- デフォルト値を実装に合わせて修正

### Step 5: TypeScriptコードの削除
- `ConfigManager` クラスのコード例を削除
- Bashでの実装概要に置き換え

### Step 6: 環境変数セクション修正
- 実装されている環境変数のみに修正

### Step 7: CLIオプションセクション修正
- `pi-run` を `./scripts/run.sh` に修正
- 未実装オプションを削除

### Step 8: 設定例セクション修正
- 実装済み項目のみを使用した例に修正

### Step 9: トラブルシューティングセクション修正
- 未実装のコマンドを削除

## テスト方針

1. ドキュメントに記載された全設定項目が `lib/config.sh` で動作確認
2. 環境変数のオーバーライドが正しく動作することを確認
3. 設定ファイルのサンプルが有効なYAML/JSONであることを確認

## リスクと対策

| リスク | 対策 |
|-------|------|
| 将来実装予定の機能を削除してしまう | 「将来実装予定」セクションとして残す |
| ユーザーが既存のドキュメントを参照している | 変更内容を明確にコミットメッセージに記載 |

## 作業時間見積もり

- ドキュメント修正: 1-2時間
- レビュー・調整: 30分
- **合計**: 約2時間
