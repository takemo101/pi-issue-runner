# 状態管理

## 概要

Pi Issue Runnerの状態管理システムは、タスクの実行状態をJSONファイルで永続化し、プロセス再起動後も状態を復元できるようにします。

## データ永続化

### ストレージ構造

```
.worktrees/
├── .status/                  # ステータスディレクトリ
│   ├── 42.json               # Issue #42のステータス
│   ├── 43.json               # Issue #43のステータス
│   └── 44.json               # Issue #44のステータス
├── issue-42-feature/         # Issue #42のworktree
├── issue-43-bugfix/          # Issue #43のworktree
└── issue-44-refactor/        # Issue #44のworktree
```

### ステータスファイルフォーマット

**ファイル**: `.worktrees/.status/{issue_number}.json`

**形式**:
```json
{
  "issue": 42,
  "status": "running",
  "session": "pi-issue-42",
  "timestamp": "2024-01-30T09:00:00Z"
}
```

**エラー時**:
```json
{
  "issue": 42,
  "status": "error",
  "session": "pi-issue-42",
  "error_message": "テストが失敗しました",
  "timestamp": "2024-01-30T09:05:00Z"
}
```

## 状態管理API

### lib/status.sh

#### 基本操作

```bash
# ライブラリ読み込み
source lib/status.sh

# ステータスを保存
save_status 42 "running" "pi-issue-42"
save_status 42 "complete" "pi-issue-42"
save_status 42 "error" "pi-issue-42" "エラーメッセージ"

# 簡易版（セッション名を自動生成）
set_status 42 "running"
set_status 42 "complete"
set_status 42 "error" "エラーメッセージ"
```

#### ステータス取得

```bash
# ステータス値を取得
status="$(get_status 42)"
# → "running", "complete", "error", "unknown"

# 完全なJSONを取得
json="$(load_status 42)"
# → {"issue":42,"status":"running",...}

# エラーメッセージを取得
error="$(get_error_message 42)"
```

#### 一覧操作

```bash
# 全ステータスを一覧
list_all_statuses
# 出力:
# 42	running
# 43	complete
# 44	error

# 特定ステータスのIssueを取得
list_issues_by_status "running"
# 出力:
# 42

list_issues_by_status "complete"
# 出力:
# 43
```

#### クリーンアップ

```bash
# ステータスファイルを削除
remove_status 42

# 孤立したステータスファイルを検出
find_orphaned_statuses
# → 対応するworktreeが存在しないステータスファイルのIssue番号
```

## 実装詳細

### JSON構築

jqが利用可能な場合はjqを使用、なければ純粋なBashでフォールバック:

```bash
# lib/status.sh

# jqを使用（推奨）
build_json_with_jq() {
    local issue_number="$1"
    local status="$2"
    local session_name="$3"
    local timestamp="$4"
    local error_message="${5:-}"
    
    if [[ -n "$error_message" ]]; then
        jq -n \
            --argjson issue "$issue_number" \
            --arg status "$status" \
            --arg session "$session_name" \
            --arg error "$error_message" \
            --arg timestamp "$timestamp" \
            '{issue: $issue, status: $status, session: $session, error_message: $error, timestamp: $timestamp}'
    else
        jq -n \
            --argjson issue "$issue_number" \
            --arg status "$status" \
            --arg session "$session_name" \
            --arg timestamp "$timestamp" \
            '{issue: $issue, status: $status, session: $session, timestamp: $timestamp}'
    fi
}

# Bashフォールバック（jqなし）
build_json_fallback() {
    local issue_number="$1"
    local status="$2"
    local session_name="$3"
    local timestamp="$4"
    local error_message="${5:-}"
    
    # JSONエスケープ処理
    local escaped_status escaped_session escaped_timestamp
    escaped_status="$(json_escape "$status")"
    escaped_session="$(json_escape "$session_name")"
    escaped_timestamp="$(json_escape "$timestamp")"
    
    if [[ -n "$error_message" ]]; then
        local escaped_message
        escaped_message="$(json_escape "$error_message")"
        cat << EOF
{
  "issue": $issue_number,
  "status": "$escaped_status",
  "session": "$escaped_session",
  "error_message": "$escaped_message",
  "timestamp": "$escaped_timestamp"
}
EOF
    else
        cat << EOF
{
  "issue": $issue_number,
  "status": "$escaped_status",
  "session": "$escaped_session",
  "timestamp": "$escaped_timestamp"
}
EOF
    fi
}
```

### JSONエスケープ

```bash
# 特殊文字のエスケープ
json_escape() {
    local str="$1"
    # バックスラッシュを最初にエスケープ（順序重要）
    str="${str//\\/\\\\}"
    # ダブルクォート
    str="${str//\"/\\\"}"
    # タブ
    str="${str//$'\t'/\\t}"
    # 改行
    str="${str//$'\n'/\\n}"
    # キャリッジリターン
    str="${str//$'\r'/\\r}"
    echo "$str"
}
```

### ステータス保存

```bash
save_status() {
    local issue_number="$1"
    local status="$2"
    local session_name="${3:-}"
    local error_message="${4:-}"
    
    # ディレクトリ初期化
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local status_file="${status_dir}/${issue_number}.json"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    # JSONを構築
    local json
    if command -v jq &>/dev/null; then
        json="$(build_json_with_jq "$issue_number" "$status" "$session_name" "$timestamp" "$error_message")"
    else
        json="$(build_json_fallback "$issue_number" "$status" "$session_name" "$timestamp" "$error_message")"
    fi
    
    echo "$json" > "$status_file"
    log_debug "Saved status for issue #$issue_number: $status"
}
```

## 状態遷移

### タスクライフサイクル

```
    run.sh 開始
         │
         ▼
    ┌─────────┐
    │ running │ ←── save_status(issue, "running", session)
    └────┬────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌───────┐
│complete│ │ error │
└───┬────┘ └───┬───┘
    │          │
    │          └── save_status(issue, "error", session, message)
    │
    └── save_status(issue, "complete", session)
```

### 状態遷移のタイミング

| タイミング | 状態 | トリガー |
|-----------|------|---------|
| セッション作成時 | `running` | `run.sh` がセッション作成後 |
| 完了マーカー検出 | `complete` | `watch-session.sh` がマーカーを検出 |
| エラーマーカー検出 | `error` | `watch-session.sh` がエラーを検出 |
| セッション異常終了 | `error` | `watch-session.sh` がセッション消失を検出 |

## 監視と復旧

### watch-session.sh による監視

```bash
# scripts/watch-session.sh の状態更新ロジック

# 完了マーカー検出時
if echo "$output" | grep -q "###TASK_COMPLETE_${issue_number}###"; then
    set_status "$issue_number" "complete"
    cleanup_and_exit
fi

# エラーマーカー検出時
if echo "$output" | grep -qE "###TASK_ERROR_${issue_number}###"; then
    local error_msg
    error_msg="$(extract_error_message "$output")"
    set_status "$issue_number" "error" "$error_msg"
    cleanup_and_exit
fi

# セッション消失時
if ! session_exists "$session_name"; then
    set_status "$issue_number" "error" "Session unexpectedly terminated"
    cleanup_and_exit
fi
```

### 孤立リソースの検出

worktreeが存在しないのにステータスファイルが残っている場合を検出:

```bash
find_orphaned_statuses() {
    local status_dir
    status_dir="$(get_status_dir)"
    
    if [[ ! -d "$status_dir" ]]; then
        return 0
    fi
    
    local worktree_base
    worktree_base="$(get_config worktree_base_dir)"
    
    for status_file in "$status_dir"/*.json; do
        [[ -f "$status_file" ]] || continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        
        # 対応するworktreeが存在するか確認
        local has_worktree=false
        for dir in "$worktree_base"/issue-"${issue_number}"-*; do
            if [[ -d "$dir" ]]; then
                has_worktree=true
                break
            fi
        done
        
        # worktreeが存在しない場合は孤立
        if [[ "$has_worktree" == "false" ]]; then
            echo "$issue_number"
        fi
    done
}
```

## scripts/status.sh

ステータス確認用のユーザー向けスクリプト:

```bash
# 使用例
./scripts/status.sh 42

# 出力例（正常）
Issue #42: complete
Session: pi-issue-42
Timestamp: 2024-01-30T09:05:00Z

# 出力例（エラー）
Issue #42: error
Session: pi-issue-42
Error: テストが失敗しました
Timestamp: 2024-01-30T09:05:00Z

# 出力例（実行中）
Issue #42: running
Session: pi-issue-42
Timestamp: 2024-01-30T09:00:00Z
```

## クリーンアップ

### ステータスファイルの削除

```bash
# 特定のIssueのステータスを削除
remove_status 42

# クリーンアップスクリプトから呼び出し
# scripts/cleanup.sh
cleanup_issue() {
    local issue_number="$1"
    
    # worktreeを削除
    local worktree
    if worktree="$(find_worktree_by_issue "$issue_number")"; then
        remove_worktree "$worktree" true
    fi
    
    # ステータスファイルを削除
    remove_status "$issue_number"
    
    log_info "Cleaned up issue #$issue_number"
}
```

### 孤立リソースのクリーンアップ

```bash
# 孤立したステータスファイルをクリーンアップ
for issue in $(find_orphaned_statuses); do
    log_info "Removing orphaned status: $issue"
    remove_status "$issue"
done
```

## ベストプラクティス

1. **状態の一貫性**
   - 状態変更は必ず `save_status()` または `set_status()` を通じて行う
   - 直接ファイルを編集しない

2. **エラー情報の保存**
   - エラー時は必ずメッセージを含める
   - 後からデバッグできるよう詳細な情報を記録

3. **定期的なクリーンアップ**
   - 完了したタスクのステータスは定期的に削除
   - `find_orphaned_statuses()` で孤立を検出

4. **jqの活用**
   - jqがインストールされている環境では自動的に使用
   - より堅牢なJSON処理が可能

5. **タイムスタンプの活用**
   - UTCフォーマットで記録
   - デバッグや監査に活用
