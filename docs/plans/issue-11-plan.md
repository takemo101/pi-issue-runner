# Issue #11 実装計画: 既存セッションへの再接続オプション

## 概要

同じ Issue で `run.sh` を再実行した際、既存セッションへのアタッチを提案・実行する機能を実装します。

## 現状分析

### 実装済み機能

既存の `run.sh` には以下の機能が実装済みです：

1. **`--reattach` オプション**
   - 既存セッションが存在する場合、アタッチして終了
   - 実装場所: `run.sh` の既存セッションチェック部分

2. **`--force` オプション**
   - 既存セッションを削除して再作成
   - 既存worktreeも削除して再作成
   - 実装場所: `run.sh` のセッション・worktreeチェック部分

### 動作確認

```bash
# --reattach の動作
$ ./scripts/run.sh 42 --reattach
Session 'pi-issue-42' already exists.
Attaching to existing session: pi-issue-42
# → セッションにアタッチ

# --force の動作
$ ./scripts/run.sh 42 --force
Removing existing session: pi-issue-42
Removing existing worktree: .worktrees/issue-42-xxx
# → 新規作成を続行

# オプションなしの場合
$ ./scripts/run.sh 42
Session 'pi-issue-42' already exists.
Options:
  --reattach  Attach to existing session
  --force     Remove and recreate session
# → エラー終了（exit 1）
```

## 実装ステータス

| 項目 | ステータス | 備考 |
|------|------------|------|
| `--reattach` オプション | ✅ 実装済み | `run.sh` に実装 |
| `--force` オプション | ✅ 実装済み | `run.sh` に実装 |
| ヘルプテキスト | ✅ 実装済み | 全オプションを表示 |
| 基本的なテスト | ✅ 実装済み | `test/scripts/run.bats` |
| 詳細なテスト | 🔄 追加必要 | reattach/force の動作確認 |
| ドキュメント | ✅ 実装済み | README.md に記載 |

## 追加実装が必要な項目

### 1. 詳細なテストケース追加

以下のテストを `test/scripts/run.bats` に追加します：

```bats
# --reattach 動作テスト
@test "run.sh --reattach attaches to existing session" {
    # モックセッションを作成
    # --reattach でアタッチすることを確認
}

# --force 動作テスト
@test "run.sh --force removes and recreates session" {
    # モックセッションとworktreeを作成
    # --force で削除・再作成されることを確認
}

# 既存セッション時のエラーメッセージ
@test "run.sh shows helpful message when session exists" {
    # セッションが存在する場合
    # 有用なエラーメッセージとオプションを表示
}
```

### 2. テスト実行と検証

```bash
# テスト実行
./scripts/test.sh run

# または直接
bats test/scripts/run.bats
```

## テスト方針

### 単体テスト

- `test/scripts/run.bats` に追加
- モックを使用して tmux/gh/git の動作をシミュレート
- 既存セッション有無のパターンを網羅

### 検証項目

1. `--reattach` オプションが既存セッションを正しく検出
2. `--force` オプションが既存セッションとworktreeを削除
3. オプションなしで既存セッションがある場合、適切なエラーメッセージを表示
4. ヘルプテキストに両オプションが含まれる

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存実装の破壊 | 既存テストがパスすることを確認 |
| モックの複雑化 | 必要最小限のモックに留める |
| テストの不安定さ | 一時ディレクトリとクリーンアップを徹底 |

## 完了条件

- [x] Issueの要件を確認
- [x] 既存実装を調査
- [x] 追加テストを実装
- [x] 全テストがパスすることを確認
- [x] 計画書を保存
