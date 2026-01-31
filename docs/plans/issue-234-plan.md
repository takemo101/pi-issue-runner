# Issue #234 実装計画

## 概要

`improve.sh` を2段階方式に変更し、piの出力をログファイルに保存する機能を追加する。

## 現状分析

### 現在の問題点
- piがプロンプトの指示通りに動作するか保証されない
- piがIssue作成やrun.sh実行をせずにマーカーを出力する場合がある
- piの出力が保存されないのでデバッグが困難

### 現在の実装
- tmuxセッション内でpiを実行し、マーカー検知で完了判定
- piにrun.shの実行を任せている
- ログ保存機能なし

## 影響範囲

### 変更ファイル
1. `scripts/improve.sh` - メインの変更対象
2. `.gitignore` - `.improve-logs/` を追加

### 依存する既存ファイル（変更なし）
- `lib/github.sh` - `get_issues_created_after()` 関数が既に存在
- `scripts/run.sh` - そのまま使用
- `scripts/wait-for-sessions.sh` - そのまま使用

## 実装ステップ

### Step 1: improve.sh の書き換え

新しいフロー:
1. **Phase 1**: `pi --print` でレビュー＆Issue作成（自動終了）
   - 出力をログファイルに保存（`tee`コマンド使用）
2. **Phase 2**: GitHub APIでIssue取得（`get_issues_created_after`）
3. **Phase 3**: `run.sh --no-attach` で並列実行
4. **Phase 4**: `wait-for-sessions.sh` で完了監視
5. **Phase 5**: 再帰呼び出し

### Step 2: .gitignore に追加

`.improve-logs/` ディレクトリを追加

## テスト方針

### 手動テスト
```bash
# ログ保存テスト
./scripts/improve.sh --max-iterations 1 --max-issues 1

# ログディレクトリ確認
ls -la .improve-logs/

# ログ内容確認
cat .improve-logs/iteration-*.log
```

### ユニットテスト
既存のテストへの影響は最小限（新しいオプションのテスト追加は任意）

## リスクと対策

| リスク | 対策 |
|--------|------|
| `pi --print` が期待通り動作しない | エラーハンドリングを追加し、ログファイルで確認可能に |
| ログファイルが肥大化 | ユーザーが手動でクリーンアップ |
| GitHub APIレート制限 | 既存の `get_issues_created_after` の実装を使用 |

## 見積もり

- 実装: 30分
- テスト: 15分
- **合計: 45分**
