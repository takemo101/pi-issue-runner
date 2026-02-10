# Public API Reference

このドキュメントは、`pi-issue-runner` のライブラリ関数のうち、外部から利用可能な公開API関数をリストアップしています。

> **Note**: これらの関数は `lib/` ディレクトリに定義されており、現時点では `scripts/` から直接呼び出されていませんが、将来の拡張や外部スクリプトからの利用を想定して保持されています。

---

## 目次

- [マルチプレクサ操作](#マルチプレクサ操作)
- [マーカー検出](#マーカー検出)
- [依存関係解析](#依存関係解析)
- [ワークフロー管理](#ワークフロー管理)
- [Worktree管理](#worktree管理)
- [設定管理](#設定管理)
- [YAML処理](#yaml処理)
- [ログ管理](#ログ管理)
- [プロンプト効果測定](#プロンプト効果測定)
- [知識ループ](#知識ループ)
- [クロスプラットフォーム互換性](#クロスプラットフォーム互換性)

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

## マーカー検出

### count_markers_outside_codeblock

**定義場所**: `lib/marker.sh`

**説明**: セッション出力からコードブロック外のマーカー数をカウントします。マーカーがコードブロック（\`\`\`で囲まれた部分）内に出現した場合は除外されます。タスク完了やエラー検出に使用されます。

**使用例**:
```bash
source lib/marker.sh

# セッション出力を取得
output=$(mux_get_session_output "issue-42-session" 100)

# COMPLETEマーカーをカウント
complete_marker="###TASK_COMPLETE_42###"
count=$(count_markers_outside_codeblock "$output" "$complete_marker")

if [[ "$count" -gt 0 ]]; then
    echo "Task completed!"
fi

# ERRORマーカーをカウント
error_marker="###TASK_ERROR_42###"
error_count=$(count_markers_outside_codeblock "$output" "$error_marker")

if [[ "$error_count" -gt 0 ]]; then
    echo "Task failed with error!"
fi
```

**引数**:
1. `output` - セッション出力テキスト（複数行）
2. `marker` - 検索するマーカー文字列（例: `###TASK_COMPLETE_42###`）

**戻り値**:
- コードブロック外のマーカー出現数（整数）
- マーカーが見つからない場合は `0`

**動作詳細**:
- マーカーは行頭から出現する必要があります（前後に空白があってもOK）
- 前後1行に \`\`\` がある場合、コードブロック内と判定して除外します
- 複数のマーカーが出現した場合、全てカウントされます

**使用箇所**:
- `scripts/watch-session.sh` - セッション監視とタスク完了検出
- `scripts/sweep.sh` - 全セッションの完了マーカースキャン
- カスタム監視スクリプト

**関連コマンド**:
- `scripts/sweep.sh` - 全セッションのマーカーチェックと自動クリーンアップ
- `scripts/watch-session.sh` - 個別セッションの監視

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
- `compute_layers` (lib/dependency.sh)
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
- なし（グローバル変数 `_CONFIG_LOADED` をリセットし、個別の `CONFIG_*` 変数を再読み込みします）

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
- なし（グローバル変数 `_YAML_CACHE_FILE` と `_YAML_CACHE_CONTENT` をクリアします）

**使用予定箇所**:
- ユニットテストでのクリーンアップ
- ワークフロー定義の動的リロード
- デバッグスクリプト

**関連関数**:
- `yaml_get` (lib/yaml.sh)
- `yaml_get_array` (lib/yaml.sh)
- `check_yq` (lib/yaml.sh)

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

## プロンプト効果測定

### get_tracker_file

**定義場所**: `lib/tracker.sh`

**説明**: トラッカーファイル（`tracker.jsonl`）のパスを取得します。設定ファイルで `tracker_file` が指定されている場合はそれを使用し、未指定の場合は `.worktrees/.status/tracker.jsonl` をデフォルトとして返します。

**使用例**:
```bash
source lib/tracker.sh

# トラッカーファイルのパスを取得
tracker_file=$(get_tracker_file)
echo "Tracker file: $tracker_file"

# ファイルが存在するか確認
if [[ -f "$tracker_file" ]]; then
    echo "Tracker data exists"
    # ファイルを解析
    jq '.' "$tracker_file"
fi
```

**戻り値**:
- トラッカーファイルのフルパス（文字列）
- デフォルト: `.worktrees/.status/tracker.jsonl`

**使用予定箇所**:
- トラッカーデータの集計・分析スクリプト
- ワークフロー成功率のレポート生成
- デバッグ・ログ確認ツール

**関連関数**:
- `record_tracker_entry` (lib/tracker.sh)
- `save_tracker_metadata` (lib/tracker.sh)

---

### save_tracker_metadata

**定義場所**: `lib/tracker.sh`

**説明**: セッション開始時にワークフロー名と開始時刻をメタデータとして保存します。このメタデータは後でタスク完了時に `record_tracker_entry` によって読み込まれ、実行時間の計算に使用されます。

**使用例**:
```bash
source lib/tracker.sh

issue_number=42
workflow_name="default"

# セッション開始時にメタデータを保存
save_tracker_metadata "$issue_number" "$workflow_name"

# この後、タスクが完了または失敗した時に
# record_tracker_entry がこのメタデータを使用して実行時間を記録します
```

**引数**:
1. `issue_number` - Issue番号（整数）
2. `workflow_name` - ワークフロー名（文字列）

**戻り値**:
- なし（メタデータファイル `.worktrees/.status/{issue_number}.tracker-meta` を作成）

**メタデータファイル形式**:
```
{workflow_name}
{timestamp_iso8601}
{epoch_seconds}
```

**使用予定箇所**:
- `scripts/run.sh` - セッション開始時
- `scripts/watch-session.sh` - セッション起動処理
- カスタムワークフロースクリプト

**関連関数**:
- `load_tracker_metadata` (lib/tracker.sh)
- `remove_tracker_metadata` (lib/tracker.sh)
- `record_tracker_entry` (lib/tracker.sh)

---

### load_tracker_metadata

**定義場所**: `lib/tracker.sh`

**説明**: 保存されたメタデータを読み込みます。ワークフロー名、開始タイムスタンプ、エポック秒をタブ区切りで返します。

**使用例**:
```bash
source lib/tracker.sh

issue_number=42

# メタデータを読み込み
if meta_line=$(load_tracker_metadata "$issue_number"); then
    # タブ区切りでパース
    workflow_name=$(echo "$meta_line" | cut -f1)
    start_timestamp=$(echo "$meta_line" | cut -f2)
    start_epoch=$(echo "$meta_line" | cut -f3)
    
    echo "Workflow: $workflow_name"
    echo "Started at: $start_timestamp"
    echo "Epoch: $start_epoch"
    
    # 実行時間を計算
    now_epoch=$(date +%s)
    duration=$((now_epoch - start_epoch))
    echo "Duration: ${duration}s"
else
    echo "No metadata found for issue #$issue_number"
fi
```

**引数**:
1. `issue_number` - Issue番号（整数）

**戻り値**:
- 成功時: `workflow_name<TAB>start_timestamp<TAB>start_epoch` の1行（終了コード 0）
- メタデータが存在しない場合: 空文字列（終了コード 1）

**使用予定箇所**:
- `record_tracker_entry` 内部での実行時間計算
- セッション状態確認スクリプト
- デバッグツール

**関連関数**:
- `save_tracker_metadata` (lib/tracker.sh)
- `remove_tracker_metadata` (lib/tracker.sh)

---

### remove_tracker_metadata

**定義場所**: `lib/tracker.sh`

**説明**: メタデータファイルを削除します。タスク完了時にクリーンアップとして実行されます。

**使用例**:
```bash
source lib/tracker.sh

issue_number=42

# タスク完了後にメタデータを削除
remove_tracker_metadata "$issue_number"

echo "Metadata cleaned up for issue #$issue_number"
```

**引数**:
1. `issue_number` - Issue番号（整数）

**戻り値**:
- なし（メタデータファイル `.worktrees/.status/{issue_number}.tracker-meta` を削除）

**使用予定箇所**:
- `record_tracker_entry` 内部でのクリーンアップ
- `scripts/cleanup.sh` - 手動クリーンアップ
- エラーハンドリング時のクリーンアップ

**関連関数**:
- `save_tracker_metadata` (lib/tracker.sh)
- `load_tracker_metadata` (lib/tracker.sh)

---

### record_tracker_entry

**定義場所**: `lib/tracker.sh`

**説明**: タスクの結果（成功または失敗）をJSONL形式でトラッカーファイルに記録します。保存されたメタデータを読み込んで実行時間を計算し、タイムスタンプと共に記録します。

**使用例**:
```bash
source lib/tracker.sh

issue_number=42

# タスク成功時
record_tracker_entry "$issue_number" "success"

# タスク失敗時（エラータイプを指定）
record_tracker_entry "$issue_number" "error" "test_failure"

# エラータイプの例:
# - "test_failure" - テスト失敗
# - "build_error" - ビルドエラー
# - "ci_timeout" - CIタイムアウト
# - "manual_intervention" - 手動介入が必要
```

**引数**:
1. `issue_number` - Issue番号（整数）
2. `result` - 結果（"success" または "error"）
3. `error_type` - エラー分類（オプション、`result="error"` の時のみ）

**JSONLエントリ形式**:
```json
{"issue":42,"workflow":"default","result":"success","duration_sec":120,"timestamp":"2026-02-10T08:00:00Z"}
{"issue":43,"workflow":"simple","result":"error","duration_sec":45,"error_type":"test_failure","timestamp":"2026-02-10T08:05:00Z"}
```

**戻り値**:
- なし（トラッカーファイルに1行追記、メタデータファイルを削除）

**使用箇所**:
- `scripts/watch-session.sh` - タスク完了時・エラー時
- カスタムワークフローのフック
- 手動テスト・デバッグスクリプト

**関連コマンド**:
- `scripts/tracker.sh` - トラッカーデータの集計・表示

**関連関数**:
- `get_tracker_file` (lib/tracker.sh)
- `save_tracker_metadata` (lib/tracker.sh)
- `load_tracker_metadata` (lib/tracker.sh)
- `remove_tracker_metadata` (lib/tracker.sh)

---

## 知識ループ

### extract_fix_commits

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 指定した期間内の `fix:` で始まるコミットを抽出します。知識ループで過去のバグ修正から知見を収集する際に使用します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間のfixコミットを抽出
fix_commits=$(extract_fix_commits "1 week ago" ".")

# 結果を表示
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    hash=$(echo "$line" | cut -d' ' -f1)
    subject=$(echo "$line" | cut -d' ' -f2-)
    echo "[$hash] $subject"
done <<< "$fix_commits"

# 過去1ヶ月のfixコミットを抽出
fix_commits=$(extract_fix_commits "1 month ago" "/path/to/project")
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago", "2026-01-01"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- コミットハッシュと件名のリスト（各行: `<hash> <subject>`）
- マージコミットは除外される
- 該当コミットがない場合は空文字列

**使用予定箇所**:
- `scripts/knowledge-loop.sh` - 知見抽出の起点
- `scripts/improve.sh` - レビューコンテキスト生成
- 品質分析レポート生成

**関連関数**:
- `get_commit_diff_summary` (lib/knowledge-loop.sh)
- `get_commit_body` (lib/knowledge-loop.sh)
- `generate_knowledge_proposals` (lib/knowledge-loop.sh)

---

### get_commit_diff_summary

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 指定したコミットの変更ファイルとその統計情報（追加・削除行数）を取得します。

**使用例**:
```bash
source lib/knowledge-loop.sh

commit_hash="a1b2c3d"

# 変更サマリーを取得
diff_summary=$(get_commit_diff_summary "$commit_hash" ".")

# 結果を表示
echo "Changes in commit $commit_hash:"
echo "$diff_summary"

# 出力例:
# lib/config.sh    | 15 +++++++++------
# lib/workflow.sh  |  8 +++-----
# 2 files changed, 12 insertions(+), 11 deletions(-)
```

**引数**:
1. `commit_hash` - コミットハッシュ（短縮形でも可）
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- `git diff-tree --stat` の出力
- ファイルごとの変更行数の統計
- 該当コミットが存在しない場合は空文字列

**使用予定箇所**:
- 知見提案の詳細情報生成
- コミット分析レポート
- デバッグ・調査ツール

**関連関数**:
- `extract_fix_commits` (lib/knowledge-loop.sh)
- `get_commit_body` (lib/knowledge-loop.sh)

---

### get_commit_body

**定義場所**: `lib/knowledge-loop.sh`

**説明**: コミットメッセージの本文（件名を除く詳細説明部分）を取得します。

**使用例**:
```bash
source lib/knowledge-loop.sh

commit_hash="a1b2c3d"

# コミットの詳細説明を取得
commit_body=$(get_commit_body "$commit_hash" ".")

if [[ -n "$commit_body" ]]; then
    echo "Commit details:"
    echo "$commit_body"
else
    echo "No detailed description"
fi
```

**引数**:
1. `commit_hash` - コミットハッシュ（短縮形でも可）
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- コミットメッセージの本文（複数行）
- 件名は含まれない
- 本文が存在しない場合は空文字列

**使用予定箇所**:
- 知見提案の理由（Reason）抽出
- コミット詳細分析
- ドキュメント自動生成

**関連関数**:
- `extract_fix_commits` (lib/knowledge-loop.sh)
- `get_commit_diff_summary` (lib/knowledge-loop.sh)

---

### extract_new_decisions

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 指定した期間内に `docs/decisions/` に追加された設計判断ファイル（ADR）を抽出します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間の新しい設計判断を抽出
new_decisions=$(extract_new_decisions "1 week ago" ".")

# 結果を表示
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    hash=$(echo "$line" | cut -d' ' -f1)
    filepath=$(echo "$line" | cut -d' ' -f2-)
    
    # タイトルを取得
    title=$(get_decision_title "$filepath" ".")
    echo "[$hash] $title"
    echo "  File: $filepath"
done <<< "$new_decisions"
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago", "2026-01-01"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- 各行: `<hash> <filepath>`
- `docs/decisions/README.md` は除外される
- 該当ファイルがない場合は空文字列

**使用予定箇所**:
- `scripts/knowledge-loop.sh` - ADRから知見を抽出
- ドキュメント更新検出
- 設計判断の追跡

**関連関数**:
- `get_decision_title` (lib/knowledge-loop.sh)
- `generate_knowledge_proposals` (lib/knowledge-loop.sh)

---

### get_decision_title

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 設計判断ファイル（`docs/decisions/*.md`）の最初の見出し（タイトル）を取得します。

**使用例**:
```bash
source lib/knowledge-loop.sh

filepath="docs/decisions/001-test-parallel-jobs-limit.md"

# タイトルを取得
title=$(get_decision_title "$filepath" ".")

echo "Title: $title"
# 出力例: "001: Bats並列テスト: 16ジョブでハング、デフォルト2ジョブ推奨 (2026-02-05)"
```

**引数**:
1. `filepath` - ファイルパス（プロジェクトルートからの相対パス）
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- ファイルの最初の `#` で始まる行からマークダウン記号を除いたテキスト
- ファイルが存在しない、または見出しがない場合は空文字列

**使用予定箇所**:
- 知見提案の一覧生成
- AGENTS.md への追加提案
- ドキュメント索引生成

**関連関数**:
- `extract_new_decisions` (lib/knowledge-loop.sh)

---

### extract_tracker_failures

**定義場所**: `lib/knowledge-loop.sh`

**説明**: トラッカーファイル（`tracker.jsonl`）から失敗パターンを集計します。エラータイプごとの発生回数を降順で返します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間の失敗パターンを抽出
tracker_failures=$(extract_tracker_failures "1 week ago" ".")

if [[ -n "$tracker_failures" ]]; then
    echo "Failure patterns:"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        count=$(echo "$line" | awk '{print $1}')
        error_type=$(echo "$line" | awk '{print $2}')
        
        # 3回以上発生したエラータイプに注目
        if [[ "$count" -ge 3 ]]; then
            echo "⚠️  $error_type occurred $count times"
        fi
    done <<< "$tracker_failures"
else
    echo "No failures recorded"
fi
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- 各行: `<count> <error_type>`（降順ソート）
- トラッカーファイルが存在しない、またはjqが利用不可の場合は空文字列

**使用予定箇所**:
- 繰り返し発生する問題の検出
- ワークフロー改善の優先順位付け
- 品質メトリクスレポート

**関連関数**:
- `generate_knowledge_proposals` (lib/knowledge-loop.sh)
- `record_tracker_entry` (lib/tracker.sh)

---

### check_agents_duplicate

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 指定したテキストが既に `AGENTS.md` の「既知の制約」セクションに記載されているか確認します。重複した知見の追加を防ぐために使用します。

**使用例**:
```bash
source lib/knowledge-loop.sh

constraint="Bats並列テスト: 16ジョブでハング"

# 重複チェック
if check_agents_duplicate "$constraint" "AGENTS.md"; then
    echo "This constraint is already documented"
else
    echo "This is a new constraint"
    # AGENTS.md への追加処理...
fi

# カスタムAGENTS.mdファイルを使用
if check_agents_duplicate "$constraint" "/path/to/custom/AGENTS.md"; then
    echo "Already documented in custom file"
fi
```

**引数**:
1. `constraint_text` - チェックする制約テキスト
2. `agents_file` - AGENTS.mdファイルのパス（オプション、デフォルト: "AGENTS.md"）

**戻り値**:
- 重複が検出された場合: 終了コード 0
- 重複が検出されなかった場合: 終了コード 1

**判定ロジック**:
- 制約テキストから3文字以上のキーワードを抽出（最大5個）
- キーワードの半数以上が「既知の制約」セクションにマッチした場合に重複と判定

**使用予定箇所**:
- `generate_knowledge_proposals` 内部での重複排除
- `apply_knowledge_proposals` での追加前チェック
- 手動での知見追加時の確認

**関連関数**:
- `generate_knowledge_proposals` (lib/knowledge-loop.sh)
- `apply_knowledge_proposals` (lib/knowledge-loop.sh)

---

### generate_knowledge_proposals

**定義場所**: `lib/knowledge-loop.sh`

**説明**: fixコミット、設計判断ファイル、トラッカー失敗パターンから知見提案を生成し、フォーマットされたレポートを出力します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間の知見を抽出
echo "=== Knowledge Loop Report ==="
generate_knowledge_proposals "1 week ago" "."

# 出力例:
# === Knowledge Loop Analysis (since: 1 week ago) ===
#
# Found 3 new constraint(s) from 5 fix commit(s):
#
# 1. CI修正 - フォーマット対応
#    Source: fix: CI修正 - フォーマット対応 (a1b2c3d)
#    Reason: Rustfmt settings were updated
#
# 2. タイムアウト処理の追加
#    Source: fix: タイムアウト処理の追加 (b2c3d4e)
#
# 3. 001: Bats並列テスト問題 (2026-02-05)
#    Source: docs/decisions/001-test-parallel-jobs-limit.md (c3d4e5f)
#    Detail: See docs/decisions/001-test-parallel-jobs-limit.md
#
# Suggested AGENTS.md additions (既知の制約 section):
#   - CI修正 - フォーマット対応 (from commit a1b2c3d)
#   - タイムアウト処理の追加 (from commit b2c3d4e)
#   - 001: Bats並列テスト問題 (2026-02-05) -> [詳細](docs/decisions/001-test-parallel-jobs-limit.md)
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago", "2026-01-01"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- フォーマットされたレポート（標準出力）
- 新しい知見が見つからない場合は "No new constraints found."

**使用予定箇所**:
- `scripts/knowledge-loop.sh` - 定期的な知見抽出
- CI/CDでの自動レポート生成
- 手動での知識ベース更新確認

**関連関数**:
- `extract_fix_commits` (lib/knowledge-loop.sh)
- `extract_new_decisions` (lib/knowledge-loop.sh)
- `extract_tracker_failures` (lib/knowledge-loop.sh)
- `check_agents_duplicate` (lib/knowledge-loop.sh)
- `apply_knowledge_proposals` (lib/knowledge-loop.sh)

---

### apply_knowledge_proposals

**定義場所**: `lib/knowledge-loop.sh`

**説明**: 知見提案を `AGENTS.md` の「既知の制約」セクションに自動的に追加します。重複チェックを行い、新しい制約のみを追加します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間の知見をAGENTS.mdに追加
if apply_knowledge_proposals "1 week ago" "."; then
    echo "✅ Knowledge proposals applied to AGENTS.md"
    echo "Please review and commit the changes"
else
    exit_code=$?
    if [[ "$exit_code" -eq 1 ]]; then
        echo "ℹ️ No new constraints to add"
    elif [[ "$exit_code" -eq 2 ]]; then
        echo "❌ AGENTS.md not found"
    fi
fi

# 特定のプロジェクトに適用
apply_knowledge_proposals "2 weeks ago" "/path/to/project"
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago", "2026-01-01"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- 0: 成功（新しい制約を追加した）
- 1: 追加する制約がなかった
- 2: `AGENTS.md` が見つからない

**追加処理**:
1. fixコミットと設計判断ファイルから知見を収集
2. `check_agents_duplicate` で重複をフィルタリング
3. 「既知の制約」セクションの適切な位置に挿入
4. セクションが存在しない場合はファイル末尾に作成

**使用予定箇所**:
- `scripts/knowledge-loop.sh` - 自動適用モード
- CI/CDでの知識ベース自動更新
- リリース前の知見マージ

**注意事項**:
- この関数は `AGENTS.md` を直接編集します
- 適用前に `generate_knowledge_proposals` でプレビューすることを推奨
- 適用後は必ず内容を確認してコミットしてください

**関連関数**:
- `generate_knowledge_proposals` (lib/knowledge-loop.sh)
- `check_agents_duplicate` (lib/knowledge-loop.sh)

---

### collect_knowledge_context

**定義場所**: `lib/knowledge-loop.sh`

**説明**: レビューフェーズでAIに提供するための知識コンテキストを収集します。fixコミット、設計判断、トラッカー失敗パターンから関連情報をマークダウン形式で生成します。

**使用例**:
```bash
source lib/knowledge-loop.sh

# 過去1週間の知識コンテキストを収集
context=$(collect_knowledge_context "1 week ago" ".")

if [[ -n "$context" ]]; then
    # レビュープロンプトに注入
    cat agents/review.md > /tmp/review-prompt.md
    echo "$context" >> /tmp/review-prompt.md
    
    # AIにレビューを依頼
    pi --print < /tmp/review-prompt.md
else
    echo "No recent knowledge to inject"
fi
```

**引数**:
1. `since` - 期間指定（git date string）、例: "1 week ago", "2026-01-01"
2. `project_root` - プロジェクトルート（オプション、デフォルト: "."）

**戻り値**:
- マークダウン形式の知識コンテキスト（標準出力）
- 関連情報がない場合は空文字列

**出力形式**:
```markdown
## 最近のfix commitから抽出された知見
以下のバグ修正から得られた知見です。同様のパターンのバグがないか確認してください。
\`\`\`
a1b2c3d fix: CI修正 - フォーマット対応
b2c3d4e fix: タイムアウト処理の追加
\`\`\`

## 最近追加された設計判断
以下の制約を考慮してレビューしてください。
  - 001: Bats並列テスト問題 (docs/decisions/001-test-parallel-jobs-limit.md)
  - 002: マーカー検出の信頼性 (docs/decisions/002-marker-detection-reliability.md)

## 繰り返し発生している失敗パターン
以下のエラータイプが繰り返し発生しています。関連するコードを重点的に確認してください。
\`\`\`
  5 test_failure
  3 ci_timeout
\`\`\`
```

**使用予定箇所**:
- `scripts/improve.sh` - レビューフェーズでのコンテキスト注入
- カスタムレビューワークフロー
- AI支援コードレビューツール

**関連関数**:
- `extract_fix_commits` (lib/knowledge-loop.sh)
- `extract_new_decisions` (lib/knowledge-loop.sh)
- `extract_tracker_failures` (lib/knowledge-loop.sh)

---

## クロスプラットフォーム互換性

### safe_timeout

**定義場所**: `lib/compat.sh`

**説明**: `timeout` コマンドのクロスプラットフォームラッパー。
Linux では `timeout` をそのまま使用し、macOS（`timeout` 未インストール）では
タイムアウトなしで直接コマンドを実行します。

**シグネチャ**:
```bash
safe_timeout <seconds> <command> [args...]
```

**使用例**:
```bash
source lib/compat.sh

# 60秒タイムアウトでコマンド実行
response=$(echo "$prompt" | safe_timeout 60 pi --print "Analyze this")

# テスト実行にタイムアウトを設定（macOSでもLinuxでも動作）
safe_timeout 30 bats test/ 2>&1 || exit_code=$?

# ワークフロー選択（15秒タイムアウト）
result=$(safe_timeout 15 "$pi_command" --print "$selection_prompt")
```

**引数**:
1. `seconds` - タイムアウト秒数（整数）
2. `command` - 実行するコマンド
3. `args...` - コマンドへの引数（オプション）

**戻り値**:
- コマンドの終了コード
- タイムアウト時は `timeout` コマンドの終了コード (124)
- macOS で `timeout` が利用不可の場合はコマンドの終了コード（タイムアウトなし）

**使用箇所**:
- `lib/generate-config.sh` - プロジェクト解析時のAI呼び出し（60秒タイムアウト）
- `lib/workflow-selector.sh` - ワークフロー自動選択のAI呼び出し（15秒タイムアウト）
- `lib/ci-fix/bash.sh` - Batsテスト実行時のタイムアウト制御

**注意事項**:
- macOS標準環境では `timeout` が利用不可のため、タイムアウトなしで実行される
- `brew install coreutils` で `gtimeout` をインストールすることで macOS でもタイムアウトが有効になる（現在は未対応）
- タイムアウトが必須の処理では、macOS環境での動作を考慮する必要がある

**関連コマンド**:
- `timeout(1)` - Linux標準のタイムアウトコマンド
- `gtimeout(1)` - GNU coreutils版（macOSでは `brew install coreutils` で利用可能）

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
   echo "$_CONFIG_LOADED"
   
   # ✅ GOOD: 公開API関数を使用
   value=$(get_config worktree_base_dir)
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
