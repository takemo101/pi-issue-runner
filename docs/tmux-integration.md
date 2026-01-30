# Tmux統合

## 概要

Tmuxセッションを使用して、各タスクを独立した仮想ターミナル内で実行します。これにより、バックグラウンド実行、アタッチ/デタッチ、出力のキャプチャが可能になります。

## Tmuxとは

Tmux (Terminal Multiplexer) は、1つのターミナルウィンドウで複数のセッションを管理できるツールです。セッションはバックグラウンドで実行され、必要に応じてアタッチ/デタッチできます。

### 主要な概念

- **セッション**: 独立したターミナル環境
- **ウィンドウ**: セッション内の複数のペイン
- **ペイン**: ウィンドウ内の分割された領域

Pi Issue Runnerでは、各タスクを1つのセッションとして管理します。

## セッション管理フロー

```
1. タスクIDを受け取る（例: pi-issue-42）
   ↓
2. Worktreeパスを取得
   ↓
3. Tmuxセッションを作成
   tmux new-session -s {session} -d -c {worktree}
   ↓
4. セッション内でpiコマンドを実行
   tmux send-keys -t {session} "pi '{prompt}'" Enter
   ↓
5. セッション状態を監視
   tmux list-sessions | grep {session}
   ↓
6. タスク完了後、セッションを終了
   tmux kill-session -t {session}
```

## コマンド詳細

### セッション作成

```bash
# 基本的な作成（デタッチ状態）
tmux new-session -s pi-issue-42 -d

# 作業ディレクトリを指定
tmux new-session -s pi-issue-42 -d -c /path/to/worktree

# 作成後すぐにアタッチ
tmux new-session -s pi-issue-42 -c /path/to/worktree
```

**実装**:
```typescript
async createSession(name: string, cwd: string): Promise<void> {
  // セッションが既に存在するか確認
  if (await this.isSessionActive(name)) {
    throw new TmuxSessionExistsError(`Session already exists: ${name}`);
  }

  // セッションを作成
  await this.exec([
    'tmux',
    'new-session',
    '-s', name,
    '-d',              // デタッチ状態で作成
    '-c', cwd          // 作業ディレクトリ
  ]);

  this.logger.info(`Created tmux session: ${name}`);
}
```

### コマンド実行

セッション内でコマンドを実行する：

```bash
# コマンドを送信
tmux send-keys -t pi-issue-42 "echo hello" Enter

# 複数行のコマンド
tmux send-keys -t pi-issue-42 "pi 'Issue #42: Add feature'" Enter
```

**実装**:
```typescript
async executeInSession(
  sessionName: string,
  command: string
): Promise<void> {
  // セッションが存在するか確認
  if (!await this.isSessionActive(sessionName)) {
    throw new TmuxSessionNotFoundError(`Session not found: ${sessionName}`);
  }

  // コマンドを送信
  await this.exec([
    'tmux',
    'send-keys',
    '-t', sessionName,
    command,
    'Enter'
  ]);

  this.logger.info(`Executed command in session ${sessionName}`);
}
```

### セッション状態確認

```bash
# セッション一覧
tmux list-sessions

# 特定セッションの存在確認
tmux has-session -t pi-issue-42
```

**実装**:
```typescript
async isSessionActive(sessionName: string): Promise<boolean> {
  try {
    await this.exec(['tmux', 'has-session', '-t', sessionName]);
    return true;
  } catch (error) {
    return false;
  }
}
```

### セッション一覧取得

```bash
# セッション一覧（詳細）
tmux list-sessions -F "#{session_name}:#{session_created}:#{session_attached}"
```

**出力例**:
```
pi-issue-42:1706592000:0
pi-issue-43:1706592100:1
```

**実装**:
```typescript
interface TmuxSession {
  name: string;
  created: Date;
  attached: boolean;
  windows: number;
}

async listSessions(): Promise<TmuxSession[]> {
  const format = [
    '#{session_name}',
    '#{session_created}',
    '#{session_attached}',
    '#{session_windows}'
  ].join(':');

  const output = await this.exec([
    'tmux',
    'list-sessions',
    '-F', format
  ]);

  const sessions: TmuxSession[] = [];
  
  for (const line of output.split('\n')) {
    if (!line.trim()) continue;
    
    const [name, created, attached, windows] = line.split(':');
    
    sessions.push({
      name,
      created: new Date(parseInt(created) * 1000),
      attached: attached === '1',
      windows: parseInt(windows)
    });
  }

  return sessions;
}
```

### 出力キャプチャ

セッションの現在の出力を取得：

```bash
# 最後の100行をキャプチャ
tmux capture-pane -t pi-issue-42 -p -S -100
```

**実装**:
```typescript
async capturePane(
  sessionName: string,
  lines: number = 100
): Promise<string> {
  const output = await this.exec([
    'tmux',
    'capture-pane',
    '-t', sessionName,
    '-p',              // 標準出力に出力
    '-S', `-${lines}`  // 開始行（負の値で末尾からの相対位置）
  ]);

  return output;
}
```

### セッション終了

```bash
# セッションを終了
tmux kill-session -t pi-issue-42
```

**実装**:
```typescript
async killSession(sessionName: string): Promise<void> {
  if (!await this.isSessionActive(sessionName)) {
    this.logger.warn(`Session not found: ${sessionName}`);
    return;
  }

  await this.exec(['tmux', 'kill-session', '-t', sessionName]);

  this.logger.info(`Killed session: ${sessionName}`);
}
```

### セッションにアタッチ

```bash
# セッションにアタッチ（対話モード）
tmux attach -t pi-issue-42
```

**実装**:
```typescript
async attachToSession(sessionName: string): Promise<void> {
  if (!await this.isSessionActive(sessionName)) {
    throw new TmuxSessionNotFoundError(`Session not found: ${sessionName}`);
  }

  // 対話的にアタッチ（現在のプロセスを置き換え）
  await Bun.spawn(['tmux', 'attach', '-t', sessionName], {
    stdin: 'inherit',
    stdout: 'inherit',
    stderr: 'inherit'
  });
}
```

## 高度な機能

### ログファイルへの出力保存

セッションの出力をリアルタイムでファイルに保存：

```bash
# ログパイプを有効化
tmux pipe-pane -t pi-issue-42 -o "cat >> /path/to/log.txt"
```

**実装**:
```typescript
async enableLogging(
  sessionName: string,
  logPath: string
): Promise<void> {
  // ログディレクトリを作成
  await Bun.write(logPath, ''); // ファイルを作成

  // パイプパインを有効化
  await this.exec([
    'tmux',
    'pipe-pane',
    '-t', sessionName,
    '-o',
    `cat >> ${logPath}`
  ]);

  this.logger.info(`Enabled logging for session ${sessionName} to ${logPath}`);
}
```

### セッションの状態監視

定期的にセッションの状態をポーリング：

```typescript
class TmuxSessionMonitor {
  private intervals = new Map<string, Timer>();

  startMonitoring(
    sessionName: string,
    callback: (status: SessionStatus) => void,
    interval: number = 1000
  ): void {
    const timer = setInterval(async () => {
      const isActive = await this.tmuxManager.isSessionActive(sessionName);
      
      if (!isActive) {
        // セッションが終了した
        this.stopMonitoring(sessionName);
        callback({ active: false, exitCode: await this.getExitCode(sessionName) });
        return;
      }

      // 出力をキャプチャして状態を確認
      const output = await this.tmuxManager.capturePane(sessionName, 10);
      
      callback({ active: true, lastOutput: output });
    }, interval);

    this.intervals.set(sessionName, timer);
  }

  stopMonitoring(sessionName: string): void {
    const timer = this.intervals.get(sessionName);
    if (timer) {
      clearInterval(timer);
      this.intervals.delete(sessionName);
    }
  }
}
```

### 終了コードの取得

piプロセスの終了コードを取得：

```typescript
async getExitCode(sessionName: string): Promise<number | null> {
  try {
    // セッション内で最後に実行されたコマンドの終了コードを取得
    const output = await this.exec([
      'tmux',
      'display-message',
      '-t', sessionName,
      '-p',
      '#{pane_dead_status}'
    ]);

    return parseInt(output.trim()) || 0;
  } catch (error) {
    return null;
  }
}
```

## ウィンドウとペインの活用

複雑なタスクでは、1つのセッション内に複数のウィンドウを作成：

```typescript
async createWindowForTask(
  sessionName: string,
  windowName: string,
  command: string
): Promise<void> {
  // 新しいウィンドウを作成
  await this.exec([
    'tmux',
    'new-window',
    '-t', sessionName,
    '-n', windowName
  ]);

  // コマンドを実行
  await this.executeInWindow(
    sessionName,
    windowName,
    command
  );
}

async executeInWindow(
  sessionName: string,
  windowName: string,
  command: string
): Promise<void> {
  await this.exec([
    'tmux',
    'send-keys',
    '-t', `${sessionName}:${windowName}`,
    command,
    'Enter'
  ]);
}
```

**使用例**:
```typescript
// メインウィンドウでpiを実行
await tmux.executeInSession('pi-issue-42', 'pi "Implement feature"');

// 別ウィンドウでログを監視
await tmux.createWindowForTask(
  'pi-issue-42',
  'logs',
  'tail -f .pi-runner/logs/issue-42.log'
);

// 別ウィンドウでテストを実行
await tmux.createWindowForTask(
  'pi-issue-42',
  'tests',
  'bun test --watch'
);
```

## エラーハンドリング

### セッションが既に存在する場合

```typescript
async createSession(name: string, cwd: string): Promise<void> {
  if (await this.isSessionActive(name)) {
    // オプション1: エラーを投げる
    throw new TmuxSessionExistsError(`Session already exists: ${name}`);
    
    // オプション2: 既存セッションを終了して再作成（--force フラグ時）
    if (options.force) {
      await this.killSession(name);
      // 作成処理を続行
    }
  }
  
  // セッション作成
}
```

### Tmuxが利用できない場合

```typescript
async checkTmuxAvailable(): Promise<boolean> {
  try {
    await this.exec(['which', 'tmux']);
    return true;
  } catch (error) {
    return false;
  }
}

// 初期化時にチェック
async initialize(): Promise<void> {
  if (!await this.checkTmuxAvailable()) {
    throw new TmuxNotInstalledError('tmux is not installed or not in PATH');
  }
}
```

### セッション終了の検出

```typescript
async waitForSessionExit(
  sessionName: string,
  timeout: number = 0
): Promise<SessionExitInfo> {
  const startTime = Date.now();
  
  while (await this.isSessionActive(sessionName)) {
    // タイムアウトチェック
    if (timeout > 0 && Date.now() - startTime > timeout) {
      throw new TimeoutError(`Session ${sessionName} did not exit within ${timeout}ms`);
    }
    
    // 短い間隔でポーリング
    await Bun.sleep(500);
  }
  
  return {
    exitCode: await this.getExitCode(sessionName),
    duration: Date.now() - startTime
  };
}
```

## パフォーマンス最適化

### セッション一覧のキャッシュ

頻繁にセッション一覧を取得する場合、キャッシュを使用：

```typescript
class TmuxManager {
  private sessionCache: Map<string, boolean> = new Map();
  private cacheExpiry = 1000; // 1秒
  private lastCacheUpdate = 0;

  async isSessionActive(sessionName: string): Promise<boolean> {
    // キャッシュをチェック
    if (Date.now() - this.lastCacheUpdate < this.cacheExpiry) {
      return this.sessionCache.get(sessionName) ?? false;
    }

    // キャッシュを更新
    await this.updateSessionCache();

    return this.sessionCache.get(sessionName) ?? false;
  }

  private async updateSessionCache(): Promise<void> {
    const sessions = await this.listSessions();
    
    this.sessionCache.clear();
    for (const session of sessions) {
      this.sessionCache.set(session.name, true);
    }
    
    this.lastCacheUpdate = Date.now();
  }
}
```

### バッチコマンド実行

複数のコマンドを一度に実行：

```typescript
async executeBatch(
  sessionName: string,
  commands: string[]
): Promise<void> {
  const script = commands.join(' && ');
  await this.executeInSession(sessionName, script);
}

// 使用例
await tmux.executeBatch('pi-issue-42', [
  'cd /path/to/worktree',
  'source .env',
  'pi "Implement feature"'
]);
```

## セキュリティ考慮事項

### コマンドインジェクション対策

```typescript
async executeInSession(
  sessionName: string,
  command: string
): Promise<void> {
  // セッション名のバリデーション
  if (!/^[a-zA-Z0-9_-]+$/.test(sessionName)) {
    throw new InvalidSessionNameError('Invalid session name');
  }

  // コマンドのエスケープ
  const escapedCommand = this.escapeCommand(command);

  await this.exec([
    'tmux',
    'send-keys',
    '-t', sessionName,
    escapedCommand,
    'Enter'
  ]);
}

private escapeCommand(command: string): string {
  // シングルクォートで囲み、内部のシングルクォートをエスケープ
  return `'${command.replace(/'/g, "'\\''")}'`;
}
```

### セッション名の検証

```typescript
validateSessionName(name: string): boolean {
  // セッション名のルール:
  // - 英数字、ハイフン、アンダースコアのみ
  // - 先頭は英字
  // - 1-64文字
  const pattern = /^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/;
  return pattern.test(name);
}
```

## トラブルシューティング

### 問題: "tmux: command not found"

**解決**:
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt-get install tmux

# Arch Linux
sudo pacman -S tmux
```

### 問題: セッションがアタッチできない

**原因**: セッションが別のクライアントにアタッチされている

**解決**:
```bash
# 強制的にアタッチ（他のクライアントをデタッチ）
tmux attach -t pi-issue-42 -d
```

### 問題: セッションが終了しない

**原因**: プロセスがバックグラウンドで実行中

**解決**:
```typescript
async forceKillSession(sessionName: string): Promise<void> {
  // セッション内の全プロセスを終了
  await this.exec([
    'tmux',
    'send-keys',
    '-t', sessionName,
    'C-c'  // Ctrl+C
  ]);
  
  await Bun.sleep(1000);
  
  // セッションを強制終了
  await this.exec(['tmux', 'kill-session', '-t', sessionName]);
}
```

### 問題: 出力が文字化けする

**原因**: ロケール設定の問題

**解決**:
```typescript
async createSession(name: string, cwd: string): Promise<void> {
  // UTF-8ロケールを設定
  await this.exec([
    'tmux',
    'new-session',
    '-s', name,
    '-d',
    '-c', cwd,
    'env', 'LANG=en_US.UTF-8'
  ]);
}
```

## ベストプラクティス

1. **セッション名の命名規則**: 一貫した命名規則を使用（例: `{prefix}-issue-{番号}`）
2. **定期的なクリーンアップ**: 孤立したセッションを定期的に削除
3. **ログの保存**: 重要な出力はファイルに保存
4. **タイムアウトの設定**: 長時間実行されるタスクにタイムアウトを設定
5. **エラーハンドリング**: セッション操作の失敗を適切に処理
6. **リソースリーク防止**: セッションの作成と削除を確実にペアで実行
