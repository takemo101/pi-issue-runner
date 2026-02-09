---
name: pi-issue-runner
description: GitHub IssueからGit worktreeを作成し、ターミナルマルチプレクサ（tmux/Zellij）のセッション内で別のpiインスタンスを起動してタスクを実行します。並列開発に最適。
---

# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、ターミナルマルチプレクサ（tmux/Zellij）のセッション内で独立したpiインスタンスを起動します。

## クイックリファレンス

```bash
# Issue実行（メインコマンド）
# デフォルトでpi終了後に自動クリーンアップ
scripts/run.sh <issue-number> [options]

Options:
  -i, --issue <number>   Issue番号（位置引数の代替）
  -w, --workflow <name>  ワークフロー名（省略時: workflows セクションがあれば auto、なければ default）
  --list-workflows       利用可能なワークフロー一覧を表示
  --no-attach            バックグラウンドで起動
  --no-cleanup           自動クリーンアップを無効化
  --reattach             既存セッションにアタッチ
  --force                強制再作成
  -b, --branch <name>    カスタムブランチ名
  --base <branch>        ベースブランチ
  --agent-args <args>    エージェントに渡す追加の引数
  --pi-args <args>       --agent-args のエイリアス（後方互換性）
  -l, --label <label>    セッションラベル（識別用タグ）
  --ignore-blockers      依存関係チェックをスキップして強制実行
  --show-config          現在の設定を表示（デバッグ用）
  --list-agents          利用可能なエージェントプリセット一覧を表示
  --show-agent-config    エージェント設定を表示（デバッグ用）
  -v, --verbose          詳細ログを表示
  --quiet                エラーのみ表示

# バッチ実行（依存関係順）
scripts/run-batch.sh <issue>... [options]
scripts/run-batch.sh 42 43 44 --dry-run     # 実行計画のみ表示
scripts/run-batch.sh 42 43 44 --sequential  # 順次実行

# タスク提案
scripts/next.sh                          # 次に実行すべきIssueを提案
scripts/next.sh -n 3                     # 次の3件を提案
scripts/next.sh -l feature               # featureラベル付きから提案
scripts/next.sh --json                   # JSON形式で出力
scripts/next.sh -v                       # 詳細な判断理由を表示

# プロジェクト初期化
scripts/init.sh                          # プロジェクト初期化（.pi-runner.yaml等を作成）
scripts/init.sh --full                   # 完全セットアップ（agents/, workflows/ も作成）
scripts/init.sh --minimal                # 最小セットアップ（.pi-runner.yaml のみ）
scripts/init.sh --force                  # 既存ファイルを上書き

scripts/generate-config.sh               # AIでプロジェクトを解析し.pi-runner.yamlを生成
scripts/generate-config.sh --dry-run     # 結果をプレビュー
scripts/generate-config.sh --no-ai       # AI不使用で静的テンプレート生成
scripts/generate-config.sh --validate    # 既存設定を検証

# コンテキスト管理
scripts/context.sh show <issue>          # Issue固有のコンテキストを表示
scripts/context.sh show-project          # プロジェクトコンテキストを表示
scripts/context.sh add <issue> <text>    # Issue固有のコンテキストに追記
scripts/context.sh add-project <text>    # プロジェクトコンテキストに追記
scripts/context.sh edit <issue>          # エディタでIssue固有コンテキストを編集
scripts/context.sh list                  # コンテキストがあるIssue一覧
scripts/context.sh clean [--days N]      # 古いコンテキストを削除
scripts/context.sh export <issue>        # Markdown形式でエクスポート
scripts/context.sh remove <issue>        # Issue固有のコンテキストを削除

# セッション管理
scripts/list.sh                          # セッション一覧
scripts/mux-all.sh -w                    # 全セッションをタイル表示
scripts/dashboard.sh                     # プロジェクトダッシュボード
scripts/dashboard.sh --compact           # サマリーのみ表示
scripts/dashboard.sh --json              # JSON出力
scripts/dashboard.sh --watch             # 自動更新（5秒ごと）
scripts/attach.sh <session>              # セッションにアタッチ
scripts/status.sh <session>              # 状態確認
scripts/stop.sh <session>                # セッション停止
scripts/sweep.sh                         # 全セッションのマーカーチェック・cleanup
scripts/sweep.sh --dry-run               # 対象セッション表示のみ
scripts/sweep.sh --force                 # PRマージ確認をスキップ
scripts/sweep.sh --check-errors          # ERRORマーカーもチェック
scripts/cleanup.sh <session>             # 手動クリーンアップ
scripts/force-complete.sh <session>      # セッション強制完了
scripts/force-complete.sh 42 --error     # エラーとして完了
scripts/restart-watcher.sh <session>     # Watcher再起動
scripts/restart-watcher.sh 42            # Issue番号でも指定可能

# メッセージ送信
scripts/nudge.sh <issue-number>          # セッションに続行を促すメッセージを送信
scripts/nudge.sh 42 --message "続けてください"

# ワークフロー選択
# .pi-runner.yaml に workflows セクションがある場合、-w 省略時は auto（AI自動選択）
scripts/run.sh 42                         # workflows あり → auto / なし → default
scripts/run.sh 42 -w frontend            # 明示的にフロントエンド用ワークフローを指定
scripts/run.sh 42 -w auto                # AIがIssue内容から自動選択（明示指定）
scripts/run.sh 42 --workflow ci-fix       # CI修正ワークフロー

# 継続的改善
scripts/improve.sh                    # レビュー→Issue作成→実行→待機のループ
scripts/improve.sh --dry-run          # レビューのみ（Issue作成しない）
scripts/improve.sh --review-only      # 問題表示のみ
scripts/improve.sh --max-iterations 2 # 最大2回繰り返す
scripts/improve.sh --auto-continue    # 自動継続（承認スキップ）
scripts/wait-for-sessions.sh 42 43    # 複数セッション完了待機
```

## 前提条件

- **Bash 4.0以上** (macOSの場合: `brew install bash`)
- `gh` (GitHub CLI、認証済み)
- `tmux` または `zellij` (ターミナルマルチプレクサ)
- `pi`
- `jq` (JSON処理)
- `yq` (オプション - YAML解析の精度向上。なくても動作します)

## 非同期実行について

**重要**: `run.sh` を実行すると、バックグラウンドで `watch-session.sh` が自動起動し、完了を監視します。
そのため、**`wait-for-sessions.sh` を呼ぶ必要はありません**。

```bash
# 推奨: --no-attach でバックグラウンド起動
scripts/run.sh 42 --no-attach
# → 即座に制御が返る
# → 完了時に自動で通知が届く

# 進捗確認が必要な場合
scripts/status.sh 42
scripts/list.sh
```

`wait-for-sessions.sh` は特殊なケース（複数セッションの同期待機が必要な場合など）にのみ使用してください。

## 自動クリーンアップ

タスク完了時またはエラー発生時にAIが特定のマーカーを出力すると、
`watch-session.sh` が検出して適切な処理を実行します。

### マーカー形式

| マーカー | 説明 | 動作 |
|----------|------|------|
| `###TASK_COMPLETE_<issue_number>###` | 正常完了 | 自動クリーンアップ実行 |
| `###TASK_ERROR_<issue_number>###` | エラー発生 | 通知送信、手動対応待ち |

### 動作フロー

1. `run.sh` がバックグラウンドで `watch-session.sh` を起動
2. `watch-session.sh` がセッションの出力を監視
3. マーカー（例: `###TASK_COMPLETE_42###` または `###TASK_ERROR_42###`）を検出
4. 完了マーカーの場合は自動的に `cleanup.sh` を実行、エラーマーカーの場合は通知を送信

### 自動クリーンアップの無効化

```bash
# 自動クリーンアップを無効化
scripts/run.sh 42 --no-cleanup
```

### メッセージ送信

実行中のセッションにメッセージを送信して、続行を促すことができます。

```bash
# セッションにメッセージを送信（続行を促す）
scripts/nudge.sh <issue-number> [options]
scripts/nudge.sh 42 --message "続けてください"
```

| オプション | 説明 |
|-----------|------|
| `-m, --message TEXT` | 送信するメッセージ（デフォルト: "続けてください"） |
| `-s, --session NAME` | セッション名を明示的に指定 |

## ワークフロー選択ガイド

`-w` オプションでワークフローを指定できます。プロジェクトの `.pi-runner.yaml` に `workflows` セクションが定義されている場合、**`-w` 省略時は自動的に `auto`**（AI自動選択）になります。

### auto モードの動作

auto モードでは2段階で処理されます：
1. **事前選択**: `pi --print` + 軽量モデル（haiku）でワークフロー名を高速に判定
2. **プロンプト生成**: 選択されたワークフローの `agents/*.md` テンプレートが展開された通常のプロンプトを生成

AI呼び出しが失敗した場合はIssueタイトルのプレフィックス（`feat:` / `fix:` / `docs:` 等）によるルールベース判定にフォールバックします。

### 判断基準

| 状況 | 推奨する `-w` |
|------|--------------|
| Issue内容に応じてAIに任せたい | 省略（auto）または `-w auto` |
| CI失敗の修正 | `-w ci-fix` |
| typo・設定変更など小さな修正 | `-w simple` |
| 特定のワークフローを使いたい | `-w <name>`（例: `-w frontend`） |

### 利用可能なワークフロー確認

```bash
scripts/run.sh --list-workflows
```

## 詳細ドキュメント

詳しい使い方、設定、トラブルシューティングは [README.md](README.md) を参照してください。
