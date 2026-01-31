# Issue #232 Implementation Plan

## refactor: improve.shをtmux方式に変更（run.shと同じ監視方式）

### 概要

`improve.sh` のpi監視方式を、`run.sh`/`watch-session.sh` と同じtmux方式に変更する。
現在の `tee` + `grep` によるマーカー検出から、`tmux capture-pane` を使用した方式に移行する。

### 背景・問題点

現在の `improve.sh` の問題：
- `tee` + `grep` でマーカー検出 → バッファリング問題の可能性
- piを直接起動 → 終了制御が不安定
- `stdbuf -oL` に依存（一部環境で利用不可）

`run.sh`/`watch-session.sh` の方式（目標）：
- tmuxセッション内でpi起動
- `tmux capture-pane` で外部から出力取得
- 確実なマーカー検出と終了制御

### 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `scripts/improve.sh` | メイン変更対象 - tmux方式に書き換え |
| `test/scripts/improve.bats` | テストの更新（存在する場合） |

### 実装ステップ

1. **定数追加**
   - `IMPROVE_SESSION="pi-improve"` - tmuxセッション名

2. **`run_pi_with_completion_detection()` 関数の置き換え**
   - 削除: `tee` + `grep` + バックグラウンドプロセス方式
   - 追加: `wait_for_marker()` 関数（`watch-session.sh` と同様のロジック）

3. **新しいフロー実装**
   ```
   improve.sh
       ↓
   既存セッション確認・削除
       ↓
   Phase 1: tmuxセッション "pi-improve" を作成
       ↓
   tmux内でpiを起動（project-review + Issue作成 + run.sh実行）
       ↓
   tmux capture-pane で出力を監視
       ↓
   ###TASK_COMPLETE### を検出したらtmuxセッションを終了
       ↓
   Phase 2: list.sh でセッションを取得
       ↓
   Phase 3: wait-for-sessions.sh で完了監視
       ↓
   Phase 4: 再帰呼び出し（次のイテレーション）
   ```

4. **`wait_for_marker()` 関数の実装**
   - `tmux capture-pane` で最後200行をキャプチャ
   - `MARKER_COMPLETE` または `MARKER_NO_ISSUES` を検出
   - タイムアウトチェック
   - 戻り値: 0=Issues created, 1=No issues, 2=Timeout

### テスト方針

1. **ユニットテスト**
   - `wait_for_marker()` 関数のテスト（モックtmux使用）
   - 引数パースのテスト

2. **統合テスト**
   - `--help` の動作確認
   - 依存関係チェックの動作確認

3. **手動テスト**
   - 実際にimprove.shを実行して動作確認
   - `--max-iterations 1` で1回のみ実行

### リスクと対策

| リスク | 対策 |
|-------|------|
| tmuxセッション名の衝突 | 既存セッションを削除してから作成 |
| capture-paneの行数制限 | `-S -200` で十分な行数を確保 |
| プロンプト内のシェル変数展開 | シングルクォートで保護 |
| piコマンドのパス解決 | `get_config pi_command` を使用 |

### 見積もり

- 実装: 30分
- テスト: 20分
- 合計: 50分
