# 実装計画: Issue #236

## 概要

`docs/` 配下のアーキテクチャドキュメントをTypeScript/Bun実装からBashシェルスクリプト実装に合わせて書き直す。

## 影響範囲

以下のドキュメントファイルを更新：

| ファイル | 内容 |
|----------|------|
| `docs/architecture.md` | システム全体のアーキテクチャ |
| `docs/parallel-execution.md` | 並列実行の仕組み |
| `docs/state-management.md` | 状態管理の仕組み |
| `docs/tmux-integration.md` | Tmux統合の詳細 |
| `docs/worktree-management.md` | Git worktree管理 |

## 実装ステップ

### Step 1: architecture.md の更新
- TypeScript クラス定義を Bash 関数参照に変更
- `cli.ts`, `commands/*.ts` を `scripts/*.sh`, `lib/*.sh` に変更
- Bun CLI API への言及を削除
- 実際のファイル構造とコンポーネント図を更新

### Step 2: parallel-execution.md の更新
- TypeScript インターフェース・クラスを Bash 関数に変更
- `lib/tmux.sh` の `check_concurrent_limit()` を参照
- `scripts/wait-for-sessions.sh` を参照
- async/await パターンを Bash のバックグラウンドプロセスに変更

### Step 3: state-management.md の更新
- TypeScript の TaskStateStore クラスを `lib/status.sh` の関数群に変更
- JSON操作を jq ベースの実装に変更
- `.worktrees/.status/` ディレクトリ構造を反映

### Step 4: tmux-integration.md の更新
- TypeScript 実装を `lib/tmux.sh` の関数群に変更
- `Bun.spawn()` を直接の tmux コマンド呼び出しに変更
- 実際のセッション管理フローを反映

### Step 5: worktree-management.md の更新
- TypeScript 実装を `lib/worktree.sh` の関数群に変更
- `Bun.file()` を Bash のファイル操作に変更
- 実際のブランチ命名規則 (`feature/issue-XXX-*`) を反映

## テスト方針

- ドキュメントの更新のみのため、単体テストは不要
- ShellCheck は影響なし
- マークダウンの構文チェック（目視確認）

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存リンクの破損 | 内部リンクの整合性を確認 |
| 情報の欠落 | 実装コードと照合して網羅性を確認 |

## 参照する実装ファイル

### scripts/
- `run.sh` - メインエントリーポイント
- `list.sh` - セッション一覧
- `status.sh` - 状態確認
- `cleanup.sh` - クリーンアップ
- `wait-for-sessions.sh` - 複数セッション待機
- `watch-session.sh` - セッション監視

### lib/
- `config.sh` - 設定管理
- `status.sh` - 状態管理
- `tmux.sh` - Tmux操作
- `worktree.sh` - Git worktree操作
- `workflow.sh` - ワークフローエンジン
- `github.sh` - GitHub CLI操作
- `log.sh` - ログ出力
- `notify.sh` - 通知機能

## 完了条件

- [x] 実装計画書を作成
- [x] `docs/architecture.md` をBash実装に更新
- [x] `docs/parallel-execution.md` をBash実装に更新
- [x] `docs/state-management.md` をBash実装に更新
- [x] `docs/tmux-integration.md` をBash実装に更新
- [x] `docs/worktree-management.md` をBash実装に更新
- [x] TypeScript/Bunへの参照が削除されている
- [x] 実際のスクリプトファイルへの参照が追加されている
