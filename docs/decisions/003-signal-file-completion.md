# 003: シグナルファイルによる完了検出 (2026-02-10)

## 問題

マーカー検出がターミナル出力のスクレイピングに依存しており、以下の問題が繰り返し発生していた：

1. **ANSIエスケープコード**: pipe-paneの生出力にカラーコード等が含まれ、完全一致検出に失敗
2. **テンプレート誤検出**: agents/merge.md内のコード例 `echo "###TASK_ERROR_NNN###"` がマーカーとして誤検出
3. **スクロールアウト**: capture-paneのスクロールバック上限を超えるとマーカーが消失
4. **pipe-pane再起動**: 既に出力済みのマーカーはpipe-paneログに含まれない
5. **set -e問題**: マーカー検出コードの複雑さにより、watcher自体が予期せず死亡

improve.shが修正を入れるたびにテンプレートやワークフローが変わり、上記のいずれかが再発していた。

## 対応

### シグナルファイル方式を導入（最優先）

AIが完了/エラー時にファイルを作成し、watcherはファイルの存在だけをチェックする。

```
旧: AI出力テキスト → tmux → pipe-pane → grep → パース → 検出
新: AI が echo "done" > signal-complete-NNN → watcher が [ -f ] → 検出
```

## 現在の検出方式（新旧併存）

### 方式一覧

| 優先度 | 方式 | 導入時期 | 仕組み | 長所 | 短所 |
|--------|------|----------|--------|------|------|
| **1（最優先）** | シグナルファイル | 003 (2026-02-10) | AIが `.worktrees/.status/signal-complete-{issue}` を作成、watcherが `-f` チェック | ANSI・スクロールアウト・誤検出が一切ない。最もシンプルで堅牢 | AIがファイル作成を忘れると検出されない（テキストマーカーでフォールバック） |
| **2** | pipe-pane + grep | 002 (2026-02-08) | `tmux pipe-pane` で全出力をファイルに記録、`grep -cF` で高速検索 | 全出力を記録するためスクロールアウトしない。C速度で高速 | ANSI除去が必要。watcher再起動で既出力を見失う。テンプレート内のマーカー例を誤検出する可能性 |
| **3** | capture-pane フォールバック | 初期〜002 | `tmux capture-pane -p` でスクロールバックを取得、bashでパース | pipe-pane非対応環境（Zellij等）でも動作。watcher再起動後も既出力を拾える | スクロールバック上限あり（デフォルト500行）。ターミナル装飾でコードブロック判定が崩れうる |

### 検出フロー（watch-session.sh）

```
ループ開始
  │
  ├─ Phase 1: シグナルファイルチェック
  │   [ -f signal-complete-NNN ] → 検出 ✅ → クリーンアップ実行
  │   [ -f signal-error-NNN ]   → 検出 ✅ → エラー通知
  │
  ├─ Phase 2: pipe-pane ログ検索（ファイルが存在する場合）
  │   grep -cF "###TASK_COMPLETE_NNN###" output-NNN.log
  │   → ヒット → コードブロック外か検証 → クリーンアップ実行
  │
  ├─ Phase 2.5: capture-pane フォールバック（15ループ≒30秒ごと）
  │   pipe-paneログにマーカーが無い場合のみ実行
  │   tmux capture-pane -p -S -500 でスクロールバック取得
  │   → count_any_markers_outside_codeblock で検出
  │
  └─ Phase 3: capture-pane のみモード（pipe-pane非対応環境）
      毎ループで capture-pane + パース
```

### 検出フロー（sweep.sh）

```
セッションごとに:
  1. シグナルファイルチェック → signal-complete-NNN / signal-error-NNN
  2. pipe-pane ログ検索 → grep -qF
  3. capture-pane フォールバック → count_any_markers_outside_codeblock
```

### エージェントテンプレートの指示（agents/*.md）

AIに対して**両方の方式を実行**するよう指示している：

```markdown
## 完了報告
### 1. シグナルファイルを作成（必須・最優先）
mkdir -p "{{signal_dir}}" && echo "done" > "{{signal_dir}}/signal-complete-{{issue_number}}"

### 2. 完了マーカーをテキスト出力（後方互換）
###TASK_COMPLETE_{{issue_number}}###
```

これにより、シグナルファイルを理解しない古いテンプレートやカスタムワークフローでも、
テキストマーカー方式（Phase 2/3）で検出される。

## シグナルファイル仕様

| ファイル | 用途 | 内容 |
|----------|------|------|
| `.worktrees/.status/signal-complete-{issue}` | 正常完了 | 任意（例: `done`） |
| `.worktrees/.status/signal-error-{issue}` | エラー | エラーメッセージ（先頭200文字を通知に使用） |

- watcherが検出後にファイルを削除（`rm -f`）
- sweep.shは検出のみ（削除はcleanup.shに委譲）
- テンプレート変数 `{{signal_dir}}` でパスを展開

## 実装

### 変更ファイル

- `scripts/watch-session.sh`: Phase 1 にシグナルファイルチェック追加
- `scripts/sweep.sh`: check_session_markers にシグナルファイルチェック追加
- `lib/template.sh`: `{{signal_dir}}` 変数追加
- `agents/*.md`: 全テンプレートにシグナルファイル作成手順追加

## 教訓

- ターミナル出力のスクレイピングはプロセス間通信として脆弱すぎる
- ファイルシステムベースのシグナリングは最もシンプルで堅牢
- 新旧方式を併存させ、フォールバックチェーンを持つことで、どの方式が失敗しても検出できる
- 古い方式を即座に削除せず後方互換として残すことで、カスタムテンプレートや古い環境でも動作を保証する
