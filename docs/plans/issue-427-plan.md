# Issue #427 Implementation Plan

## 概要

worktree内にuntracked filesが存在する場合、`cleanup.sh` が削除に失敗するが、成功と誤認してしまう問題を修正する。

## Issue分析

### 問題の詳細
1. `git worktree remove` がuntracked filesの存在で失敗（exit code: 128）
2. 失敗後、`git worktree list` でworktreeが見つからない（gitの管理からは外れている）
3. 関数が「Worktree already removed」と誤検知して成功を返す
4. 実際にはディレクトリとuntracked filesが残存している

### 根本原因
`lib/worktree.sh` の `remove_worktree` 関数が、git worktree listでの存在確認のみを行い、
実際のディレクトリの存在確認を行っていない。

## 影響範囲

- `lib/worktree.sh` - `remove_worktree` 関数の修正
- 必要に応じて `scripts/cleanup.sh` - デフォルトで `--force` を使用する変更

## 実装ステップ

### Step 1: lib/worktree.sh の修正

#### 修正点1: 実際のディレクトリ存在確認を追加
`remove_worktree` 関数で、git worktree listでの確認に加えて、
実際のディレクトリ存在確認も行うようにする。

```bash
# 失敗後の確認ロジックを修正
if [[ "$worktree_still_exists" == "true" ]] || [[ -d "$worktree_path" ]]; then
    # まだ存在する場合はリトライまたは失敗
else
    # 削除済みと判断
fi
```

#### 修正点2: force=false時のエラーハンドリング強化
untracked filesがある場合、より明確なエラーメッセージを表示し、
`--force` オプションの使用を推奨する。

### Step 2: cleanup.sh の検討（オプション）

`watch-session.sh` から呼び出される場合、デフォルトで `--force` を使用するか検討。
ただし、現状のままでも `remove_worktree` の修正で正しくエラー検出されるようになる。

### Step 3: テストの追加/更新

既存のテスト `test/lib/worktree.bats` に以下を追加:
- untracked filesがある場合のforce=falseでの失敗テスト
- untracked filesがある場合のforce=trueでの成功テスト

## テスト方針

1. **単体テスト**: Batsテストで以下を検証
   - `remove_worktree path false` がuntracked filesで失敗すること
   - `remove_worktree path true` がuntracked filesでも成功すること
   - エラーメッセージが適切であること

2. **手動テスト**:
   ```bash
   # worktree作成
   ./scripts/run.sh 999 --no-attach
   # untracked file作成
   echo "test" > .worktrees/issue-999-test/untracked.txt
   # cleanup実行（forceなし）
   ./scripts/cleanup.sh 999
   # 正しくエラーになることを確認
   ```

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存の正常系に影響 | force=false時のみ挙動変更。force=true時は既存通り |
| 誤検知で削除失敗を報告 | ディレクトリ存在確認を追加することで精度向上 |
| CIでの挙動変更 | テストを追加して検証 |

## 実装後の期待動作

### 修正前（問題）
```
fatal: '...' contains modified or untracked files, use --force to delete it
[WARN] Worktree removal failed on attempt 1 (exit code: 128)
[INFO] Worktree already removed  ← 誤検知
[INFO] Worktree removed successfully  ← 嘘
# 実際にはworktreeが残存
```

### 修正後（期待）
```
fatal: '...' contains modified or untracked files, use --force to delete it
[WARN] Worktree removal failed on attempt 1 (exit code: 128)
[ERROR] Failed to remove worktree after 3 attempts: ...
[ERROR] You may need to manually run: git worktree remove --force '...'
# または --force 使用時は成功
```

## 完了条件

- [ ] `lib/worktree.sh` の `remove_worktree` 関数を修正
- [ ] テストを追加/更新
- [ ] 全てのテストがパス
- [ ] コミット作成
