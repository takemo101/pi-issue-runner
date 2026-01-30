# 並列実行

## 概要

複数のGitHub Issueを同時に処理する機能です。各タスクは独立したworktreeとtmuxセッションで実行されるため、相互に干渉しません。

## アーキテクチャ

```
                     ┌────────────────────────────────┐
                     │      Task Queue Manager        │
                     │                                │
                     │  - タスクキュー                │
                     │  - 実行数制限                  │
                     │  - 優先順位管理                │
                     └────────────┬───────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
          ┌─────────▼─────────┐     ┌──────────▼──────────┐
          │   Task Runner 1   │     │   Task Runner 2     │
          │                   │     │                     │
          │ Issue #42         │     │ Issue #43           │
          │ ├─ Worktree       │     │ ├─ Worktree         │
          │ ├─ Tmux Session   │     │ ├─ Tmux Session     │
          │ └─ Pi Process     │     │ └─ Pi Process       │
          └───────────────────┘     └─────────────────────┘
```

## 並列実行の制御

### 同時実行数の制限

```typescript
interface ParallelConfig {
  maxConcurrent: number;  // 最大同時実行数（デフォルト: 5）
  queueStrategy: 'fifo' | 'priority';  // キュー戦略
}

class TaskQueueManager {
  private runningTasks = new Set<string>();
  private queuedTasks: QueuedTask[] = [];
  
  async enqueueTask(task: Task): Promise<void> {
    // 同時実行数をチェック
    if (this.canStartNewTask()) {
      await this.startTask(task);
    } else {
      this.queuedTasks.push({
        task,
        enqueuedAt: new Date(),
        priority: this.calculatePriority(task)
      });
    }
  }
  
  canStartNewTask(): boolean {
    return this.runningTasks.size < this.config.maxConcurrent;
  }
  
  async processQueue(): Promise<void> {
    while (this.canStartNewTask() && this.queuedTasks.length > 0) {
      const next = this.dequeueTask();
      if (next) {
        await this.startTask(next.task);
      }
    }
  }
}
```

### キュー戦略

#### FIFO (First In, First Out)

```typescript
private dequeueTask(): QueuedTask | null {
  return this.queuedTasks.shift() ?? null;
}
```

#### 優先順位ベース

```typescript
private calculatePriority(task: Task): number {
  // Issueのラベルやマイルストーンから優先度を計算
  let priority = 0;
  
  if (task.labels.includes('urgent')) priority += 100;
  if (task.labels.includes('bug')) priority += 50;
  if (task.milestone) priority += 20;
  
  return priority;
}

private dequeueTask(): QueuedTask | null {
  if (this.queuedTasks.length === 0) return null;
  
  // 優先度が最も高いタスクを取得
  this.queuedTasks.sort((a, b) => b.priority - a.priority);
  return this.queuedTasks.shift() ?? null;
}
```

## タスクライフサイクル管理

### タスク状態の追跡

```typescript
interface TaskState {
  id: string;
  issue: number;
  status: TaskStatus;
  startedAt?: Date;
  completedAt?: Date;
  duration?: number;
  exitCode?: number;
}

class TaskLifecycleManager {
  private states = new Map<string, TaskState>();
  
  async onTaskStarted(taskId: string): Promise<void> {
    const state = this.states.get(taskId);
    if (state) {
      state.status = 'running';
      state.startedAt = new Date();
      await this.persistState();
    }
  }
  
  async onTaskCompleted(taskId: string, exitCode: number): Promise<void> {
    const state = this.states.get(taskId);
    if (state) {
      state.status = exitCode === 0 ? 'completed' : 'failed';
      state.completedAt = new Date();
      state.exitCode = exitCode;
      state.duration = state.completedAt.getTime() - (state.startedAt?.getTime() ?? 0);
      
      await this.persistState();
      await this.processQueue();  // 次のタスクを開始
    }
  }
}
```

### タスク監視

各タスクの状態を定期的にチェック：

```typescript
class TaskMonitor {
  private monitors = new Map<string, TaskMonitorInstance>();
  
  startMonitoring(taskId: string): void {
    const instance: TaskMonitorInstance = {
      taskId,
      interval: setInterval(async () => {
        await this.checkTaskStatus(taskId);
      }, 1000),  // 1秒ごとにチェック
      lastCheck: new Date()
    };
    
    this.monitors.set(taskId, instance);
  }
  
  async checkTaskStatus(taskId: string): Promise<void> {
    const task = await this.taskManager.getTask(taskId);
    if (!task) return;
    
    // Tmuxセッションの状態を確認
    const isActive = await this.tmuxManager.isSessionActive(task.tmuxSession);
    
    if (!isActive && task.status === 'running') {
      // タスクが終了した
      const exitCode = await this.tmuxManager.getExitCode(task.tmuxSession);
      await this.lifecycleManager.onTaskCompleted(taskId, exitCode ?? 1);
      this.stopMonitoring(taskId);
    }
  }
  
  stopMonitoring(taskId: string): void {
    const instance = this.monitors.get(taskId);
    if (instance) {
      clearInterval(instance.interval);
      this.monitors.delete(taskId);
    }
  }
}
```

## リソース管理

### CPU・メモリ制限

```typescript
interface ResourceLimits {
  maxCpu?: number;     // CPU使用率の上限（%）
  maxMemory?: number;  // メモリ使用量の上限（MB）
}

class ResourceManager {
  async checkResources(): Promise<ResourceStatus> {
    // システムリソースを取得
    const cpuUsage = await this.getCpuUsage();
    const memoryUsage = await this.getMemoryUsage();
    
    return {
      cpu: cpuUsage,
      memory: memoryUsage,
      available: cpuUsage < 80 && memoryUsage < 80  // 80%以下なら利用可能
    };
  }
  
  async canStartNewTask(): Promise<boolean> {
    const resources = await this.checkResources();
    return resources.available;
  }
}
```

### ディスク容量の監視

```typescript
class DiskSpaceMonitor {
  async checkDiskSpace(): Promise<DiskSpaceInfo> {
    const worktreeDir = this.config.worktree.baseDir;
    
    // ディスク使用状況を取得
    const output = await exec(['df', '-k', worktreeDir]);
    const lines = output.split('\n');
    const stats = lines[1].split(/\s+/);
    
    const total = parseInt(stats[1]) * 1024;  // KB to bytes
    const used = parseInt(stats[2]) * 1024;
    const available = parseInt(stats[3]) * 1024;
    
    return {
      total,
      used,
      available,
      usagePercent: (used / total) * 100
    };
  }
  
  async ensureSpace(required: number): Promise<void> {
    const space = await this.checkDiskSpace();
    
    if (space.available < required) {
      // 古いworktreeをクリーンアップ
      await this.cleanupOldWorktrees();
      
      // 再チェック
      const newSpace = await this.checkDiskSpace();
      if (newSpace.available < required) {
        throw new InsufficientDiskSpaceError(
          `Required: ${required} bytes, Available: ${newSpace.available} bytes`
        );
      }
    }
  }
}
```

## 依存関係の解決

### Issue間の依存関係

```typescript
interface IssueDependency {
  issue: number;
  dependsOn: number[];  // このIssueが依存する他のIssue番号
  blockedBy: number[];  // このIssueをブロックしている他のIssue番号
}

class DependencyResolver {
  async resolveDependencies(issues: number[]): Promise<number[][]> {
    // 依存関係グラフを構築
    const graph = await this.buildDependencyGraph(issues);
    
    // トポロジカルソート
    const sorted = this.topologicalSort(graph);
    
    // 並列実行可能なグループに分割
    return this.groupByLevel(sorted);
  }
  
  private async buildDependencyGraph(
    issues: number[]
  ): Promise<Map<number, IssueDependency>> {
    const graph = new Map<number, IssueDependency>();
    
    for (const issue of issues) {
      const issueData = await this.githubClient.getIssue(issue);
      const deps = this.extractDependencies(issueData);
      
      graph.set(issue, {
        issue,
        dependsOn: deps.dependsOn,
        blockedBy: deps.blockedBy
      });
    }
    
    return graph;
  }
  
  private extractDependencies(issue: GitHubIssue): {
    dependsOn: number[];
    blockedBy: number[];
  } {
    // Issue本文から依存関係を抽出
    // 例: "Depends on #42" or "Blocked by #43"
    const dependsOn: number[] = [];
    const blockedBy: number[] = [];
    
    const dependsOnMatches = issue.body.matchAll(/depends on #(\d+)/gi);
    for (const match of dependsOnMatches) {
      dependsOn.push(parseInt(match[1]));
    }
    
    const blockedByMatches = issue.body.matchAll(/blocked by #(\d+)/gi);
    for (const match of blockedByMatches) {
      blockedBy.push(parseInt(match[1]));
    }
    
    return { dependsOn, blockedBy };
  }
  
  private topologicalSort(
    graph: Map<number, IssueDependency>
  ): number[] {
    const sorted: number[] = [];
    const visited = new Set<number>();
    const visiting = new Set<number>();
    
    const visit = (issue: number) => {
      if (visited.has(issue)) return;
      if (visiting.has(issue)) {
        throw new CircularDependencyError(`Circular dependency detected: ${issue}`);
      }
      
      visiting.add(issue);
      
      const deps = graph.get(issue);
      if (deps) {
        for (const dep of deps.dependsOn) {
          visit(dep);
        }
      }
      
      visiting.delete(issue);
      visited.add(issue);
      sorted.push(issue);
    };
    
    for (const issue of graph.keys()) {
      visit(issue);
    }
    
    return sorted;
  }
  
  private groupByLevel(sorted: number[]): number[][] {
    // 依存関係のレベルごとにグループ化
    // 同じレベルのIssueは並列実行可能
    const groups: number[][] = [];
    const levels = new Map<number, number>();
    
    for (const issue of sorted) {
      const deps = this.graph.get(issue);
      const maxDepLevel = Math.max(
        0,
        ...deps.dependsOn.map(d => levels.get(d) ?? 0)
      );
      const level = maxDepLevel + 1;
      levels.set(issue, level);
      
      if (!groups[level]) {
        groups[level] = [];
      }
      groups[level].push(issue);
    }
    
    return groups.filter(g => g.length > 0);
  }
}
```

### 実行例

```typescript
// Issue #42, #43, #44, #45 を実行
// 依存関係: #43 depends on #42, #45 depends on #43
const issues = [42, 43, 44, 45];
const groups = await dependencyResolver.resolveDependencies(issues);

// groups = [
//   [42, 44],  // レベル0: 並列実行可能
//   [43],      // レベル1: #42完了後に実行
//   [45]       // レベル2: #43完了後に実行
// ]

for (const group of groups) {
  // グループ内のIssueを並列実行
  await Promise.all(group.map(issue => runner.runTask(issue)));
}
```

## エラーハンドリング

### タスク失敗時の動作

```typescript
enum FailureStrategy {
  CONTINUE = 'continue',  // 他のタスクは継続
  STOP_ALL = 'stop-all',  // 全タスクを停止
  RETRY = 'retry'         // 失敗したタスクを再試行
}

class FailureHandler {
  async handleTaskFailure(
    taskId: string,
    error: Error
  ): Promise<void> {
    const strategy = this.config.failureStrategy;
    
    switch (strategy) {
      case FailureStrategy.CONTINUE:
        this.logger.error(`Task ${taskId} failed, continuing others`, error);
        break;
        
      case FailureStrategy.STOP_ALL:
        this.logger.error(`Task ${taskId} failed, stopping all tasks`, error);
        await this.stopAllTasks();
        break;
        
      case FailureStrategy.RETRY:
        this.logger.warn(`Task ${taskId} failed, retrying...`, error);
        await this.retryTask(taskId);
        break;
    }
  }
  
  async retryTask(taskId: string, maxRetries: number = 3): Promise<void> {
    const task = await this.taskManager.getTask(taskId);
    if (!task) return;
    
    const retryCount = task.metadata.retryCount ?? 0;
    
    if (retryCount >= maxRetries) {
      this.logger.error(`Task ${taskId} failed after ${maxRetries} retries`);
      return;
    }
    
    // リトライカウントをインクリメント
    task.metadata.retryCount = retryCount + 1;
    await this.taskManager.updateTask(task);
    
    // タスクを再実行
    await this.runner.runTask(task.issue);
  }
}
```

### デッドロック検出

```typescript
class DeadlockDetector {
  async detectDeadlock(): Promise<boolean> {
    const runningTasks = await this.taskManager.listTasks({ status: 'running' });
    const queuedTasks = await this.taskManager.listTasks({ status: 'queued' });
    
    // 全タスクがキュー内にあり、実行中のタスクがない場合、デッドロック
    if (runningTasks.length === 0 && queuedTasks.length > 0) {
      // 依存関係をチェック
      for (const task of queuedTasks) {
        const deps = await this.getDependencies(task.issue);
        const allDepsQueued = deps.every(dep => 
          queuedTasks.some(t => t.issue === dep)
        );
        
        if (allDepsQueued) {
          return true;  // デッドロック検出
        }
      }
    }
    
    return false;
  }
  
  async resolveDeadlock(): Promise<void> {
    this.logger.error('Deadlock detected, attempting to resolve...');
    
    // 循環依存を検出
    const cycles = await this.findCycles();
    
    if (cycles.length > 0) {
      throw new DeadlockError(
        `Circular dependencies detected: ${cycles.join(', ')}`
      );
    }
  }
}
```

## パフォーマンス最適化

### タスク起動の最適化

```typescript
class TaskLauncher {
  async launchTasksParallel(issues: number[]): Promise<void> {
    // Worktreeを並列作成
    const worktreePaths = await Promise.all(
      issues.map(issue => this.worktreeManager.createWorktree(issue))
    );
    
    // Tmuxセッションを並列作成
    await Promise.all(
      issues.map((issue, index) => 
        this.tmuxManager.createSession(
          `pi-issue-${issue}`,
          worktreePaths[index]
        )
      )
    );
    
    // Piコマンドを並列実行
    await Promise.all(
      issues.map(issue => this.executeTask(issue))
    );
  }
}
```

### バッチ処理

大量のIssueを処理する場合、バッチで分割：

```typescript
class BatchProcessor {
  async processBatch(
    issues: number[],
    batchSize: number = 10
  ): Promise<void> {
    for (let i = 0; i < issues.length; i += batchSize) {
      const batch = issues.slice(i, i + batchSize);
      
      this.logger.info(`Processing batch ${i / batchSize + 1}/${Math.ceil(issues.length / batchSize)}`);
      
      // バッチ内を並列実行
      await Promise.all(
        batch.map(issue => this.runner.runTask(issue))
      );
      
      // バッチ間で少し待機（リソース回復）
      await Bun.sleep(1000);
    }
  }
}
```

## モニタリングとレポート

### リアルタイム状態表示

```typescript
class TaskStatusDashboard {
  async displayStatus(): Promise<void> {
    const tasks = await this.taskManager.listTasks();
    
    console.clear();
    console.log('╔═══════════════════════════════════════════════╗');
    console.log('║          Pi Issue Runner - Status             ║');
    console.log('╚═══════════════════════════════════════════════╝');
    console.log('');
    
    // 統計
    const running = tasks.filter(t => t.status === 'running').length;
    const queued = tasks.filter(t => t.status === 'queued').length;
    const completed = tasks.filter(t => t.status === 'completed').length;
    const failed = tasks.filter(t => t.status === 'failed').length;
    
    console.log(`Running: ${running} | Queued: ${queued} | Completed: ${completed} | Failed: ${failed}`);
    console.log('');
    
    // タスク詳細
    console.log('┌─────────┬──────────┬──────────────┬──────────┐');
    console.log('│ Issue   │ Status   │ Duration     │ Branch   │');
    console.log('├─────────┼──────────┼──────────────┼──────────┤');
    
    for (const task of tasks) {
      const duration = task.completedAt && task.startedAt
        ? formatDuration(task.completedAt.getTime() - task.startedAt.getTime())
        : '-';
      
      console.log(
        `│ #${task.issue.toString().padEnd(6)} │ ` +
        `${this.formatStatus(task.status).padEnd(8)} │ ` +
        `${duration.padEnd(12)} │ ` +
        `${task.branch.substring(0, 8).padEnd(8)} │`
      );
    }
    
    console.log('└─────────┴──────────┴──────────────┴──────────┘');
  }
  
  async watch(interval: number = 1000): Promise<void> {
    setInterval(async () => {
      await this.displayStatus();
    }, interval);
  }
}
```

### パフォーマンスメトリクス

```typescript
interface PerformanceMetrics {
  totalTasks: number;
  completedTasks: number;
  failedTasks: number;
  averageDuration: number;
  successRate: number;
  throughput: number;  // タスク/時間
}

class MetricsCollector {
  async collect(): Promise<PerformanceMetrics> {
    const tasks = await this.taskManager.listTasks();
    const completed = tasks.filter(t => t.status === 'completed');
    const failed = tasks.filter(t => t.status === 'failed');
    
    const durations = completed
      .map(t => t.duration ?? 0)
      .filter(d => d > 0);
    
    const averageDuration = durations.length > 0
      ? durations.reduce((a, b) => a + b, 0) / durations.length
      : 0;
    
    return {
      totalTasks: tasks.length,
      completedTasks: completed.length,
      failedTasks: failed.length,
      averageDuration,
      successRate: tasks.length > 0 
        ? (completed.length / tasks.length) * 100
        : 0,
      throughput: this.calculateThroughput(tasks)
    };
  }
}
```

## ベストプラクティス

1. **適切な並列数**: マシンスペックに応じて `maxConcurrent` を設定（推奨: CPUコア数の50-75%）
2. **リソース監視**: CPU・メモリ・ディスク容量を定期的にチェック
3. **依存関係の明記**: Issue本文に依存関係を明記（例: "Depends on #42"）
4. **エラーハンドリング**: 適切な失敗戦略を設定
5. **定期的なクリーンアップ**: 完了したタスクのリソースを速やかに解放
6. **ログの保存**: 各タスクのログをファイルに保存し、デバッグに活用
7. **バッチ処理**: 大量のタスクはバッチに分割して処理
