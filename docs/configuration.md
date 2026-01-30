# 設定

## 概要

Pi Issue Runnerの動作は設定ファイルでカスタマイズできます。設定ファイルはプロジェクトルートまたはホームディレクトリに配置します。

## 設定ファイルの場所

設定ファイルは以下の順序で検索され、最初に見つかったものが使用されます：

1. `--config` オプションで指定されたパス
2. プロジェクトルート: `./.pi-runner.yml`
3. ホームディレクトリ: `~/.pi-runner/config.yml`
4. デフォルト設定（ファイルなし）

## 設定フォーマット

### YAML形式（推奨）

```yaml
# .pi-runner.yml

# Git Worktree設定
worktree:
  base_dir: ".worktrees"        # Worktreeの作成先ディレクトリ
  copy_files:                   # Worktreeに自動コピーするファイル
    - ".env"
    - ".env.local"
    - "config/local.json"
  symlink_node_modules: false   # node_modulesをシンボリックリンクで共有

# Tmux設定
tmux:
  session_prefix: "pi-issue"    # セッション名のプレフィックス
  start_in_session: true        # 作成後に自動アタッチ
  log_output: true              # 出力をファイルにログ
  capture_interval: 1000        # 出力キャプチャ間隔（ミリ秒）

# Pi設定
pi:
  command: "pi"                 # piコマンドのパス
  args: []                      # デフォルトで渡す引数
  timeout: 0                    # タイムアウト（0=無制限、ミリ秒）

# 並列実行設定
parallel:
  max_concurrent: 5             # 最大同時実行数
  queue_strategy: "fifo"        # キュー戦略（fifo | priority）
  auto_cleanup: true            # 完了後に自動クリーンアップ
  resolve_dependencies: false   # Issue間の依存関係を解決

# GitHub設定
github:
  token: ""                     # GitHubトークン（未指定時はgh CLIを使用）
  api_url: "https://api.github.com"  # GitHub API URL（Enterprise用）

# ログ設定
logging:
  level: "info"                 # ログレベル（debug | info | warn | error）
  file: ".pi-runner/system.log" # システムログファイルのパス
  max_size: 104857600           # ログファイルの最大サイズ（バイト）
  rotate: true                  # ログローテーション有効化

# データディレクトリ設定
data:
  dir: ".pi-runner"             # データディレクトリ
  backup_dir: ".pi-runner/backups"  # バックアップディレクトリ
  auto_backup: true             # 自動バックアップ有効化
  backup_interval: 3600000      # バックアップ間隔（ミリ秒、1時間）

# リソース管理
resources:
  max_cpu: 80                   # CPU使用率の上限（%）
  max_memory: 80                # メモリ使用率の上限（%）
  min_disk_space: 1073741824    # 最小ディスク空き容量（バイト、1GB）

# エラーハンドリング
error:
  strategy: "continue"          # 失敗戦略（continue | stop-all | retry）
  max_retries: 3                # 最大リトライ回数
  retry_delay: 5000             # リトライ間隔（ミリ秒）

# 通知設定（将来実装）
notifications:
  enabled: false
  slack_webhook: ""
  email: ""
```

### JSON形式

```json
{
  "worktree": {
    "base_dir": ".worktrees",
    "copy_files": [".env", ".env.local"],
    "symlink_node_modules": false
  },
  "tmux": {
    "session_prefix": "pi-issue",
    "start_in_session": true,
    "log_output": true
  },
  "pi": {
    "command": "pi",
    "args": [],
    "timeout": 0
  },
  "parallel": {
    "max_concurrent": 5,
    "queue_strategy": "fifo",
    "auto_cleanup": true
  }
}
```

## 設定項目の詳細

### worktree

#### base_dir
- **型**: `string`
- **デフォルト**: `.worktrees`
- **説明**: Git worktreeを作成するディレクトリ

#### copy_files
- **型**: `string[]`
- **デフォルト**: `[".env"]`
- **説明**: Worktree作成時にコピーするファイルのリスト（プロジェクトルートからの相対パス）

#### symlink_node_modules
- **型**: `boolean`
- **デフォルト**: `false`
- **説明**: `node_modules`をシンボリックリンクで共有（ディスク容量節約）

### tmux

#### session_prefix
- **型**: `string`
- **デフォルト**: `pi-issue`
- **説明**: Tmuxセッション名のプレフィックス（実際のセッション名: `{prefix}-{issue番号}`）

#### start_in_session
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: タスク作成後、自動的にセッションにアタッチ

#### log_output
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: セッションの出力をファイルに記録

#### capture_interval
- **型**: `number`
- **デフォルト**: `1000`
- **説明**: 出力をキャプチャする間隔（ミリ秒）

### pi

#### command
- **型**: `string`
- **デフォルト**: `pi`
- **説明**: piコマンドのパス（フルパスまたはPATH内のコマンド名）

#### args
- **型**: `string[]`
- **デフォルト**: `[]`
- **説明**: piコマンドに常に渡す追加引数

**例**:
```yaml
pi:
  args:
    - "--verbose"
    - "--model"
    - "claude-sonnet-4"
```

#### timeout
- **型**: `number`
- **デフォルト**: `0`
- **説明**: タスクのタイムアウト（ミリ秒、0は無制限）

### parallel

#### max_concurrent
- **型**: `number`
- **デフォルト**: `5`
- **説明**: 同時に実行できるタスクの最大数

**推奨値**: CPUコア数の50-75%

#### queue_strategy
- **型**: `"fifo" | "priority"`
- **デフォルト**: `"fifo"`
- **説明**: タスクキューの処理戦略
  - `fifo`: 先入れ先出し
  - `priority`: 優先度ベース（Issueラベルから計算）

#### auto_cleanup
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: タスク完了後に自動的にworktreeとセッションをクリーンアップ

#### resolve_dependencies
- **型**: `boolean`
- **デフォルト**: `false`
- **説明**: Issue本文から依存関係を解析し、順序を調整

### github

#### token
- **型**: `string`
- **デフォルト**: `""`
- **説明**: GitHub APIトークン（未指定時は `gh` CLIを使用）

**取得方法**:
```bash
# gh CLIで取得
gh auth token
```

#### api_url
- **型**: `string`
- **デフォルト**: `"https://api.github.com"`
- **説明**: GitHub API URL（GitHub Enterprise Server用）

### logging

#### level
- **型**: `"debug" | "info" | "warn" | "error"`
- **デフォルト**: `"info"`
- **説明**: ログレベル

#### file
- **型**: `string`
- **デフォルト**: `".pi-runner/system.log"`
- **説明**: システムログファイルのパス

#### max_size
- **型**: `number`
- **デフォルト**: `104857600` (100MB)
- **説明**: ログファイルの最大サイズ（バイト）

#### rotate
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: ログローテーション有効化

### data

#### dir
- **型**: `string`
- **デフォルト**: `".pi-runner"`
- **説明**: タスク状態やメタデータを保存するディレクトリ

#### backup_dir
- **型**: `string`
- **デフォルト**: `".pi-runner/backups"`
- **説明**: バックアップファイルの保存先

#### auto_backup
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: 自動バックアップ有効化

#### backup_interval
- **型**: `number`
- **デフォルト**: `3600000` (1時間)
- **説明**: バックアップ作成間隔（ミリ秒）

### resources

#### max_cpu
- **型**: `number`
- **デフォルト**: `80`
- **説明**: CPU使用率の上限（%）

#### max_memory
- **型**: `number`
- **デフォルト**: `80`
- **説明**: メモリ使用率の上限（%）

#### min_disk_space
- **型**: `number`
- **デフォルト**: `1073741824` (1GB)
- **説明**: 最小ディスク空き容量（バイト）

### error

#### strategy
- **型**: `"continue" | "stop-all" | "retry"`
- **デフォルト**: `"continue"`
- **説明**: タスク失敗時の動作
  - `continue`: 他のタスクは継続
  - `stop-all`: 全タスクを停止
  - `retry`: 失敗したタスクを自動リトライ

#### max_retries
- **型**: `number`
- **デフォルト**: `3`
- **説明**: 最大リトライ回数（`retry`戦略時のみ）

#### retry_delay
- **型**: `number`
- **デフォルト**: `5000`
- **説明**: リトライ間隔（ミリ秒）

## 設定の読み込み

### ConfigManager実装

```typescript
class ConfigManager {
  private config: Config | null = null;
  
  async load(): Promise<Config> {
    if (this.config) {
      return this.config;
    }
    
    // 設定ファイルを検索
    const configPath = await this.findConfigFile();
    
    if (configPath) {
      this.config = await this.loadFromFile(configPath);
    } else {
      this.config = this.getDefaults();
    }
    
    // 環境変数で上書き
    this.applyEnvironmentOverrides(this.config);
    
    // 検証
    this.validate(this.config);
    
    return this.config;
  }
  
  private async findConfigFile(): Promise<string | null> {
    const candidates = [
      './.pi-runner.yml',
      './.pi-runner.yaml',
      './.pi-runner.json',
      path.join(os.homedir(), '.pi-runner/config.yml'),
      path.join(os.homedir(), '.pi-runner/config.yaml'),
      path.join(os.homedir(), '.pi-runner/config.json')
    ];
    
    for (const candidate of candidates) {
      if (await Bun.file(candidate).exists()) {
        return candidate;
      }
    }
    
    return null;
  }
  
  private async loadFromFile(filePath: string): Promise<Config> {
    const ext = path.extname(filePath);
    
    if (ext === '.json') {
      return await Bun.file(filePath).json();
    } else if (ext === '.yml' || ext === '.yaml') {
      // YAML解析（yaml パッケージを使用）
      const content = await Bun.file(filePath).text();
      return YAML.parse(content);
    }
    
    throw new UnsupportedConfigFormatError(`Unsupported config format: ${ext}`);
  }
  
  private applyEnvironmentOverrides(config: Config): void {
    // 環境変数から設定を上書き
    if (process.env.PI_RUNNER_MAX_CONCURRENT) {
      config.parallel.max_concurrent = parseInt(
        process.env.PI_RUNNER_MAX_CONCURRENT
      );
    }
    
    if (process.env.PI_RUNNER_AUTO_CLEANUP) {
      config.parallel.auto_cleanup = 
        process.env.PI_RUNNER_AUTO_CLEANUP === 'true';
    }
    
    if (process.env.GITHUB_TOKEN) {
      config.github.token = process.env.GITHUB_TOKEN;
    }
  }
  
  private validate(config: Config): void {
    // 設定値の検証
    if (config.parallel.max_concurrent < 1) {
      throw new ConfigValidationError(
        'parallel.max_concurrent must be at least 1'
      );
    }
    
    if (config.resources.max_cpu < 1 || config.resources.max_cpu > 100) {
      throw new ConfigValidationError(
        'resources.max_cpu must be between 1 and 100'
      );
    }
    
    // ... その他の検証
  }
  
  getDefaults(): Config {
    return {
      worktree: {
        base_dir: '.worktrees',
        copy_files: ['.env'],
        symlink_node_modules: false
      },
      tmux: {
        session_prefix: 'pi-issue',
        start_in_session: true,
        log_output: true,
        capture_interval: 1000
      },
      pi: {
        command: 'pi',
        args: [],
        timeout: 0
      },
      parallel: {
        max_concurrent: 5,
        queue_strategy: 'fifo',
        auto_cleanup: true,
        resolve_dependencies: false
      },
      github: {
        token: '',
        api_url: 'https://api.github.com'
      },
      logging: {
        level: 'info',
        file: '.pi-runner/system.log',
        max_size: 104857600,
        rotate: true
      },
      data: {
        dir: '.pi-runner',
        backup_dir: '.pi-runner/backups',
        auto_backup: true,
        backup_interval: 3600000
      },
      resources: {
        max_cpu: 80,
        max_memory: 80,
        min_disk_space: 1073741824
      },
      error: {
        strategy: 'continue',
        max_retries: 3,
        retry_delay: 5000
      }
    };
  }
}
```

## 環境変数

設定ファイルの代わりに、またはオーバーライドとして環境変数を使用できます：

| 環境変数 | 説明 | 例 |
|---------|------|-----|
| `PI_RUNNER_MAX_CONCURRENT` | 最大同時実行数 | `10` |
| `PI_RUNNER_AUTO_CLEANUP` | 自動クリーンアップ | `true` |
| `PI_RUNNER_LOG_LEVEL` | ログレベル | `debug` |
| `PI_RUNNER_DATA_DIR` | データディレクトリ | `/var/pi-runner` |
| `GITHUB_TOKEN` | GitHubトークン | `ghp_xxxxx` |
| `TMUX_SESSION_PREFIX` | Tmuxセッションプレフィックス | `dev-issue` |

## CLIオプションによる上書き

コマンドライン引数は設定ファイルと環境変数を上書きします：

```bash
# 設定ファイルを指定
pi-run --config ./custom-config.yml run --issue 42

# 最大同時実行数を上書き
pi-run run --issues 42,43,44 --max-concurrent 10

# 自動クリーンアップを無効化
pi-run run --issue 42 --no-auto-cleanup
```

## 設定の優先順位

1. **CLIオプション** (最優先)
2. **環境変数**
3. **設定ファイル**
4. **デフォルト値** (最低優先)

## 設定例

### 開発環境

```yaml
# .pi-runner.yml (開発)
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env.local"
    - "config/development.json"

tmux:
  start_in_session: true

pi:
  args:
    - "--verbose"

parallel:
  max_concurrent: 3
  auto_cleanup: false  # デバッグのため無効

logging:
  level: "debug"
```

### 本番環境（CI/CD）

```yaml
# .pi-runner.yml (本番)
worktree:
  base_dir: "/tmp/pi-worktrees"
  copy_files:
    - ".env.production"

tmux:
  start_in_session: false  # 非対話モード

parallel:
  max_concurrent: 10
  auto_cleanup: true

logging:
  level: "info"
  file: "/var/log/pi-runner/system.log"

error:
  strategy: "stop-all"  # 本番では失敗時に全停止
```

### チーム開発

```yaml
# .pi-runner.yml (チーム)
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env.local"
    - ".npmrc"

parallel:
  max_concurrent: 5
  queue_strategy: "priority"  # 優先度ベース
  resolve_dependencies: true  # 依存関係解決

github:
  # チームのGitHub Enterprise Server
  api_url: "https://github.company.com/api/v3"

notifications:
  enabled: true
  slack_webhook: "https://hooks.slack.com/services/xxx"
```

## 設定のベストプラクティス

1. **環境ごとに設定ファイルを分ける**: `.pi-runner.dev.yml`, `.pi-runner.prod.yml`
2. **機密情報は環境変数で**: GitHubトークン等は設定ファイルに含めない
3. **リソース制限を適切に設定**: マシンスペックに応じて調整
4. **ログレベルは環境で変える**: 開発=debug、本番=info
5. **自動クリーンアップ**: 本番では有効、開発では無効にしてデバッグしやすく
6. **バックアップ設定**: 本番環境では必ず有効化
7. **設定のバージョン管理**: `.pi-runner.yml`はGitで管理、`.env`は除外

## トラブルシューティング

### 設定ファイルが読み込まれない

```bash
# 設定ファイルの場所を確認
pi-run config --show-path

# 設定内容を表示
pi-run config --show
```

### 設定の検証エラー

```bash
# 設定ファイルを検証
pi-run config --validate
```

### デフォルト設定に戻す

```bash
# 設定ファイルを削除
rm .pi-runner.yml

# または、デフォルト設定を出力
pi-run config --init
```

## 設定スキーマ

JSON Schemaで設定を検証：

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "worktree": {
      "type": "object",
      "properties": {
        "base_dir": { "type": "string" },
        "copy_files": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "parallel": {
      "type": "object",
      "properties": {
        "max_concurrent": {
          "type": "number",
          "minimum": 1
        }
      }
    }
  }
}
```

このスキーマをVS Codeで使用すると、設定ファイル編集時に補完と検証が効きます。
