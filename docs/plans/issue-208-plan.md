# Implementation Plan: Issue #208

## refactor: improve.shをシンプル化（piをオーケストレーターに）

## 概要

`improve.sh` を再設計し、piとimprove.shで役割分担を明確にする。現在の複雑なGitHub API呼び出しやマーカー抽出ロジックを削除し、シンプルな再帰呼び出し方式に変更する。

## 新しい役割分担

| 担当 | 役割 |
|------|------|
| **pi** | Issue作成 + run.sh --no-attach で実行開始 |
| **improve.sh** | 完了監視 + 再帰呼び出し + イテレーション管理 |

## 影響範囲

### 変更対象ファイル

1. **scripts/improve.sh** - 完全書き換え
2. **test/improve_test.sh** - テスト更新
3. **lib/github.sh** - `get_issues_created_after` は不要だが、他で使用されている可能性があるため残す

### 削除する機能

- `review_and_create_issues()` 関数
- GitHub API呼び出し（get_issues_created_after）の使用
- マーカー抽出関連コード
- 複雑なオプション: `--dry-run`, `--review-only`, `--auto-continue` (必要に応じて残す)

### 残すオプション

- `--max-iterations` - 最大イテレーション数
- `--max-issues` - 1回あたりの最大Issue数（piへのプロンプトで使用）
- `--timeout` - セッション完了待ちタイムアウト
- `--iteration` - 内部使用（再帰呼び出し時のイテレーション番号）
- `-h, --help` - ヘルプ表示

## 実装ステップ

### Step 1: improve.shの書き換え

新しいフロー:
```
improve.sh (iteration 1)
    ↓
pi起動 → Issue作成 → run.sh --no-attach で実行開始 → pi終了(TASK_COMPLETE)
    ↓
improve.sh が wait-for-sessions.sh で完了監視
    ↓
完了したら improve.sh (iteration 2) を再帰呼び出し
    ↓
問題なくなるか最大回数まで繰り返し
```

### Step 2: テストの更新

- 新しいオプションのテスト
- GitHub API関連テストの削除
- 再帰呼び出しロジックのテスト

## テスト方針

1. **ユニットテスト**
   - ヘルプ表示
   - オプションパース
   - スクリプト構文チェック

2. **統合テスト（モック使用）**
   - piコマンドのモック実行
   - list.shからのセッション取得
   - wait-for-sessions.shの呼び出し

## リスクと対策

| リスク | 対策 |
|--------|------|
| piのプロンプトが長すぎて失敗 | プロンプトを簡潔に保つ |
| セッション検出の信頼性 | list.shの出力形式に依存するため、安定したパース方法を使用 |
| 再帰呼び出しの無限ループ | --max-iterations でハードリミットを設定 |

## 見積もり

- improve.sh書き換え: 45分
- テスト更新: 30分
- ドキュメント更新: 15分
- **合計: 1.5時間**
