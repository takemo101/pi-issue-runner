# 状態管理

## 概要

Pi Issue Runnerの状態管理システムは、タスクの実行状態、設定、ログなどを永続化し、プロセス再起動後も復元できるようにします。

## データ永続化

### ストレージ構造

```
.pi-runner/
├── tasks.json          # タスク状態データベース
├── config.json         # 実行時設定（自動生成）
├── metadata.json       # メタデータ（バージョン、統計等）
└── logs/               # ログファイル
    ├── issue-42.log    # タスクログ
    ├── issue-43.log
    └── system.log      # システムログ
```

### tasks.jsonフォーマット

```json
{
  "version": "1.0.0",
  "lastUpdated": "2024-01-30T09:00:00.000Z",
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
      "error": null,
      "metadata": {
        "retryCount": 0,
        "priority": 0,
        "labels": ["feature"],
        "assignee": "username"
      },
      "logs": {
        "path": ".pi-runner/logs/issue-42.log",
        "size": 12345
      }
    }
  ]
}
```

## TaskManager実装

### データアクセス層

```typescript
class TaskStateStore {
  private filePath: string;
  private cache: TaskDatabase | null = null;
  private dirty = false;
  
  constructor(dataDir: string) {
    this.filePath = path.join(dataDir, 'tasks.json');
  }
  
  async load(): Promise<TaskDatabase> {
    if (this.cache) {
      return this.cache;
    }
    
    try {
      const file = Bun.file(this.filePath);
      if (await file.exists()) {
        const data = await file.json();
        this.cache = this.validate(data);
        return this.cache;
      }
    } catch (error) {
      this.logger.warn('Failed to load tasks.json, using empty database');
    }
    
    // 初期データベース
    this.cache = {
      version: '1.0.0',
      lastUpdated: new Date().toISOString(),
      tasks: []
    };
    
    return this.cache;
  }
  
  async save(): Promise<void> {
    if (!this.dirty || !this.cache) return;
    
    this.cache.lastUpdated = new Date().toISOString();
    
    await Bun.write(
      this.filePath,
      JSON.stringify(this.cache, null, 2)
    );
    
    this.dirty = false;
  }
  
  markDirty(): void {
    this.dirty = true;
  }
  
  private validate(data: any): TaskDatabase {
    // バージョンチェック
    if (data.version !== '1.0.0') {
      throw new InvalidVersionError(`Unsupported version: ${data.version}`);
    }
    
    // データ構造の検証
    if (!Array.isArray(data.tasks)) {
      throw new InvalidDataError('tasks must be an array');
    }
    
    return data as TaskDatabase;
  }
}
```

### TaskManager

```typescript
class TaskManager {
  private store: TaskStateStore;
  private autoSaveInterval: Timer;
  
  constructor(config: Config) {
    this.store = new TaskStateStore(config.dataDir);
    
    // 自動保存（5秒ごと）
    this.autoSaveInterval = setInterval(() => {
      this.store.save();
    }, 5000);
  }
  
  async createTask(issueNumber: number, options?: TaskOptions): Promise<Task> {
    const db = await this.store.load();
    
    // タスクIDを生成
    const taskId = this.generateTaskId(issueNumber);
    
    // 既存タスクをチェック
    if (db.tasks.some(t => t.id === taskId)) {
      throw new TaskExistsError(`Task already exists: ${taskId}`);
    }
    
    // GitHub Issueを取得
    const issue = await this.githubClient.getIssue(issueNumber);
    
    // タスクを作成
    const task: Task = {
      id: taskId,
      issue: issueNumber,
      status: 'queued',
      branch: options?.branch ?? `issue-${issueNumber}`,
      worktreePath: '',
      tmuxSession: taskId,
      startedAt: null,
      completedAt: null,
      exitCode: null,
      error: null,
      metadata: {
        retryCount: 0,
        priority: this.calculatePriority(issue),
        labels: issue.labels,
        assignee: issue.assignee
      },
      logs: {
        path: path.join(this.config.logsDir, `issue-${issueNumber}.log`),
        size: 0
      }
    };
    
    db.tasks.push(task);
    this.store.markDirty();
    
    return task;
  }
  
  async getTask(taskId: string): Promise<Task | null> {
    const db = await this.store.load();
    return db.tasks.find(t => t.id === taskId) ?? null;
  }
  
  async updateTask(task: Task): Promise<void> {
    const db = await this.store.load();
    const index = db.tasks.findIndex(t => t.id === task.id);
    
    if (index === -1) {
      throw new TaskNotFoundError(`Task not found: ${task.id}`);
    }
    
    db.tasks[index] = task;
    this.store.markDirty();
  }
  
  async updateTaskStatus(
    taskId: string,
    status: TaskStatus,
    metadata?: Partial<Task>
  ): Promise<void> {
    const task = await this.getTask(taskId);
    if (!task) {
      throw new TaskNotFoundError(`Task not found: ${taskId}`);
    }
    
    task.status = status;
    
    if (status === 'running' && !task.startedAt) {
      task.startedAt = new Date().toISOString();
    }
    
    if ((status === 'completed' || status === 'failed') && !task.completedAt) {
      task.completedAt = new Date().toISOString();
    }
    
    if (metadata) {
      Object.assign(task, metadata);
    }
    
    await this.updateTask(task);
  }
  
  async listTasks(filter?: TaskFilter): Promise<Task[]> {
    const db = await this.store.load();
    let tasks = db.tasks;
    
    if (filter) {
      if (filter.status) {
        tasks = tasks.filter(t => t.status === filter.status);
      }
      if (filter.issue) {
        tasks = tasks.filter(t => t.issue === filter.issue);
      }
      if (filter.label) {
        tasks = tasks.filter(t => t.metadata.labels.includes(filter.label));
      }
    }
    
    return tasks;
  }
  
  async removeTask(taskId: string): Promise<void> {
    const db = await this.store.load();
    const index = db.tasks.findIndex(t => t.id === taskId);
    
    if (index === -1) {
      throw new TaskNotFoundError(`Task not found: ${taskId}`);
    }
    
    db.tasks.splice(index, 1);
    this.store.markDirty();
    await this.store.save();  // 即座に保存
  }
  
  async shutdown(): Promise<void> {
    clearInterval(this.autoSaveInterval);
    await this.store.save();
  }
}
```

## 状態遷移の管理

### 状態マシン

```typescript
type TaskStatus = 'queued' | 'running' | 'completed' | 'failed';

interface StateTransition {
  from: TaskStatus;
  to: TaskStatus;
  conditions?: (task: Task) => boolean;
  actions?: (task: Task) => Promise<void>;
}

class TaskStateMachine {
  private transitions: StateTransition[] = [
    {
      from: 'queued',
      to: 'running',
      conditions: (task) => this.canStartTask(task),
      actions: async (task) => {
        await this.worktreeManager.createWorktree(task.issue, task.branch);
        await this.tmuxManager.createSession(task.tmuxSession, task.worktreePath);
      }
    },
    {
      from: 'running',
      to: 'completed',
      conditions: (task) => task.exitCode === 0,
      actions: async (task) => {
        await this.notifyCompletion(task);
        if (this.config.autoCleanup) {
          await this.cleanup(task);
        }
      }
    },
    {
      from: 'running',
      to: 'failed',
      conditions: (task) => task.exitCode !== 0,
      actions: async (task) => {
        await this.notifyFailure(task);
        await this.handleFailure(task);
      }
    }
  ];
  
  async transition(
    task: Task,
    to: TaskStatus
  ): Promise<void> {
    const transition = this.transitions.find(
      t => t.from === task.status && t.to === to
    );
    
    if (!transition) {
      throw new InvalidTransitionError(
        `Cannot transition from ${task.status} to ${to}`
      );
    }
    
    // 条件をチェック
    if (transition.conditions && !transition.conditions(task)) {
      throw new TransitionConditionError(
        `Conditions not met for transition from ${task.status} to ${to}`
      );
    }
    
    // アクションを実行
    if (transition.actions) {
      await transition.actions(task);
    }
    
    // 状態を更新
    await this.taskManager.updateTaskStatus(task.id, to);
  }
}
```

### イベント駆動の状態管理

```typescript
enum TaskEvent {
  CREATED = 'task.created',
  STARTED = 'task.started',
  COMPLETED = 'task.completed',
  FAILED = 'task.failed',
  CANCELLED = 'task.cancelled'
}

interface TaskEventPayload {
  taskId: string;
  timestamp: Date;
  data?: any;
}

class TaskEventBus {
  private handlers = new Map<TaskEvent, Set<EventHandler>>();
  
  on(event: TaskEvent, handler: EventHandler): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    this.handlers.get(event)!.add(handler);
  }
  
  off(event: TaskEvent, handler: EventHandler): void {
    this.handlers.get(event)?.delete(handler);
  }
  
  async emit(event: TaskEvent, payload: TaskEventPayload): Promise<void> {
    const handlers = this.handlers.get(event);
    if (!handlers) return;
    
    // イベントをログに記録
    await this.logEvent(event, payload);
    
    // 全ハンドラーを実行
    await Promise.all(
      Array.from(handlers).map(h => h(payload))
    );
  }
  
  private async logEvent(
    event: TaskEvent,
    payload: TaskEventPayload
  ): Promise<void> {
    const logEntry = {
      event,
      ...payload,
      timestamp: new Date().toISOString()
    };
    
    await Bun.write(
      path.join(this.config.dataDir, 'events.jsonl'),
      JSON.stringify(logEntry) + '\n',
      { append: true }
    );
  }
}

// 使用例
eventBus.on(TaskEvent.STARTED, async (payload) => {
  const task = await taskManager.getTask(payload.taskId);
  console.log(`Task ${task?.issue} started at ${payload.timestamp}`);
});

eventBus.on(TaskEvent.COMPLETED, async (payload) => {
  const task = await taskManager.getTask(payload.taskId);
  console.log(`Task ${task?.issue} completed successfully`);
  
  // 次のタスクをキューから起動
  await queueManager.processQueue();
});
```

## トランザクション管理

### アトミック操作

```typescript
class TransactionManager {
  private inProgress = new Map<string, Transaction>();
  
  async begin(transactionId: string): Promise<Transaction> {
    if (this.inProgress.has(transactionId)) {
      throw new TransactionExistsError(`Transaction already in progress: ${transactionId}`);
    }
    
    const transaction: Transaction = {
      id: transactionId,
      operations: [],
      startedAt: new Date(),
      status: 'active'
    };
    
    this.inProgress.set(transactionId, transaction);
    return transaction;
  }
  
  async commit(transactionId: string): Promise<void> {
    const tx = this.inProgress.get(transactionId);
    if (!tx) {
      throw new TransactionNotFoundError(`Transaction not found: ${transactionId}`);
    }
    
    try {
      // 全操作を実行
      for (const op of tx.operations) {
        await op.execute();
      }
      
      tx.status = 'committed';
      this.inProgress.delete(transactionId);
    } catch (error) {
      // ロールバック
      await this.rollback(transactionId);
      throw error;
    }
  }
  
  async rollback(transactionId: string): Promise<void> {
    const tx = this.inProgress.get(transactionId);
    if (!tx) return;
    
    // 逆順でロールバック
    for (let i = tx.operations.length - 1; i >= 0; i--) {
      const op = tx.operations[i];
      if (op.rollback) {
        await op.rollback();
      }
    }
    
    tx.status = 'rolled_back';
    this.inProgress.delete(transactionId);
  }
  
  addOperation(transactionId: string, operation: Operation): void {
    const tx = this.inProgress.get(transactionId);
    if (!tx) {
      throw new TransactionNotFoundError(`Transaction not found: ${transactionId}`);
    }
    
    tx.operations.push(operation);
  }
}

// 使用例
const tx = await transactionManager.begin('create-task-42');

try {
  // Worktree作成
  transactionManager.addOperation(tx.id, {
    execute: async () => {
      task.worktreePath = await worktreeManager.createWorktree(42);
    },
    rollback: async () => {
      await worktreeManager.removeWorktree(task.worktreePath, true);
    }
  });
  
  // Tmuxセッション作成
  transactionManager.addOperation(tx.id, {
    execute: async () => {
      await tmuxManager.createSession(task.tmuxSession, task.worktreePath);
    },
    rollback: async () => {
      await tmuxManager.killSession(task.tmuxSession);
    }
  });
  
  // タスク状態を保存
  transactionManager.addOperation(tx.id, {
    execute: async () => {
      await taskManager.createTask(task);
    },
    rollback: async () => {
      await taskManager.removeTask(task.id);
    }
  });
  
  // コミット
  await transactionManager.commit(tx.id);
} catch (error) {
  // 自動的にロールバック
  console.error('Failed to create task, rolling back...', error);
}
```

## キャッシュ管理

### メモリキャッシュ

```typescript
class TaskCache {
  private cache = new Map<string, CachedTask>();
  private ttl: number = 60000;  // 60秒
  
  set(taskId: string, task: Task): void {
    this.cache.set(taskId, {
      task,
      cachedAt: Date.now()
    });
  }
  
  get(taskId: string): Task | null {
    const cached = this.cache.get(taskId);
    if (!cached) return null;
    
    // TTLチェック
    if (Date.now() - cached.cachedAt > this.ttl) {
      this.cache.delete(taskId);
      return null;
    }
    
    return cached.task;
  }
  
  invalidate(taskId: string): void {
    this.cache.delete(taskId);
  }
  
  clear(): void {
    this.cache.clear();
  }
}

// TaskManagerに統合
class TaskManager {
  private cache = new TaskCache();
  
  async getTask(taskId: string): Promise<Task | null> {
    // キャッシュをチェック
    const cached = this.cache.get(taskId);
    if (cached) {
      return cached;
    }
    
    // ストアから取得
    const db = await this.store.load();
    const task = db.tasks.find(t => t.id === taskId);
    
    if (task) {
      this.cache.set(taskId, task);
    }
    
    return task ?? null;
  }
  
  async updateTask(task: Task): Promise<void> {
    await this.store.updateTask(task);
    
    // キャッシュを無効化
    this.cache.invalidate(task.id);
  }
}
```

## バックアップとリストア

### 自動バックアップ

```typescript
class BackupManager {
  async createBackup(): Promise<string> {
    const timestamp = new Date().toISOString().replace(/:/g, '-');
    const backupPath = path.join(
      this.config.backupDir,
      `backup-${timestamp}.json`
    );
    
    // 現在の状態をバックアップ
    const db = await this.store.load();
    await Bun.write(
      backupPath,
      JSON.stringify(db, null, 2)
    );
    
    this.logger.info(`Created backup: ${backupPath}`);
    return backupPath;
  }
  
  async restore(backupPath: string): Promise<void> {
    // バックアップファイルを読み込み
    const backup = await Bun.file(backupPath).json();
    
    // 検証
    this.store.validate(backup);
    
    // 現在の状態をバックアップ
    await this.createBackup();
    
    // リストア
    await Bun.write(
      this.store.filePath,
      JSON.stringify(backup, null, 2)
    );
    
    // キャッシュをクリア
    this.cache.clear();
    
    this.logger.info(`Restored from backup: ${backupPath}`);
  }
  
  async cleanOldBackups(maxAge: number = 7 * 24 * 60 * 60 * 1000): Promise<void> {
    const backupDir = this.config.backupDir;
    const files = await Array.fromAsync(
      new Bun.Glob('backup-*.json').scan(backupDir)
    );
    
    const now = Date.now();
    
    for (const file of files) {
      const stats = await Bun.file(path.join(backupDir, file)).stat();
      const age = now - stats.mtime.getTime();
      
      if (age > maxAge) {
        await Bun.spawn(['rm', path.join(backupDir, file)]);
        this.logger.info(`Deleted old backup: ${file}`);
      }
    }
  }
}
```

## 復旧処理

### プロセスクラッシュ後の復旧

```typescript
class RecoveryManager {
  async recover(): Promise<void> {
    this.logger.info('Starting recovery process...');
    
    // タスクデータベースを読み込み
    const db = await this.store.load();
    
    // 実行中だったタスクを検出
    const runningTasks = db.tasks.filter(t => t.status === 'running');
    
    for (const task of runningTasks) {
      await this.recoverTask(task);
    }
    
    // 孤立したリソースをクリーンアップ
    await this.cleanupOrphanedResources();
    
    this.logger.info('Recovery completed');
  }
  
  private async recoverTask(task: Task): Promise<void> {
    this.logger.info(`Recovering task: ${task.id}`);
    
    // Tmuxセッションが存在するか確認
    const sessionActive = await this.tmuxManager.isSessionActive(task.tmuxSession);
    
    if (sessionActive) {
      // セッションが存在する場合、監視を再開
      this.logger.info(`Task ${task.id} is still running, resuming monitoring`);
      await this.taskMonitor.startMonitoring(task.id);
    } else {
      // セッションが存在しない場合、失敗としてマーク
      this.logger.warn(`Task ${task.id} session not found, marking as failed`);
      await this.taskManager.updateTaskStatus(task.id, 'failed', {
        error: 'Process crashed or session lost'
      });
      
      // クリーンアップ
      if (task.worktreePath) {
        await this.worktreeManager.removeWorktree(task.worktreePath, true);
      }
    }
  }
  
  private async cleanupOrphanedResources(): Promise<void> {
    // 孤立したworktreeを検出
    const orphanedWorktrees = await this.worktreeManager.findOrphanedWorktrees();
    for (const worktree of orphanedWorktrees) {
      this.logger.warn(`Cleaning up orphaned worktree: ${worktree}`);
      await this.worktreeManager.removeWorktree(worktree, true);
    }
    
    // 孤立したtmuxセッションを検出
    const orphanedSessions = await this.tmuxManager.findOrphanedSessions();
    for (const session of orphanedSessions) {
      this.logger.warn(`Cleaning up orphaned session: ${session}`);
      await this.tmuxManager.killSession(session);
    }
  }
}
```

## データマイグレーション

### バージョン間のマイグレーション

```typescript
interface Migration {
  version: string;
  migrate: (data: any) => Promise<any>;
}

class MigrationManager {
  private migrations: Migration[] = [
    {
      version: '1.0.0',
      migrate: async (data) => {
        // 初期バージョン、そのまま返す
        return data;
      }
    },
    {
      version: '1.1.0',
      migrate: async (data) => {
        // metadata フィールドを追加
        for (const task of data.tasks) {
          if (!task.metadata) {
            task.metadata = {
              retryCount: 0,
              priority: 0,
              labels: [],
              assignee: null
            };
          }
        }
        return data;
      }
    }
  ];
  
  async migrate(data: any, targetVersion: string): Promise<any> {
    const currentVersion = data.version || '1.0.0';
    
    // 現在のバージョンからターゲットまでのマイグレーションを適用
    let migratedData = data;
    
    for (const migration of this.migrations) {
      if (this.compareVersions(migration.version, currentVersion) > 0 &&
          this.compareVersions(migration.version, targetVersion) <= 0) {
        this.logger.info(`Applying migration to ${migration.version}`);
        migratedData = await migration.migrate(migratedData);
        migratedData.version = migration.version;
      }
    }
    
    return migratedData;
  }
  
  private compareVersions(v1: string, v2: string): number {
    const parts1 = v1.split('.').map(Number);
    const parts2 = v2.split('.').map(Number);
    
    for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
      const p1 = parts1[i] || 0;
      const p2 = parts2[i] || 0;
      
      if (p1 !== p2) {
        return p1 - p2;
      }
    }
    
    return 0;
  }
}
```

## ベストプラクティス

1. **定期的な自動保存**: 状態の変更を定期的に永続化（5秒ごと推奨）
2. **トランザクション管理**: 複数のリソース操作をアトミックに実行
3. **バックアップ**: 定期的なバックアップと古いバックアップの削除
4. **復旧処理**: 起動時に必ず復旧処理を実行
5. **バージョン管理**: データフォーマットのバージョンを管理し、マイグレーションを提供
6. **エラーハンドリング**: 状態の不整合を検出し、適切に対処
7. **ログ記録**: 全ての状態変更をログに記録
8. **キャッシュ管理**: 頻繁にアクセスするデータはキャッシュ、TTLを設定
