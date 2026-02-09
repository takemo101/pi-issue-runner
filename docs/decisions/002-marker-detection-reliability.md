# 002: マーカー検出の信頼性とパフォーマンス改善 (2026-02-08)

## 問題

`watch-session.sh` のマーカー検出（`###TASK_COMPLETE_<issue>###`）が失敗するケースが複数発生した。

### 検出漏れ1: マーカーの語順間違い

AIエージェントがマーカーの語順を間違えて `###COMPLETE_TASK_<issue>###` と出力。
エージェントテンプレート（`agents/*.md`）ではマーカーを分解して記載しており（AI説明中の誤出力防止のため）、
組み立て時に語順が逆になるケースがあった。

### 検出漏れ2: スクロールアウト

監視ループは `tmux capture-pane -p -S -100` で末尾100行のみキャプチャしていた。
マーカー出力後にAIが100行以上出力すると、マーカーがキャプチャ範囲外に消え、永遠に検出されなかった。

### 通知漏れ: インラインhookのブロック

カスタムhookがインラインコマンド（osascript等）として設定されていたが、
`PI_RUNNER_ALLOW_INLINE_HOOKS=true` が未設定でブロックされた。
ブロック時にデフォルト通知へのフォールバックがなく、通知が一切送られなかった。

## 対応

### マーカーの語順間違い対応

- `lib/marker.sh` に `count_any_markers_outside_codeblock()` を追加（複数パターン対応）
- `watch-session.sh` / `sweep.sh` で代替パターン（`COMPLETE_TASK` / `ERROR_TASK`）も検出

### スクロールアウト対策: pipe-pane + grep

`tmux pipe-pane` で全セッション出力をファイルに記録し、`grep -cF` で直接検索する方式に変更。

**設計判断のポイント:**

1. **なぜ `capture-pane` の行数増加だけでは不十分か**
   - tmuxスクロールバックバッファにも上限がある
   - 2秒の監視間隔中に大量出力があればどんな行数でもスクロールアウトの可能性がある

2. **なぜ `pipe-pane` を使うか**
   - `tmux pipe-pane -t <session> "cat >> <file>"` で全出力をリアルタイム記録
   - ファイルにはセッションの全出力が蓄積されるため、マーカーが絶対に消えない
   - tmux組み込み機能なので追加依存なし

3. **なぜファイル全体をbashに読み込まないか**
   - 長時間セッションでログファイルが数MB〜数十MBになりうる
   - bash変数に読み込んでwhileループでスキャンするとO(n) bash速度で非常に遅い
   - `grep -cF` はCレベルのストリーム処理でメモリ消費も一定

4. **検出フロー（2段階）**
   ```
   [毎2秒] grep -cF でファイル検索 → カウント変化なし → 即終了（軽量）
                                     → カウント増加 → grep -B15 -A15 で周辺抽出
                                                    → コードブロック内か検証（重い処理は最小限）
   ```

5. **フォールバック設計**
   - Zellij等pipe-pane非対応環境: `capture-pane 1000行` + 累積カウント方式
   - 累積カウント: 一度検出したマーカーのカウントを記憶し、キャプチャ範囲外に消えても再検出しない

### hook フォールバック

- `_execute_hook` がインラインhookブロック時に `return 2` を返す
- `run_hook` が戻り値2を受けて `_run_default_hook`（デフォルト通知）を実行
- hookスクリプト実行失敗時（return 1+）もデフォルト通知にフォールバック
- `_run_default_hook` に improve 系イベント5種を追加（不要な "Unknown hook event" 警告を解消）

## 関連コミット

- `fix: detect alternative marker patterns (COMPLETE_TASK/ERROR_TASK)`
- `fix: fall back to default notification when inline hooks are blocked`
- `fix: fallback to default notification on hook script failure too`
- `fix: use pipe-pane for reliable marker detection (Issue #1068)`
- `perf: use grep for fast marker detection instead of reading entire log`
