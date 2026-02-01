# Issue #380 実装計画

## 概要

`lib/worktree.sh` の `find_worktree_by_issue` 関数において、コメントと実装に不一致があります。
コメントは「issue-XXX-* パターンで検索」としていますが、実際のパターン変数は `issue-${issue_number}` （末尾のハイフンなし）となっています。

## 問題の詳細

### 該当コード（lib/worktree.sh:137付近）

```bash
find_worktree_by_issue() {
    local issue_number="$1"
    
    load_config
    local base_dir
    base_dir="$(get_config worktree_base_dir)"
    
    # issue-XXX-* パターンで検索
    local pattern="issue-${issue_number}"
    
    for dir in "$base_dir"/*; do
        if [[ -d "$dir" && "$(basename "$dir")" == $pattern* ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    return 1
}
```

### 問題点

1. **コメントと実装の違い**
   - コメント: "issue-XXX-* パターンで検索"
   - 実際のパターン: `issue-${issue_number}`（末尾のハイフンなし）
   - 実際には `== $pattern*` で先頭一致を確認している

2. **一貫性の欠如**
   - コメントは "issue-XXX-*" とあるが、実際には `issue-${issue_number}`（タイトル部分なし）で検索

## 影響範囲

- `lib/worktree.sh` - コメントの修正のみ
- テストケース - 確認・追加が必要

## 実装ステップ

### 1. コメントの修正

実装が正しいため、コメントを実装に合わせます：

```bash
# issue-{number}* パターンで検索（ブランチ名にタイトルが含まれる場合に対応）
```

### 2. テストの確認

既存のテスト `test/lib/worktree.bats` を確認し、必要に応じてテストケースを追加：

- `issue-123` 形式のディレクトリが見つかること
- `issue-123-title` 形式のディレクトリも見つかること
- 存在しないIssue番号では見つからないこと

## テスト方針

1. **単体テスト**
   - `find_worktree_by_issue` 関数の各ケースをテスト
   - モックを使用してディレクトリ構造をシミュレート

2. **手動テスト**
   - 実際のworktree作成・検索フローを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| コメント修正のみだが、実装の意図を誤解している可能性 | テストケースで各パターンを検証 |
| 他の箇所で同様の不一致がある可能性 | コード全体を簡易レビュー |

## 修正案の選定

**案1: コメントを実装に合わせる（採用）**

理由:
- 現在の実装は `issue-123` および `issue-123-title` の両方に対応可能
- 実装を変更すると後方互換性に影響する可能性がある
- コメントを修正するだけで問題は解決する

## 受け入れ条件

- [ ] コメントが実装に合わせて修正されている
- [ ] 全てのテストがパスしている
- [ ] コードがコミットされている
