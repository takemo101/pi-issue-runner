# Issue #230 Implementation Plan

## 概要

`improve.sh` が `run.sh --no-attach` 実行後、セッションが起動する前に `list.sh` を実行して「セッションなし」と判定してしまう問題を修正する。

## 問題分析

### 原因
1. `run.sh --no-attach` はバックグラウンドでtmuxセッションを起動
2. セッション起動には数秒かかる場合がある
3. `improve.sh` は `run_pi_with_completion_detection()` が完了後すぐに `list.sh` を実行
4. この時点でセッションがまだ起動していないため、「No active sessions found」になる

### 現在のコード（問題箇所）
```bash
# Phase 2: Monitor session completion
echo ""
echo "[PHASE 2] Monitoring session completion..."

# Get running sessions
local sessions
sessions=$("$SCRIPT_DIR/list.sh" 2>/dev/null | grep -oE "pi-issue-[0-9]+" || true)

if [[ -z "$sessions" ]]; then
    echo "No running sessions found"
    # ← ここで早期終了してしまう
```

## 影響範囲

- `scripts/improve.sh` のみ変更

## 実装ステップ

### 1. リトライロジックの追加

Phase 2のセッション取得部分に、リトライロジックを追加する。

```bash
# Wait for sessions to appear with retry
local retry_count=0
local max_retries=10
local sessions=""

while [[ $retry_count -lt $max_retries ]]; do
    sessions=$("$SCRIPT_DIR/list.sh" 2>/dev/null | grep -oE "pi-issue-[0-9]+" || true)
    if [[ -n "$sessions" ]]; then
        break
    fi
    log_debug "Waiting for sessions to start... (attempt $((retry_count + 1))/$max_retries)"
    sleep 2
    ((retry_count++))
done
```

### 2. 設定項目の追加（オプション）

`--session-wait-timeout` オプションを追加して、セッション待機時間を設定可能にする。

### 3. ログ出力の改善

待機中の状態をユーザーに表示する。

## テスト方針

### 1. 手動テスト
- `improve.sh` を実行し、セッションが起動されるまで待機することを確認
- タイムアウト後に適切に終了することを確認

### 2. ユニットテスト
- 既存のテストが壊れていないことを確認
- 必要に応じてリトライロジックのテストを追加

## リスクと対策

| リスク | 対策 |
|--------|------|
| リトライ時間が長すぎる | max_retriesとsleep時間を適切に設定（デフォルト: 10回 × 2秒 = 20秒） |
| セッションが本当に存在しない場合 | リトライ後に適切なメッセージを表示して終了 |

## 見積もり

- 実装: 15分
- テスト: 10分
- レビュー: 5分
- **合計: 30分**
