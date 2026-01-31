# Issue #216 Implementation Plan

## 概要

`improve.sh` にpiの出力を監視し、完了マーカー検出時にpiを自動終了させる機能を追加する。

## 影響範囲

- **scripts/improve.sh** - メイン変更対象
- **test/improve_test.sh** - 既存テストの更新
- **test/scripts/improve.bats** - Batsテストの更新

## 実装ステップ

### Step 1: run_pi_with_completion_detection() 関数の追加

`improve.sh` に以下の関数を追加：

```bash
run_pi_with_completion_detection() {
    local prompt="$1"
    local pi_command="$2"
    local output_file
    output_file=$(mktemp)
    local marker="###TASK_COMPLETE###"
    local no_issues_marker="###NO_ISSUES###"
    local pi_pid
    
    # piをバックグラウンドで起動し、出力をファイルとターミナルに出力
    "$pi_command" --message "$prompt" 2>&1 | tee "$output_file" &
    pi_pid=$!
    
    # 完了マーカーを監視
    while kill -0 "$pi_pid" 2>/dev/null; do
        if grep -q "$marker" "$output_file" 2>/dev/null; then
            log_info "完了マーカー検出。piを終了します..."
            kill "$pi_pid" 2>/dev/null || true
            wait "$pi_pid" 2>/dev/null || true
            rm -f "$output_file"
            return 0  # Issue作成あり
        fi
        if grep -q "$no_issues_marker" "$output_file" 2>/dev/null; then
            log_info "問題なしマーカー検出。piを終了します..."
            kill "$pi_pid" 2>/dev/null || true
            wait "$pi_pid" 2>/dev/null || true
            rm -f "$output_file"
            return 1  # Issue作成なし
        fi
        sleep 1
    done
    
    rm -f "$output_file"
    return 0
}
```

### Step 2: プロンプトの更新

完了マーカーの出力指示をプロンプトに追加：

```markdown
完了したら以下のいずれかを出力:
- Issueを作成した場合: ###TASK_COMPLETE###
- 問題が見つからない場合: ###NO_ISSUES###
```

### Step 3: PHASE 1の変更

```bash
echo "[PHASE 1] piでレビュー＆Issue作成＆実行開始..."

if ! run_pi_with_completion_detection "$prompt" "$pi_command"; then
    echo "✅ 改善完了！問題は見つかりませんでした。"
    exit 0
fi

echo "[PHASE 2] セッション完了を監視中..."
```

### Step 4: テストの追加

1. `run_pi_with_completion_detection()` 関数の存在確認テスト
2. マーカー検出ロジックのテスト
3. 戻り値のテスト（Issue作成あり/なし）

## テスト方針

### ユニットテスト
- 関数の存在確認
- マーカー定数の確認
- コードパスの検証

### 統合テスト（手動）
- 実際にpiを起動してマーカー検出を確認
- タイムアウトなしでの動作確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| teeコマンドのバッファリング | `stdbuf -oL` の使用を検討 |
| pi終了時のゾンビプロセス | `wait` コマンドで確実に回収 |
| 一時ファイルの残存 | trapによるクリーンアップ |

## 実装順序

1. 関数の追加
2. プロンプトの更新
3. PHASE 1の変更
4. テストの追加
5. 既存テストの修正（削除されたオプションへの参照）

## 見積もり

- 実装: 45分
- テスト: 30分
- **合計: 1.25時間**
