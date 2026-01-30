# アーキテクチャ設計

## システム構成

```
┌─────────────────────────────────────────────────────────────┐
│                        CLI Interface                         │
│  (run, list, status, logs, attach, stop, cleanup)           │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                     Command Handlers                         │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐ │
│  │   Run    │   List   │  Status  │   Logs   │  Cleanup  │ │
│  └─────┬────┴─────┬────┴─────┬────┴─────┬────┴─────┬─────┘ │
└────────┼──────────┼──────────┼──────────┼──────────┼───────┘
         │          │          │          │          │
┌────────▼──────────▼──────────▼──────────▼──────────▼───────┐
│                       Core Services                          │
│  ┌────────────────┬──────────────────┬───────────────────┐  │
│  │ Task Manager   │ Worktree Manager │   Tmux Manager    │  │
│  │                │                  │                   │  │
│  │ - 状態管理     │ - worktree作成   │ - セッション作成  │  │
│  │ - タスクキュー │ - ファイルコピー │ - セッション監視  │  │
│  │ - ログ記録     │ - クリーンアップ │ - コマンド実行    │  │
│  └────────────────┴──────────────────┴───────────────────┘  │
│  ┌────────────────┬──────────────────────────────────────┐  │
│  │ GitHub Client  │        Config Manager                │  │
│  │                │                                      │  │
│  │ - Issue取得    │ - 設定ファイル読み込み               │  │
│  │ - API連携      │ - デフォルト値管理                   │  │
│  └────────────────┴──────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
         │                    │                    │
┌────────▼────────┐  ┌────────▼────────┐  ┌───────▼──────┐
│   Git Worktree  │  │  Tmux Sessions  │  │  Pi Process  │
│                 │  │                 │  │              │
│ .worktrees/     │  │ pi-issue-42     │  │ pi running   │
│   issue-42/     │  │ pi-issue-43     │  │              │
│   issue-43/     │  │ pi-issue-44     │  │              │
└─────────────────┘  └─────────────────┘  └──────────────┘
```

## レイヤー構成

### 1. CLI Layer (Presentation)

**責務**: ユーザーインターフェース、コマンドパース、引数検証

**コンポーネント**:
- `cli.ts` - メインエントリーポイント
- `commands/*.ts` - 各コマンドの実装

**技術スタック**: Bun CLI API、Commander.js風の引数パース

### 2. Command Handler Layer

**責務**: ビジネスロジックの調整、複数のサービスの連携

**コンポーネント**:
- `commands/run.ts` - タスク実行のオーケストレーション
- `commands/status.ts` - 状態取得と表示
- `commands/logs.ts` - ログ取得と表示
- `commands/cleanup.ts` - リソース解放の調整

### 3. Core Service Layer

**責務**: コアビジネスロジック、状態管理、外部リソース管理

#### TaskManager

```typescript
class TaskManager {
  // タスク作成
  createTask(issueNumber: number, options?: TaskOptions): Promise<Task>
  
  // タスク取得
  getTask(taskId: string): Promise<Task | null>
  listTasks(filter?: TaskFilter): Promise<Task[]>
  
  // タスク状態更新
  updateTaskStatus(taskId: string, status: TaskStatus): Promise<void>
  
  // タスク削除
  removeTask(taskId: string): Promise<void>
  
  // 並列実行制御
  canStartNewTask(): boolean
  getRunningTaskCount(): number
}
```

#### WorktreeManager

```typescript
class WorktreeManager {
  // Worktree作成
  createWorktree(
    issueNumber: number, 
    branch: string, 
    base?: string
  ): Promise<string>
  
  // ファイルコピー
  copyFiles(worktreePath: string, files: string[]): Promise<void>
  
  // Worktree削除
  removeWorktree(worktreePath: string, force?: boolean): Promise<void>
  
  // Worktree一覧
  listWorktrees(): Promise<WorktreeInfo[]>
  
  // Worktree存在確認
  exists(worktreePath: string): Promise<boolean>
}
```

#### TmuxManager

```typescript
class TmuxManager {
  // セッション作成
  createSession(name: string, cwd: string): Promise<void>
  
  // コマンド実行
  executeInSession(
    sessionName: string, 
    command: string
  ): Promise<void>
  
  // セッション状態確認
  isSessionActive(sessionName: string): Promise<boolean>
  
  // セッション終了
  killSession(sessionName: string): Promise<void>
  
  // セッション一覧
  listSessions(): Promise<TmuxSession[]>
  
  // セッション出力キャプチャ
  capturePane(sessionName: string): Promise<string>
}
```

#### GitHubClient

```typescript
class GitHubClient {
  // Issue取得
  getIssue(issueNumber: number): Promise<GitHubIssue>
  
  // Issue一覧
  listIssues(filter?: IssueFilter): Promise<GitHubIssue[]>
  
  // PR作成（将来実装）
  createPR(options: PROptions): Promise<string>
}
```

#### ConfigManager

```typescript
class ConfigManager {
  // 設定読み込み
  load(): Promise<Config>
  
  // デフォルト設定
  getDefaults(): Config
  
  // 設定マージ
  merge(userConfig: Partial<Config>): Config
  
  // 設定検証
  validate(config: Config): ValidationResult
}
```

### 4. Infrastructure Layer

**責務**: 外部システムとの通信、ファイルI/O、プロセス管理

**コンポーネント**:
- Git CLI ラッパー
- GitHub CLI (`gh`) ラッパー
- Tmux CLI ラッパー
- ファイルシステム操作
- プロセス実行（Bun.spawn）

## データフロー

### タスク実行フロー

```
1. ユーザー入力
   pi-run run --issue 42

2. CLI Layer
   - 引数をパース
   - RunCommandを呼び出し

3. RunCommand
   - GitHubClient.getIssue(42) を呼び出し
   - TaskManager.createTask(42) を呼び出し

4. TaskManager
   - タスクIDを生成（pi-issue-42）
   - タスクを "queued" 状態で保存
   - WorktreeManager.createWorktree() を呼び出し

5. WorktreeManager
   - git worktree add .worktrees/issue-42 -b issue-42
   - copyFiles() で .env等をコピー
   - worktreeパスを返す

6. TaskManager
   - タスクを "running" 状態に更新
   - TmuxManager.createSession() を呼び出し

7. TmuxManager
   - tmux new-session -s pi-issue-42 -d -c .worktrees/issue-42
   - executeInSession() でpiコマンドを実行
   - セッション名を返す

8. TaskManager
   - タスク情報を更新（セッション名、開始時刻）
   - バックグラウンドで状態監視を開始

9. 状態監視ループ
   - TmuxManager.isSessionActive() でセッションを確認
   - セッション終了時、終了コードを取得
   - TaskManager.updateTaskStatus() で "completed" または "failed"

10. RunCommand
    - タスク情報を表示
    - オプションに応じてセッションにアタッチ
```

### 並列実行フロー

```
1. ユーザー入力
   pi-run run --issues 42,43,44

2. CLI Layer
   - 複数のIssue番号をパース

3. RunCommand
   - Issue番号ごとにループ
   - TaskManager.canStartNewTask() で起動可能か確認

4. TaskManager
   - 現在のrunning状態のタスク数をチェック
   - maxConcurrent設定と比較
   - trueならタスクを作成、falseならキューに追加

5. タスク実行
   - 各タスクは独立して実行
   - 完了したタスクから順次クリーンアップ（autoCleanup=true時）

6. キュー処理
   - タスク完了時、キューをチェック
   - 次のタスクを起動
```

## 状態管理

### タスク状態の永続化

**保存先**: `.pi-runner/tasks.json`

**形式**:
```json
{
  "tasks": [
    {
      "id": "pi-issue-42",
      "issue": 42,
      "status": "running",
      "branch": "issue-42",
      "worktreePath": ".worktrees/issue-42",
      "tmuxSession": "pi-issue-42",
      "startedAt": "2024-01-30T09:00:00.000Z",
      "completedAt": null,
      "exitCode": null,
      "error": null
    }
  ],
  "version": "1.0.0"
}
```

### 状態遷移

```
          createTask()
              ↓
          [queued]
              ↓
        startTask()
              ↓
         [running]
           ↙    ↘
    success    failure
       ↓          ↓
  [completed] [failed]
       ↓          ↓
    cleanup   cleanup
       ↓          ↓
    removed   removed
```

## エラーハンドリング

### エラー階層

```typescript
// ベースエラー
class PiRunnerError extends Error {
  code: string;
  details?: any;
}

// 具体的なエラー
class WorktreeCreationError extends PiRunnerError {}
class TmuxSessionError extends PiRunnerError {}
class GitHubAPIError extends PiRunnerError {}
class ConfigValidationError extends PiRunnerError {}
```

### エラーリカバリー戦略

| エラー種別 | リカバリー戦略 |
|-----------|--------------|
| Worktree作成失敗 | 既存worktreeを削除して再試行 |
| Tmuxセッション作成失敗 | 既存セッションをkillして再試行 |
| GitHub API失敗 | 指数バックオフでリトライ（最大3回） |
| Pi実行失敗 | タスクを "failed" にマーク、クリーンアップ |
| 設定ファイル不正 | デフォルト設定を使用、警告を表示 |

## ログ管理

### ログレベル

```typescript
enum LogLevel {
  DEBUG = 'debug',   // 詳細なデバッグ情報
  INFO = 'info',     // 一般的な情報
  WARN = 'warn',     // 警告
  ERROR = 'error'    // エラー
}
```

### ログ出力先

1. **標準出力/エラー出力** - リアルタイムフィードバック
2. **タスクログファイル** - `.pi-runner/logs/{task-id}.log`
3. **システムログ** - `.pi-runner/system.log`

### ログフォーマット

```
[2024-01-30 09:00:00] [INFO] [TaskManager] Task pi-issue-42 created
[2024-01-30 09:00:05] [INFO] [WorktreeManager] Worktree created at .worktrees/issue-42
[2024-01-30 09:00:10] [INFO] [TmuxManager] Session pi-issue-42 started
[2024-01-30 09:05:00] [INFO] [TaskManager] Task pi-issue-42 completed (exit code: 0)
```

## セキュリティ考慮事項

### 機密情報の取り扱い

1. **環境変数**: `.env`ファイルはログに記録しない
2. **GitHub Token**: GitHub CLIの認証機構を使用、直接取り扱わない
3. **ログファイル**: 機密情報をフィルタリング（APIキー、パスワード等）

### ファイルアクセス制御

1. **Worktree**: 親リポジトリと同じ権限
2. **ログファイル**: 所有者のみ読み書き可能（600）
3. **設定ファイル**: 所有者のみ読み書き可能（600）

## パフォーマンス最適化

### 並列処理

- タスク起動を非同期実行
- Worktree作成を並列化（Git 2.15+のサポート）
- 状態監視を効率的なポーリングで実施

### リソース管理

- 最大同時実行数の制限（デフォルト: 5）
- ログファイルのローテーション（100MB超で圧縮）
- 古いタスク情報の自動削除（30日以上前の完了タスク）

### キャッシング

- GitHub Issueの情報をキャッシュ（5分間）
- 設定ファイルの読み込みをメモリキャッシュ
- Tmuxセッション一覧の取得結果をキャッシュ（1秒間）

## テスト戦略

### ユニットテスト

- 各Managerクラスの個別機能
- エラーハンドリング
- 設定の読み込みとバリデーション

### 統合テスト

- Worktree作成 → Tmuxセッション作成 → Pi実行
- 並列実行のシナリオ
- エラーリカバリーのシナリオ

### E2Eテスト

- 実際のGitHubリポジトリを使用
- 完全なタスクライフサイクル
- クリーンアップの動作確認

## モニタリング

### メトリクス

- タスク成功率
- 平均実行時間
- 並列実行数
- リソース使用量（CPU、メモリ）

### ヘルスチェック

- Worktreeの整合性チェック
- 孤立したTmuxセッションの検出
- ディスク容量の監視
