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
1. Issue番号を受け取る
   ↓
2. ブランチ名を生成（issue-{番号}）
   ↓
3. ベースブランチを確認（デフォルト: main）
   ↓
4. Worktreeを作成
   git worktree add {path} -b {branch} {base}
   ↓
5. 必要なファイルをコピー
   - .env
   - .env.local
   - その他設定ファイル
   ↓
6. Worktreeパスを返す
```

## コマンド詳細

### Worktree作成

```bash
# 基本的な作成
git worktree add .worktrees/issue-42 -b issue-42

# ベースブランチを指定
git worktree add .worktrees/issue-42 -b issue-42 origin/develop

# 既存ブランチをチェックアウト
git worktree add .worktrees/issue-42 issue-42
```

**実装**:
```typescript
async createWorktree(
  issueNumber: number,
  branch: string,
  base: string = 'main'
): Promise<string> {
  const worktreePath = path.join(
    this.config.worktree.baseDir,
    `issue-${issueNumber}`
  );

  // Worktreeが既に存在するか確認
  if (await this.exists(worktreePath)) {
    throw new WorktreeExistsError(`Worktree already exists: ${worktreePath}`);
  }

  // Worktreeを作成
  await this.exec(
    `git worktree add ${worktreePath} -b ${branch} ${base}`
  );

  // 必要なファイルをコピー
  await this.copyFiles(worktreePath, this.config.worktree.copyFiles);

  return worktreePath;
}
```

### ファイルコピー

設定ファイルで指定されたファイルをメインリポジトリからworktreeにコピーします。

**設定例**:
```yaml
worktree:
  copy_files:
    - ".env"
    - ".env.local"
    - "config/local.json"
```

**実装**:
```typescript
async copyFiles(worktreePath: string, files: string[]): Promise<void> {
  const repoRoot = await this.getRepoRoot();

  for (const file of files) {
    const src = path.join(repoRoot, file);
    const dest = path.join(worktreePath, file);

    // ファイルが存在するか確認
    if (!await Bun.file(src).exists()) {
      this.logger.warn(`File not found, skipping: ${src}`);
      continue;
    }

    // ディレクトリを作成
    await Bun.write(dest, await Bun.file(src).arrayBuffer());
    
    this.logger.info(`Copied ${file} to ${worktreePath}`);
  }
}
```

### Worktree削除

```bash
# 通常の削除
git worktree remove .worktrees/issue-42

# 強制削除（変更がある場合）
git worktree remove --force .worktrees/issue-42
```

**実装**:
```typescript
async removeWorktree(
  worktreePath: string,
  force: boolean = false
): Promise<void> {
  // Worktreeが存在するか確認
  if (!await this.exists(worktreePath)) {
    this.logger.warn(`Worktree not found: ${worktreePath}`);
    return;
  }

  // 削除コマンドを実行
  const forceFlag = force ? '--force' : '';
  await this.exec(`git worktree remove ${forceFlag} ${worktreePath}`);

  this.logger.info(`Removed worktree: ${worktreePath}`);
}
```

### Worktree一覧取得

```bash
# Worktree一覧を表示
git worktree list
```

**出力例**:
```
/path/to/repo              abc123 [main]
/path/to/.worktrees/issue-42  def456 [issue-42]
/path/to/.worktrees/issue-43  ghi789 [issue-43]
```

**実装**:
```typescript
interface WorktreeInfo {
  path: string;
  branch: string;
  commit: string;
}

async listWorktrees(): Promise<WorktreeInfo[]> {
  const output = await this.exec('git worktree list --porcelain');
  
  // 出力をパース
  const worktrees: WorktreeInfo[] = [];
  const lines = output.split('\n');
  
  let current: Partial<WorktreeInfo> = {};
  
  for (const line of lines) {
    if (line.startsWith('worktree ')) {
      current.path = line.substring(9);
    } else if (line.startsWith('branch ')) {
      current.branch = line.substring(7);
    } else if (line.startsWith('HEAD ')) {
      current.commit = line.substring(5);
    } else if (line === '') {
      if (current.path) {
        worktrees.push(current as WorktreeInfo);
      }
      current = {};
    }
  }
  
  return worktrees;
}
```

## エッジケース処理

### 1. Worktreeが既に存在する場合

**シナリオ**: 同じIssue番号で複数回実行

**対処**:
```typescript
if (await this.exists(worktreePath)) {
  // オプション1: エラーを投げる（デフォルト）
  throw new WorktreeExistsError();
  
  // オプション2: 既存を削除して再作成（--force フラグ時）
  if (options.force) {
    await this.removeWorktree(worktreePath, true);
    // 作成処理を続行
  }
}
```

### 2. ブランチが既に存在する場合

**シナリオ**: 以前作成したブランチが残っている

**対処**:
```typescript
try {
  await this.exec(`git worktree add ${path} -b ${branch} ${base}`);
} catch (error) {
  if (error.message.includes('already exists')) {
    // 既存ブランチをチェックアウト
    await this.exec(`git worktree add ${path} ${branch}`);
  } else {
    throw error;
  }
}
```

### 3. ディスク容量不足

**対処**:
```typescript
async createWorktree(...): Promise<string> {
  // 利用可能なディスク容量を確認
  const available = await this.getAvailableDiskSpace();
  const required = await this.estimateWorktreeSize();
  
  if (available < required * 1.2) { // 20%のバッファ
    throw new InsufficientDiskSpaceError();
  }
  
  // Worktree作成処理
}
```

### 4. 孤立したWorktree

**シナリオ**: プロセスクラッシュ等で削除されなかったworktree

**検出**:
```typescript
async findOrphanedWorktrees(): Promise<string[]> {
  const worktrees = await this.listWorktrees();
  const tasks = await this.taskManager.listTasks();
  
  const orphaned: string[] = [];
  
  for (const wt of worktrees) {
    // メインリポジトリはスキップ
    if (!wt.path.includes(this.config.worktree.baseDir)) {
      continue;
    }
    
    // 対応するタスクがあるか確認
    const hasTask = tasks.some(t => t.worktreePath === wt.path);
    
    if (!hasTask) {
      orphaned.push(wt.path);
    }
  }
  
  return orphaned;
}
```

**クリーンアップ**:
```typescript
async cleanupOrphaned(): Promise<void> {
  const orphaned = await this.findOrphanedWorktrees();
  
  for (const path of orphaned) {
    this.logger.warn(`Removing orphaned worktree: ${path}`);
    await this.removeWorktree(path, true);
  }
}
```

## パフォーマンス最適化

### 並列作成

複数のworktreeを並列で作成する場合：

```typescript
async createWorktreesParallel(
  issues: number[]
): Promise<Map<number, string>> {
  const results = new Map<number, string>();
  
  // Promise.allで並列実行
  const promises = issues.map(async (issue) => {
    try {
      const path = await this.createWorktree(
        issue,
        `issue-${issue}`
      );
      results.set(issue, path);
    } catch (error) {
      this.logger.error(`Failed to create worktree for issue ${issue}`, error);
    }
  });
  
  await Promise.all(promises);
  
  return results;
}
```

**注意**: Git 2.15以降では並列worktree作成が安全です。

### シンボリックリンクの活用

大きなファイル（node_modules等）は共有可能：

```typescript
async createWorktree(...): Promise<string> {
  // Worktree作成
  const path = await this.createWorktreeBase(...);
  
  // node_modulesをシンボリックリンク（オプション）
  if (this.config.worktree.symlinkNodeModules) {
    const repoRoot = await this.getRepoRoot();
    const src = path.join(repoRoot, 'node_modules');
    const dest = path.join(path, 'node_modules');
    
    await Bun.spawn(['ln', '-s', src, dest]);
  }
  
  return path;
}
```

## ディレクトリ構造例

```
project-root/
├── .git/                           # メインのGitディレクトリ
├── .worktrees/                     # Worktree作業ディレクトリ
│   ├── issue-42/                   # Issue #42のworktree
│   │   ├── .git                    # Gitリンク（実体は親の.git/worktrees/）
│   │   ├── .env                    # コピーされた設定ファイル
│   │   ├── src/
│   │   ├── package.json
│   │   └── node_modules/           # （オプション）シンボリックリンク
│   └── issue-43/                   # Issue #43のworktree
│       └── ...
├── src/                            # メインリポジトリのソース
├── package.json
└── .pi-runner.yaml
```

## セキュリティ考慮事項

### ファイルコピー時の権限

```typescript
async copyFiles(worktreePath: string, files: string[]): Promise<void> {
  for (const file of files) {
    const src = path.join(repoRoot, file);
    const dest = path.join(worktreePath, file);
    
    // ファイルをコピー
    await Bun.write(dest, await Bun.file(src).arrayBuffer());
    
    // パーミッションを保持
    const stats = await Bun.file(src).stat();
    if (stats) {
      await Bun.spawn(['chmod', stats.mode.toString(8), dest]);
    }
  }
}
```

### 機密ファイルの扱い

- `.env` ファイルはログに記録しない
- コピー時にバックアップを作成しない
- クリーンアップ時に確実に削除

```typescript
async removeWorktree(worktreePath: string, force: boolean = false): Promise<void> {
  // 機密ファイルを先に削除
  const sensitiveFiles = ['.env', '.env.local'];
  for (const file of sensitiveFiles) {
    const filePath = path.join(worktreePath, file);
    try {
      await Bun.spawn(['rm', '-f', filePath]);
    } catch (error) {
      // 既に削除されている場合は無視
    }
  }
  
  // Worktree本体を削除
  await this.exec(`git worktree remove ${force ? '--force' : ''} ${worktreePath}`);
}
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

**原因**: ファイルが使用中

**解決**:
```bash
# Tmuxセッションを先に終了
tmux kill-session -t pi-issue-42

# 強制削除
git worktree remove --force .worktrees/issue-42
```

### 問題: ブランチの追跡が壊れている

**原因**: リモートブランチとの同期が失われた

**解決**:
```bash
cd .worktrees/issue-42
git branch --set-upstream-to=origin/issue-42
```

## ベストプラクティス

1. **定期的なクリーンアップ**: 完了したタスクのworktreeは速やかに削除
2. **ディスク容量の監視**: worktreeはディスク容量を消費するため、定期的にチェック
3. **共有リソースの最小化**: node_modules等はシンボリックリンクで共有
4. **並列作成の制限**: 一度に大量のworktreeを作成しない（最大10個程度）
5. **孤立したworktreeの監視**: 定期的に `findOrphanedWorktrees()` を実行
