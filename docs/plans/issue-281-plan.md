# Issue #281 実装計画

## 概要

`watch-session.sh` が初期化中（10秒待機）にマーカーが出力された場合に検出できない問題を修正する。

## 影響範囲

- `scripts/watch-session.sh` - メイン修正対象
- `test/scripts/watch-session.bats` - テスト追加

## 原因分析

現在のコードフロー:
1. 10秒間スリープ（初期プロンプト表示待ち）
2. baseline_output をキャプチャ
3. ループで `marker_count_current > marker_count_baseline` を比較

問題: スリープ中にマーカーが出力された場合、baseline にマーカーが含まれるため、
比較 `1 > 1` は false となり、永久に検出されない。

## 解決策

**方法2（推奨）**: 初期化時にマーカーチェックを追加

baseline をキャプチャした直後に、マーカーが既に存在するかをチェックし、
存在する場合は即座に完了処理を実行して終了する。

```bash
# 初期出力をキャプチャ（ベースライン）
baseline_output=$(tmux capture-pane ...)

# 初期化時点でマーカーが既にあるか確認
if echo "$baseline_output" | grep -qF "$marker"; then
    log_info "Completion marker already present at startup"
    handle_complete "$session_name" "$issue_number"
    # クリーンアップ実行
    exit 0
fi
```

同様にエラーマーカーも初期化時にチェックする。

## 実装ステップ

1. [x] 現状のコードを理解
2. [ ] baseline キャプチャ後にマーカーチェックを追加
3. [ ] エラーマーカーも同様にチェック
4. [ ] テストケースを追加
5. [ ] 既存テストが全てパスすることを確認

## テスト方針

- 新規テスト: 「baseline にマーカーが含まれる場合の検出」
- 回帰テスト: 既存のマーカー検出ロジックが引き続き動作すること

## リスクと対策

| リスク | 対策 |
|--------|------|
| 誤検出 | マーカーの完全一致 (`grep -F`) を使用 |
| クリーンアップ失敗 | 既存のエラーハンドリングを維持 |

## 見積もり

- 実装: 15分
- テスト: 15分
- レビュー: 10分
- **合計: 40分**
