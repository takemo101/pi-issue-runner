# Public API Reference

このドキュメントは、`pi-issue-runner` のライブラリ関数のうち、外部から利用可能な公開API関数をリストアップしています。

> **Note**: これらの関数は `lib/` ディレクトリに定義されており、現時点では `scripts/` から直接呼び出されていませんが、将来の拡張や外部スクリプトからの利用を想定して保持されています。

---

## 目次

- [マルチプレクサ操作](#マルチプレクサ操作)
- [依存関係解析](#依存関係解析)
- [ワークフロー管理](#ワークフロー管理)
- [Worktree管理](#worktree管理)
- [設定管理](#設定管理)
- [YAML処理](#yaml処理)
- [ログ管理](#ログ管理)

---

## マルチプレクサ操作

### count_active_sessions

**定義場所**: `lib/tmux.sh`（後方互換ラッパー、実装: `lib/multiplexer.sh`）

**説明**: アクティブなセッション数をカウントします。これは `mux_count_active_sessions()` の後方互換性ラッパーです。

**使用例**:
```bash
source lib/multiplexer.sh  # または lib/tmux.sh（後方互換）

count=$(count_active_sessions)
echo "Active sessions: $count"
```

**戻り値**: 
- アクティブなセッション数（整数）
- エラー時は 0

**使用予定箇所**:
- 並列実行数の制限チェック
- ダッシュボードでのセッション数表示
- ステータス監視スクリプト

**関連関数**:
- `mux_count_active_sessions` (lib/multiplexer-tmux.sh, lib/multiplexer-zellij.sh)
- `check_concurrent_limit` (lib/multiplexer.sh / lib/tmux.sh)

---

## 依存関係解析

### get_issues_in_layer

**定義場所**: `lib/dependency.sh`

**説明**: 依存関係グラフから特定のレイヤー（層）に属するIssue番号のリストを取得します。レイヤー0は依存関係のないIssue、レイヤー1はレイヤー0のIssueにのみ依存するIssue、という形で階層化されます。

**使用例**:
```bash
source lib/dependency.sh

# 依存関係情報（issue_number dependency1,dependency2 の形式）
dependencies="42 
43 42
44 42,43"

# レイヤー0のIssueを取得（依存なし）
layer0=$(get_issues_in_layer 0 "$dependencies")
echo "Layer 0: $layer0"  # → "42"

# レイヤー1のIssueを取得（レイヤー0に依存）
layer1=$(get_issues_in_layer 1 "$dependencies")
echo "Layer 1: $layer1"  # → "43"
```

**引数**:
1. `layer_number` - 取得するレイヤー番号（0以上の整数）
2. `dependencies` - 依存関係情報（タブ区切りの文字列）

**戻り値**:
- 指定レイヤーに属するIssue番号のスペース区切り文字列
- 該当するIssueがない場合は空文字列

**使用予定箇所**:
- バッチ実行での優先順位決定 (`scripts/run-batch.sh`)
- 依存関係を考慮したタスクスケジューリング
- 次に実行すべきタスクの推奨 (`scripts/next.sh`)

**関連関数**:
- `calculate_dependency_layers` (lib/dependency.sh)
- `get_max_layer` (lib/dependency.sh)

---

## ワークフロー管理

### get_workflow_steps_array

**定義場所**: `lib/workflow.sh`

**説明**: ワークフロー名から、そのワークフローに含まれるステップのリストを配列形式で取得します。カスタムワークフローの動的処理に使用します。

**使用例**:
```bash
source lib/workflow.sh

# デフォルトワークフローのステップを取得
steps=$(get_workflow_steps_array "default" "/path/to/project")
echo "$steps"  # → "plan implement review merge"

# カスタムワークフローのステップを取得
steps=$(get_workflow_steps_array "simple" "/path/to/project")
echo "$steps"  # → "implement merge"
```

**引数**:
1. `workflow_name` - ワークフロー名
2. `project_root` - プロジェクトルートディレクトリ（カスタムワークフローの検索に使用）

**戻り値**:
- ステップ名のスペース区切り文字列
- ワークフローが見つからない場合は空文字列

**使用予定箇所**:
- カスタムワークフローの動的処理
- ワークフロー進行状況の表示
- ステップごとのプロンプト生成

**関連関数**:
- `list_available_workflows` (lib/workflow.sh)
- `write_workflow_prompt` (lib/workflow-prompt.sh)

---

## Worktree管理

### list_worktrees

**定義場所**: `lib/worktree.sh`

**説明**: 現在のリポジトリに存在する全てのgit worktreeの一覧を取得します。

**使用例**:
```bash
source lib/worktree.sh

# worktree一覧を取得
worktrees=$(list_worktrees)

# 各worktreeを処理
while IFS= read -r line; do
    # パースしてパスを取得
    path=$(echo "$line" | awk '{print $1}')
    echo "Worktree: $path"
done <<< "$worktrees"
```

**戻り値**:
- `git worktree list` の出力（改行区切り）
- 各行の形式: `<path> <commit-hash> [<branch>]`
- エラー時は空文字列

**使用予定箇所**:
- ダッシュボードでの全タスク一覧表示
- worktreeのクリーンアップ処理
- ステータス確認スクリプト

**関連関数**:
- `find_worktree_by_issue` (lib/worktree.sh)
- `create_worktree` (lib/worktree.sh)
- `remove_worktree` (lib/worktree.sh)

---

## 設定管理

### reload_config

**定義場所**: `lib/config.sh`

**説明**: 設定ファイルを再読み込みします。長時間実行するプロセスで設定変更を反映させる際に使用します。

**使用例**:
```bash
source lib/config.sh

# 初回読み込み
load_config

# 設定を取得
max_concurrent=$(get_config parallel_max_concurrent)
echo "Max concurrent: $max_concurrent"

# 設定ファイルを編集後...
# 設定を再読み込み
reload_config

# 更新された設定を取得
max_concurrent=$(get_config parallel_max_concurrent)
echo "Updated max concurrent: $max_concurrent"
```

**戻り値**:
- なし（グローバル変数 `_CONFIG_CACHE` を更新）

**使用予定箇所**:
- デーモンプロセスでの設定更新
- 長時間実行するwatch-sessionスクリプト
- 対話的な設定変更ツール

**注意事項**:
- 環境変数 (`PI_RUNNER_*`) は再読み込みされません
- デフォルト値は変更されません
- 設定ファイルの構文エラーがある場合、前の設定が保持されます

**関連関数**:
- `load_config` (lib/config.sh)
- `get_config` (lib/config.sh)
- `set_config` (lib/config.sh)

---

## YAML処理

### reset_yq_cache

**定義場所**: `lib/yaml.sh`

**説明**: YAMLパーサーのキャッシュをクリアします。テストやデバッグ時に、YAMLファイルの変更を確実に反映させる際に使用します。

**使用例**:
```bash
source lib/yaml.sh

# YAMLファイルを読み込み（キャッシュされる）
value=$(yaml_get "workflows/default.yaml" ".name")
echo "Workflow name: $value"

# YAMLファイルを編集...
# キャッシュをクリア
reset_yq_cache

# 再度読み込み（更新された内容が反映される）
value=$(yaml_get "workflows/default.yaml" ".name")
echo "Updated workflow name: $value"
```

**戻り値**:
- なし（グローバル変数 `_YQ_CACHE` をクリア）

**使用予定箇所**:
- ユニットテストでのクリーンアップ
- ワークフロー定義の動的リロード
- デバッグスクリプト

**関連関数**:
- `yaml_get` (lib/yaml.sh)
- `yaml_get_array` (lib/yaml.sh)
- `check_yq_cli` (lib/yaml.sh)

---

## ログ管理

### set_log_level

**定義場所**: `lib/log.sh`

**説明**: ログ出力レベルを動的に変更します。デバッグ時やCI環境での詳細ログ出力に使用します。

**使用例**:
```bash
source lib/log.sh

# デフォルトはINFOレベル
log_debug "This will not be shown"
log_info "This will be shown"

# DEBUGレベルに変更
set_log_level "DEBUG"

log_debug "This will now be shown"
log_info "This will still be shown"

# WARNレベルに変更（INFOは表示されなくなる）
set_log_level "WARN"

log_debug "Not shown"
log_info "Not shown"
log_warn "This will be shown"
log_error "This will also be shown"
```

**引数**:
1. `level` - ログレベル（"DEBUG", "INFO", "WARN", "ERROR"）

**戻り値**:
- なし（グローバル変数 `LOG_LEVEL` を更新）

**使用予定箇所**:
- デバッグモードの有効化（`--debug` フラグ）
- CI環境での詳細ログ出力
- 対話的なログレベル変更

**注意事項**:
- 無効なレベルを指定した場合、デフォルトで "INFO" にフォールバックします
- 環境変数 `LOG_LEVEL` が設定されている場合、それが優先されます

**ログレベルの階層**:
```
ERROR (最も重要)
  ↑
WARN
  ↑
INFO (デフォルト)
  ↑
DEBUG (最も詳細)
```

**関連関数**:
- `log_debug` (lib/log.sh)
- `log_info` (lib/log.sh)
- `log_warn` (lib/log.sh)
- `log_error` (lib/log.sh)

---

## 使用ガイドライン

### 公開API関数を使用する際の推奨事項

1. **ライブラリの読み込み**
   ```bash
   source "$SCRIPT_DIR/../lib/config.sh"
   source "$SCRIPT_DIR/../lib/log.sh"
   # 必要なライブラリを明示的に読み込む
   ```

2. **エラーハンドリング**
   ```bash
   if reload_config; then
       echo "Config reloaded successfully"
   else
       echo "Failed to reload config" >&2
       exit 1
   fi
   ```

3. **戻り値の確認**
   ```bash
   count=$(count_active_sessions)
   if [[ -z "$count" || "$count" -eq 0 ]]; then
       echo "No active sessions"
   fi
   ```

4. **依存関係の考慮**
   - 公開API関数は、同じライブラリ内の他の関数に依存している場合があります
   - ライブラリファイルを `source` することで、依存関係は自動的に解決されます

### 非推奨の使用パターン

1. **内部実装への直接アクセス**
   ```bash
   # ❌ BAD: 内部変数に直接アクセス
   echo "$_CONFIG_CACHE"
   
   # ✅ GOOD: 公開API関数を使用
   value=$(get_config key_name)
   ```

2. **プライベート関数の呼び出し**
   ```bash
   # ❌ BAD: アンダースコアで始まる内部関数を呼び出し
   _internal_function
   
   # ✅ GOOD: 公開API関数を使用
   public_function
   ```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2026-02-06 | 1.0.0 | 初版作成（Issue #849） |

---

## 関連ドキュメント

- [アーキテクチャ設計](./architecture.md) - システム全体の構成
- [設定リファレンス](./configuration.md) - 設定ファイルの詳細
- [ワークフロー](./workflows.md) - ワークフローの仕組み
- [開発ガイド](../AGENTS.md) - 開発者向け情報
