# Pi Issue Runner - 仕様書

## 概要

Pi Issue RunnerはGitHub Issueを入力として、Git worktreeとtmuxセッションを活用して複数のpiインスタンスを並列実行するタスクランナーです。

## 目的

- GitHub Issueベースの開発ワークフローを自動化
- 複数のタスクを独立した環境で並列実行
- 開発者がセッション間を自由に移動できる柔軟性の提供
- piエージェントの実行環境を分離し、干渉を防ぐ

## 主要機能

### 1. GitHub Issue統合

- GitHub CLI (`gh`) を使用してIssueを取得
- Issue番号から自動的にタスク情報を抽出
- Issue本文をpiのプロンプトとして使用

### 2. Git Worktree管理

- 各Issue専用のworktreeを自動作成
- ブランチ名はIssue番号から自動生成（例: `issue-42`）
- 必要なファイル（.env等）を自動コピー
- タスク完了後の自動クリーンアップ

### 3. Tmuxセッション統合

- 各タスクを独立したtmuxセッション内で実行
- セッション名: `{prefix}-issue-{番号}` (例: `pi-issue-42`)
- アタッチ/デタッチによる柔軟なセッション管理
- バックグラウンド実行のサポート

### 4. Pi実行制御

- Worktree内で独立したpiインスタンスを起動
- Issue内容を自動的にプロンプトとして渡す
- piコマンドへのカスタム引数サポート

### 5. 並列実行

- 複数のIssueを同時に処理
- 各タスクは完全に独立した環境で実行
- 同時実行数の制限設定（リソース管理）

### 6. 状態管理

- タスクの状態追跡（queued, running, completed, failed）
- 実行時間の記録
- 終了コードの保存
- 永続化されたタスク情報（JSON形式）

### 7. ログ管理

- 各タスクのログをファイルに保存
- リアルタイムログストリーミング
- ログの検索・フィルタリング

### 8. クリーンアップ

- 完了したworktreeの自動削除
- tmuxセッションの終了
- タスク履歴のクリア

## コアコンセプト

### タスクライフサイクル

```
queued → running → completed
                 ↘ failed
```

1. **queued**: タスクが作成され、実行待機中
2. **running**: Worktree作成、tmuxセッション起動、pi実行中
3. **completed**: piが正常終了
4. **failed**: piがエラー終了、またはタイムアウト

### 実行フロー

```
Issue番号入力
    ↓
GitHub Issueを取得（gh issue view）
    ↓
Git Worktreeを作成（git worktree add）
    ↓
必要なファイルをコピー（.env等）
    ↓
Tmuxセッションを作成（tmux new-session）
    ↓
セッション内でpiを起動（pi "Issue内容"）
    ↓
タスク状態を監視
    ↓
完了後、オプションでクリーンアップ
```

### ディレクトリ構造

```
project-root/
├── .worktrees/              # Worktree作業ディレクトリ
│   ├── issue-42/            # Issue #42のworktree
│   │   ├── .env             # コピーされた設定ファイル
│   │   ├── src/
│   │   └── ...
│   └── issue-43/            # Issue #43のworktree
│       └── ...
├── .pi-runner/              # Pi Runner管理ディレクトリ
│   ├── tasks.json           # タスク状態（永続化）
│   ├── config.yml           # 設定ファイル
│   └── logs/                # ログディレクトリ
│       ├── issue-42.log     # Issue #42のログ
│       └── issue-43.log     # Issue #43のログ
└── .pi-runner.yml           # ユーザー設定（オプション）
```

## データモデル

### Task

```typescript
interface Task {
  id: string;              // タスクID（例: "pi-issue-42"）
  issue: number;           // GitHub Issue番号
  status: TaskStatus;      // タスク状態
  branch: string;          // ブランチ名
  worktreePath: string;    // Worktreeのパス
  tmuxSession: string;     // Tmuxセッション名
  startedAt?: Date;        // 開始時刻
  completedAt?: Date;      // 完了時刻
  exitCode?: number;       // 終了コード
  error?: string;          // エラーメッセージ
}
```

### TaskStatus

```typescript
type TaskStatus = 
  | 'queued'     // 実行待機中
  | 'running'    // 実行中
  | 'completed'  // 正常完了
  | 'failed';    // 失敗
```

### Config

```typescript
interface Config {
  worktree: {
    baseDir: string;        // Worktree作成先
    copyFiles: string[];    // コピーするファイル
  };
  tmux: {
    sessionPrefix: string;  // セッション名プレフィックス
    startInSession: boolean; // 作成後に自動アタッチ
  };
  pi: {
    command: string;        // piコマンドのパス
    args: string[];         // デフォルト引数
  };
  parallel: {
    maxConcurrent: number;  // 最大同時実行数
    autoCleanup: boolean;   // 自動クリーンアップ
  };
}
```

## 非機能要件

### パフォーマンス

- タスク起動時間: 5秒以内（worktree作成 + tmuxセッション起動）
- 並列実行数: デフォルト5、設定で変更可能
- ログファイルサイズ制限: 100MB/タスク

### 信頼性

- タスク状態の永続化（プロセス再起動後も復元）
- エラー発生時の適切なクリーンアップ
- Worktree/セッションの孤立を防ぐ

### 互換性

- Bun 1.0以上
- GitHub CLI 2.0以上
- tmux 3.0以上
- pi-mono latest

### セキュリティ

- `.env`ファイルのコピー時の権限保持
- GitHub認証情報の安全な取り扱い
- ログファイルへの機密情報記録の回避

## 制約事項

### 技術的制約

- 同一Issue番号で複数のworktreeは作成不可
- Tmuxセッション名の一意性が必要
- Git worktreeの制限に従う（サブモジュール等）

### 運用制約

- Worktree削除前にtmuxセッションを終了する必要がある
- GitHub CLI認証が必須
- プロジェクトルートからの実行を推奨

## 将来の拡張性

### Phase 2（検討中）

- Zellij対応（tmux代替）
- Docker/Podman統合
- GitHub Actions連携
- PR自動作成
- 依存関係解決（Issue間の依存）
- Webhookサポート

### Phase 3（検討中）

- WebダッシュボードUI
- メトリクス収集・可視化
- 複数リポジトリ対応
- チーム機能（タスク共有）

## 参考資料

- [orchestrator-hybrid](https://github.com/takemo101/orchestrator-hybrid)
- [pi-mono](https://github.com/badlogic/pi-mono)
- [Git worktree documentation](https://git-scm.com/docs/git-worktree)
- [tmux documentation](https://github.com/tmux/tmux/wiki)
