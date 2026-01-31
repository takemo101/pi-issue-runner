# Issue #115 実装計画

## 概要

`lib/worktree.sh` の `get_worktree_branch()` と `list_worktrees()` 関数でパイプラインと `while read` を使用しており、サブシェル内で変数を設定した場合に外部に出ない問題を修正する。

## 問題の詳細

### 1. `get_worktree_branch()` の問題

```bash
git worktree list --porcelain | while read -r line; do
    if [[ "$line" == "worktree $worktree_path" ]]; then
        while read -r subline; do
            if [[ "$subline" =~ ^branch ]]; then
                echo "${subline#branch refs/heads/}"
                return  # ← サブシェル内のreturnは関数を終了しない
            fi
            ...
        done
    fi
done
```

- `return` がサブシェル内で実行されるため、関数全体を終了しない
- 将来的に変数を設定して使用する際に問題になる

### 2. `list_worktrees()` の問題

```bash
git worktree list --porcelain | while read -r line; do
    ...
done
```

- 現時点では `echo` で出力しているため動作するが、パターンとして一貫性がない

## 影響範囲

- `lib/worktree.sh`
  - `get_worktree_branch()` 関数
  - `list_worktrees()` 関数
- `test/worktree_test.sh` - テスト追加

## 実装ステップ

1. `get_worktree_branch()` をプロセス置換パターンに修正
2. `list_worktrees()` をプロセス置換パターンに修正
3. サブシェル問題を検証するテストを追加
4. 既存テストを実行して動作確認

## 修正パターン

### Before (問題あり)
```bash
command | while read -r line; do
    result="$line"
done
echo "$result"  # 空になる
```

### After (修正後)
```bash
while read -r line; do
    result="$line"
done < <(command)
echo "$result"  # 正しく出力される
```

## テスト方針

1. `get_worktree_branch()` が正しくブランチ名を返すことを確認
2. 実際のworktreeを作成してブランチ名を取得するテスト
3. 存在しないworktreeに対するテスト

## リスクと対策

| リスク | 対策 |
|--------|------|
| プロセス置換の互換性 | Bash 4.0以上を前提としているため問題なし |
| 既存テストの失敗 | 修正後に全テストを実行して確認 |
