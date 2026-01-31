# Issue #189 実装計画書

## 概要

`improve.sh` のIssue番号取得方式を、出力マーカー抽出からGitHub API方式に変更する。

## 背景

現在のマーカー抽出方式（`###CREATED_ISSUES###`）には以下の問題がある：
1. teeのバッファリング問題
2. ANSIエスケープコード混入
3. PTY問題（表示幅）
4. 出力タイミングの問題

## 影響範囲

### 変更が必要なファイル

1. **scripts/improve.sh** - メイン変更対象
   - `review_and_create_issues()` 関数を大幅リファクタリング
   - マーカー抽出ロジックを削除
   - GitHub API呼び出しを追加
   
2. **lib/github.sh** - 新機能追加
   - `get_issues_created_after()` 関数を追加（開始時刻以降のIssue取得）
   
3. **test/improve_test.sh** - テスト更新
   - マーカー抽出テストを削除
   - GitHub API方式のテストを追加

### 変更なし

- `lib/config.sh`, `lib/log.sh`, `lib/status.sh` - 変更不要
- 他のスクリプト - 変更不要

## 実装ステップ

### Step 1: lib/github.sh に新機能追加

```bash
# 開始時刻以降に作成されたIssueを取得
get_issues_created_after() {
    local start_time="$1"
    local max_issues="${2:-20}"
    
    gh issue list --state open --author "@me" --limit "$max_issues" --json number,createdAt \
        | jq -r --arg start "$start_time" '.[] | select(.createdAt >= $start) | .number'
}
```

### Step 2: improve.sh の review_and_create_issues() を変更

**Before:**
```bash
# パイプでteeに接続してマーカー抽出
"$pi_command" --message "$review_prompt" 2>&1 | tee "$output_file"
# マーカーからIssue番号を抽出
sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file"
```

**After:**
```bash
# 開始時刻を記録
start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# piを直接実行（パイプなし）
"$pi_command" --message "$review_prompt"

# GitHub APIでIssue取得
get_issues_created_after "$start_time" "$max_issues"
```

### Step 3: プロンプトを簡素化

**Before:**
```
作成したIssue番号を以下の形式で最後に必ず出力してください:
###CREATED_ISSUES###
<Issue番号を1行ずつ、数字のみ>
###END_ISSUES###
```

**After:**
```
発見した問題からGitHub Issueを作成してください。
最大N件までのIssueを作成してください。
```

### Step 4: テスト更新

- マーカー抽出テスト（`extract_issue_numbers`関連）を削除
- GitHub API方式のモックテストを追加

## テスト方針

### 単体テスト

1. **lib/github.sh のテスト**
   - `get_issues_created_after()` の動作確認
   - 時刻フィルタリングの正確性

2. **improve.sh のテスト**
   - オプション処理（既存テスト維持）
   - スクリプト構造（既存テスト維持）
   - マーカー関連テスト削除

### 手動テスト

```bash
# dry-runで動作確認
./scripts/improve.sh --dry-run

# review-onlyで動作確認
./scripts/improve.sh --review-only

# 実際のIssue作成テスト
./scripts/improve.sh --max-iterations 1 --max-issues 1
```

## リスクと対策

| リスク | 対策 |
|--------|------|
| ネットワーク依存 | GitHub APIエラー時の適切なハンドリング |
| 他ユーザーの同時Issue作成 | `--author @me` で自分のIssueのみ取得 |
| 時刻ずれ | UTC時刻を使用（`date -u`） |
| API rate limit | 20件に制限、必要なら増加可能 |

## 見積もり

- lib/github.sh 変更: 15分
- improve.sh 変更: 30分
- テスト更新: 30分
- 手動テスト: 15分
- **合計: 1.5時間**

## 完了条件

- [x] 実装計画書作成
- [ ] lib/github.sh に `get_issues_created_after()` 追加
- [ ] improve.sh をGitHub API方式に変更
- [ ] マーカー関連コードを削除
- [ ] テストを更新
- [ ] 全テストがパス
- [ ] 手動テストで動作確認
