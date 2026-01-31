# Git Worktree管理

## 概要

Git worktreeを使用して、各Issue用の独立した作業ディレクトリを管理します。これにより、複数のタスクを並列で実行しながら、それぞれが独立したファイルシステム状態を持つことができます。

## Git Worktreeとは

Git worktreeは、1つのGitリポジトリから複数の作業ディレクトリを作成できる機能です。各worktreeは独立したブランチをチェックアウトでき、相互に干渉しません。

### 従来の方法との比較

| 方法 | メリット | デメリット |
|------|---------|-----------|
| **ブランチ切り替え** | シンプル | 切り替え時にファイル変更、並列実行不可 |
| **複数クローン** | 完全に独立 | ディスク容量を大量消費、.gitが重複 |
| **Git Worktree** | 独立 + 効率的 | 若干の学習コスト |

## Worktree作成フロー

```
1. Issue番号とタイトルを取得
   ↓
2. ブランチ名を生成（issue-{番号}-{sanitized-title}）
   ↓
3. ベースブランチを確認（デフォルト: HEAD）
   ↓
4. Worktreeを作成
   git worktree add {path} -b feature/{branch} {base}
   ↓
5. 設定ファイルをコピー
   - .env, .env.local, .envrc
   ↓
6. Worktreeパスを返す
```

## lib/worktree.sh API

### Worktree作成

```bash
# ブランチ名とベースブランチを指定して作成
worktree_path="$(create_worktree "issue-42-add-feature" "main")"
# → ".worktrees/issue-42-add-feature"

# HEADをベースに作成（デフォルト）
worktree_path="$(create_worktree "issue-42-add-feature")"
```

**実装**:

```bash
create_worktree() {
    local branch_name="$1"
    local base_branch="${2:-HEAD}"
    local worktree_dir
    
    load_config
    worktree_dir="$(get_config worktree_base_dir)/$branch_name"
    
    # 既存のworktreeチェック
    if [[ -d "$worktree_dir" ]]; then
        log_error "Worktree already exists: $worktree_dir"
        return 1
    fi
    
    # ベースディレクトリ作成
    mkdir -p "$(get_config worktree_base_dir)"
    
    # worktree作成
    log_info "Creating worktree: $worktree_dir (branch: feature/$branch_name)"
    
    if git rev-parse --verify "feature/$branch_name" &> /dev/null; then
        # ブランチが既に存在する場合
        git worktree add "$worktree_dir" "feature/$branch_name" >&2
    else
        # 新規ブランチ作成
        git worktree add -b "feature/$branch_name" "$worktree_dir" "$base_branch" >&2
    fi
    
    # ファイルのコピー
    copy_files_to_worktree "$worktree_dir"
    
    echo "$worktree_dir"
}
```

### ファイルコピー

環境設定ファイルをworktreeにコピー:

```bash
copy_files_to_worktree "$worktree_path"
```

**設定** (`.pi-runner.yaml`):
```yaml
worktree:
  copy_files:
    - ".env"
    - ".env.local"
    - ".envrc"
```

**実装**:

```bash
copy_files_to_worktree() {
    local worktree_dir="$1"
    local files
    
    load_config
    files="$(get_config worktree_copy_files)"
    
    for file in $files; do
        if [[ -f "$file" ]]; then
            log_debug "Copying $file to worktree"
            cp "$file" "$worktree_dir/"
        fi
    done
}
```

### Worktree削除

```bash
# 通常削除
remove_worktree ".worktrees/issue-42-add-feature"

# 強制削除（未コミットの変更があっても削除）
remove_worktree ".worktrees/issue-42-add-feature" true
```

**実装**:

```bash
remove_worktree() {
    local worktree_path="$1"
    local force="${2:-false}"
    
    if [[ ! -d "$worktree_path" ]]; then
        log_error "Worktree not found: $worktree_path"
        return 1
    fi
    
    log_info "Removing worktree: $worktree_path"
    
    if [[ "$force" == "true" ]]; then
        git worktree remove --force "$worktree_path"
    else
        git worktree remove "$worktree_path"
    fi
}
```

### Worktree一覧

```bash
list_worktrees
# 出力:
# .worktrees/issue-42-add-feature
# .worktrees/issue-43-fix-bug
```

**実装**:

```bash
list_worktrees() {
    load_config
    local base_dir
    base_dir="$(get_config worktree_base_dir)"
    
    while read -r line; do
        if [[ "$line" =~ ^worktree ]]; then
            local path="${line#worktree }"
            if [[ "$path" == *"$base_dir"* ]]; then
                echo "$path"
            fi
        fi
    done < <(git worktree list --porcelain)
}
```

### Worktreeのブランチ取得

```bash
branch="$(get_worktree_branch ".worktrees/issue-42-add-feature")"
# → "feature/issue-42-add-feature"
```

### Issue番号からWorktree検索

```bash
worktree="$(find_worktree_by_issue 42)"
# → ".worktrees/issue-42-add-feature"
```

**実装**:

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

## ブランチ命名規則

### 自動生成

`lib/github.sh` の `issue_to_branch_name()` で生成:

```bash
# Issue #42: "Add new feature for users"
branch_name="$(issue_to_branch_name 42)"
# → "issue-42-add-new-feature-for-users"
```

**命名ルール**:
- プレフィックス: `feature/`
- フォーマット: `issue-{番号}-{sanitized-title}`
- タイトルは小文字化、特殊文字はハイフンに置換
- 最大長制限あり

### カスタムブランチ名

`run.sh` の `--branch` オプションで指定:

```bash
./scripts/run.sh 42 --branch custom-feature-name
```

## ディレクトリ構造

```
project-root/
├── .git/                           # メインのGitディレクトリ
├── .worktrees/                     # Worktree作業ディレクトリ
│   ├── .status/                    # ステータスファイル
│   │   ├── 42.json
│   │   └── 43.json
│   ├── issue-42-add-feature/       # Issue #42のworktree
│   │   ├── .git                    # Gitリンク（親の.git/worktrees/へ）
│   │   ├── .env                    # コピーされた設定ファイル
│   │   ├── .pi-prompt.md           # 生成されたプロンプト
│   │   ├── src/
│   │   └── package.json
│   └── issue-43-fix-bug/           # Issue #43のworktree
│       └── ...
├── src/                            # メインリポジトリのソース
├── package.json
└── .pi-runner.yaml
```

## エッジケース処理

### Worktreeが既に存在する場合

`run.sh` での処理:

```bash
if existing_worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
    if [[ "$force" == "true" ]]; then
        log_info "Removing existing worktree: $existing_worktree"
        remove_worktree "$existing_worktree" true || true
    else
        log_error "Worktree already exists: $existing_worktree"
        log_info "Options:"
        log_info "  --force     Remove and recreate worktree"
        exit 1
    fi
fi
```

### ブランチが既に存在する場合

`create_worktree()` で自動処理:

```bash
if git rev-parse --verify "feature/$branch_name" &> /dev/null; then
    # 既存ブランチをチェックアウト
    git worktree add "$worktree_dir" "feature/$branch_name" >&2
else
    # 新規ブランチ作成
    git worktree add -b "feature/$branch_name" "$worktree_dir" "$base_branch" >&2
fi
```

### エラー時のクリーンアップ

`run.sh` でのトラップ設定:

```bash
# エラー時のクリーンアップを設定
setup_cleanup_trap cleanup_worktree_on_error

# worktreeを登録（エラー時に削除される）
register_worktree_for_cleanup "$full_worktree_path"

# 成功時はトラップ解除
unregister_worktree_for_cleanup
```

## 設定

### .pi-runner.yaml

```yaml
worktree:
  base_dir: ".worktrees"      # worktree作成先ディレクトリ
  copy_files:                 # worktreeにコピーするファイル
    - ".env"
    - ".env.local"
    - ".envrc"
```

### 環境変数

```bash
PI_RUNNER_WORKTREE_BASE_DIR=".worktrees"
PI_RUNNER_WORKTREE_COPY_FILES=".env .env.local .envrc"
```

## Gitコマンドリファレンス

### よく使うコマンド

```bash
# Worktree一覧
git worktree list

# Worktree作成（新規ブランチ）
git worktree add .worktrees/issue-42 -b feature/issue-42 main

# Worktree作成（既存ブランチ）
git worktree add .worktrees/issue-42 feature/issue-42

# Worktree削除
git worktree remove .worktrees/issue-42

# 強制削除
git worktree remove --force .worktrees/issue-42

# 孤立したworktree情報を修復
git worktree repair
```

### Worktree一覧の詳細表示

```bash
git worktree list --porcelain
# 出力:
# worktree /path/to/repo
# HEAD abc1234
# branch refs/heads/main
#
# worktree /path/to/.worktrees/issue-42
# HEAD def5678
# branch refs/heads/feature/issue-42
```

## トラブルシューティング

### 問題: "worktree already locked"

**原因**: 前回の操作が不完全に終了

**解決**:
```bash
rm -f .git/worktrees/issue-42/locked
git worktree repair
```

### 問題: Worktreeが削除できない

**原因**: ファイルが使用中（tmuxセッション等）

**解決**:
```bash
# Tmuxセッションを先に終了
./scripts/stop.sh 42

# 強制削除
git worktree remove --force .worktrees/issue-42-*
```

### 問題: ブランチの追跡が壊れている

**原因**: リモートブランチとの同期が失われた

**解決**:
```bash
cd .worktrees/issue-42-*
git branch --set-upstream-to=origin/feature/issue-42
```

### 問題: 孤立したWorktreeがある

**検出と削除**:
```bash
# 孤立したworktreeを検出
./scripts/cleanup.sh --orphaned --dry-run

# 削除
./scripts/cleanup.sh --orphaned
```

## セキュリティ考慮事項

### 機密ファイルの取り扱い

- `.env` ファイルはログに記録しない
- クリーンアップ時に確実に削除

### ファイル権限

- Worktreeは親リポジトリと同じ権限
- コピーされたファイルは元のパーミッションを維持

## ベストプラクティス

1. **定期的なクリーンアップ**
   - 完了したタスクのworktreeは速やかに削除
   - `cleanup.sh --all --completed` で一括削除

2. **ディスク容量の監視**
   - worktreeはディスク容量を消費
   - 定期的に `du -sh .worktrees/` でチェック

3. **並列作成の制限**
   - 一度に大量のworktreeを作成しない
   - `parallel_max_concurrent` で制限

4. **ブランチ名の一貫性**
   - 自動生成のブランチ名を使用
   - カスタム名は特別な理由がある場合のみ

5. **エラー時のリカバリー**
   - `--force` オプションで既存リソースを削除して再作成
   - `git worktree repair` で整合性を修復
