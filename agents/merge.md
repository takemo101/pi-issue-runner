# Merge Agent

GitHub Issue #{{issue_number}} のPRを作成し、マージします。

> **重要: 非対話的実行**
> このセッションはバックグラウンドで実行されます。
> **絶対にエディタを開くコマンドを使用しないでください**。
> - `git commit` は必ず `-m` オプションを使用
> - `git merge` は `--no-edit` オプションを使用
> - `gh pr create` は必ず `--body` オプションを使用
> - 対話的なプロンプトが出るコマンドは使用しない

> **🚫 禁止事項**
> - **`gh issue close` を絶対に実行しないでください**
> - IssueのCloseはPRマージ時に `Closes #{{issue_number}}` で**自動的に**行われます
> - PRのbodyに必ず `Closes #{{issue_number}}` を含めてください

## コンテキスト

- **Issue番号**: #{{issue_number}}
- **タイトル**: {{issue_title}}
- **ブランチ**: {{branch_name}}
- **作業ディレクトリ**: {{worktree_path}}

## タスク

### 1. プッシュ
```bash
git push -u origin {{branch_name}}
```

### 2. PR作成
```bash
gh pr create \
  --title "<type>: {{issue_title}}" \
  --body "## Summary
Closes #{{issue_number}}

## Changes
- <変更内容を記載>

## Testing
- <テスト内容を記載>"
```

### 3. PRのマージ

CIの状態を確認してからマージします。CIが失敗した場合は自動修正を試行します：

```bash
# PR番号を取得
PR_NUMBER=$(gh pr list --head "{{branch_name}}" --json number -q '.[0].number' 2>/dev/null)

# CIが設定されているかチェック
if gh pr checks "$PR_NUMBER" 2>/dev/null | grep -q .; then
  echo "CI checks detected. Waiting for completion (timeout: 10 minutes)..."
  
  # CI完了を待機
  if timeout 600 gh pr checks --watch; then
    echo "✅ CI passed. Merging PR..."
    gh pr merge --merge --delete-branch
  else
    echo "⚠️ CI failed. Attempting auto-fix..."
    
    # ===== CI自動修正フロー =====
    cd "{{worktree_path}}"
    
    # リトライ回数を追跡（ファイルベース）
    RETRY_FILE="/tmp/pi-runner-ci-retry-{{issue_number}}"
    RETRY_COUNT=$(cat "$RETRY_FILE" 2>/dev/null || echo "0")
    MAX_RETRIES=3
    
    if [[ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]]; then
      echo "❌ Maximum retry count ($MAX_RETRIES) reached. Escalating to manual handling..."
      
      # PRをDraft化
      gh pr ready "$PR_NUMBER" --undo 2>/dev/null || true
      
      # 失敗ログをコメント追加
      FAILED_LOGS=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' | xargs -I {} gh run view {} --log-failed 2>/dev/null | head -100)
      gh pr comment "$PR_NUMBER" --body "## 🤖 CI自動修正: エスカレーション

CI失敗の自動修正が最大試行回数に達しました。手動対応が必要です。

### 失敗ログ（要約）
\`\`\`
$FAILED_LOGS
\`\`\`

### 対応が必要な項目
- [ ] 失敗ログの詳細確認
- [ ] ソースコードの修正
- [ ] CIの再実行
" 2>/dev/null || true
      
      echo "###TASK_ERROR_{{issue_number}}###"
      echo "CI failed after $MAX_RETRIES auto-fix attempts. PR marked as draft for manual handling."
      exit 1
    fi
    
    # 失敗タイプを特定
    echo "Analyzing CI failure type..."
    RUN_ID=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' 2>/dev/null)
    FAILED_LOGS=$(gh run view "$RUN_ID" --log-failed 2>/dev/null || echo "")
    
    # 失敗タイプを検出
    if echo "$FAILED_LOGS" | grep -qE '(Diff in|would have been reformatted|fmt check failed)'; then
      FAILURE_TYPE="format"
    elif echo "$FAILED_LOGS" | grep -qE '(warning:|clippy::|error: could not compile.*clippy)'; then
      FAILURE_TYPE="lint"
    elif echo "$FAILED_LOGS" | grep -qE '(FAILED|test result: FAILED|failures:)'; then
      FAILURE_TYPE="test"
    elif echo "$FAILED_LOGS" | grep -qE '(error\[E|cannot find|unresolved import)'; then
      FAILURE_TYPE="build"
    else
      FAILURE_TYPE="unknown"
    fi
    
    echo "Detected failure type: $FAILURE_TYPE"
    
    # 自動修正を試行（プロジェクト非依存）
    # ci-fix-helper.sh を使用してCI修正を実行
    FIX_APPLIED=false
    
    echo "🛠️ Attempting auto-fix for failure type: $FAILURE_TYPE"
    
    # ci-fix-helper.sh のパスを解決
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CI_FIX_HELPER="$SCRIPT_DIR/scripts/ci-fix-helper.sh"
    
    if [[ -f "$CI_FIX_HELPER" ]]; then
      # ci-fix-helper.sh を使用（プロジェクトタイプを自動検出）
      if "$CI_FIX_HELPER" fix "$FAILURE_TYPE" "{{worktree_path}}" 2>&1; then
        # 修正が適用された場合、コミット
        if [[ -n "$(git status --porcelain)" ]]; then
          git add -A
          git commit -m "fix: CI修正 - $FAILURE_TYPE 対応

Refs #{{issue_number}}" || true
          FIX_APPLIED=true
          echo "✅ Auto-fix applied successfully"
        else
          echo "ℹ️ No changes to commit"
        fi
      else
        echo "⚠️ Auto-fix failed or not available for this failure type"
        # test/buildの場合はAI修正が必要
        if [[ "$FAILURE_TYPE" == "test" ]] || [[ "$FAILURE_TYPE" == "build" ]]; then
          echo "🤖 AI-based fixing required for $FAILURE_TYPE failure..."
          # このケースはAIによる修正が必要
        fi
      fi
    else
      echo "⚠️ ci-fix-helper.sh not found. Falling back to legacy method..."
      # フォールバック: 旧来の方法（後方互換性のため残す）
      case "$FAILURE_TYPE" in
        "format")
          echo "🛠️ Attempting format fix..."
          if command -v cargo &> /dev/null && cargo fmt --all 2>/dev/null; then
            git add -A
            git commit -m "fix: CI修正 - フォーマット対応

Refs #{{issue_number}}" || true
            FIX_APPLIED=true
          fi
          ;;
        "lint")
          echo "🛠️ Attempting lint fix..."
          if command -v cargo &> /dev/null && cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features 2>/dev/null; then
            git add -A
            git commit -m "fix: CI修正 - Lint対応

Refs #{{issue_number}}" || true
            FIX_APPLIED=true
          fi
          ;;
        "test"|"build")
          echo "🤖 AI-based fixing required for $FAILURE_TYPE failure..."
          ;;
      esac
    fi
    
    if [[ "$FIX_APPLIED" == "true" ]]; then
      # リトライ回数をインクリメント
      echo $((RETRY_COUNT + 1)) > "$RETRY_FILE"
      
      # プッシュしてCI再実行
      echo "Pushing fix and re-running CI..."
      git push
      
      # CI再実行を待機
      if timeout 600 gh pr checks --watch; then
        echo "✅ CI passed after auto-fix. Merging PR..."
        rm -f "$RETRY_FILE"  # 成功したのでリトライカウントをリセット
        gh pr merge --merge --delete-branch
      else
        echo "❌ CI still failing after auto-fix. Will retry..."
        echo "###TASK_ERROR_{{issue_number}}###"
        echo "CI failed after auto-fix attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
        exit 1
      fi
    else
      # 自動修正不可 - エスカレーション
      echo "❌ Auto-fix not available for this failure type. Escalating..."
      
      gh pr ready "$PR_NUMBER" --undo 2>/dev/null || true
      gh pr comment "$PR_NUMBER" --body "## 🤖 CI自動修正: エスカレーション

自動修正が困難な失敗タイプ（$FAILURE_TYPE）のため、手動対応が必要です。

失敗ログ:
\`\`\`
$FAILED_LOGS
\`\`\`
" 2>/dev/null || true
      
      echo "###TASK_ERROR_{{issue_number}}###"
      echo "CI failure type '$FAILURE_TYPE' requires manual fixing."
      exit 1
    fi
  fi
else
  # CIが設定されていない場合：スキップしてマージ
  echo "No CI checks detected. Merging PR..."
  gh pr merge --merge --delete-branch
fi
```

### 4. クリーンアップ

> **Note**: 以下のクリーンアップは `watch-session.sh` により自動的に行われます：
> - Worktree の削除
> - 計画書（`{{plans_dir}}/issue-{{issue_number}}-plan.md`）の削除
> 
> 手動でクリーンアップが必要な場合は `scripts/cleanup.sh` を使用してください。

## コミットタイプ

- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメント
- `refactor`: リファクタリング
- `test`: テスト追加
- `chore`: メンテナンス

## 完了条件

- [ ] コードがリモートにプッシュされた
- [ ] PRが作成された
- [ ] CIがパスした
- [ ] PRがマージされた
- [ ] リモートブランチが削除された

## コンテキスト保存（オプション）

タスク完了時または重要な学びがあった場合、以下のファイルを更新してください：

### Issue固有の学び
`.worktrees/.context/issues/{{issue_number}}.md`

### 保存すべき内容
- 試したアプローチと結果
- 発見した問題と解決策
- 今後の実行者への注意点

**注意**: これは推奨事項です。必須ではありません。

## 完了報告

全てのタスクが正常に完了した場合は、以下の形式で完了マーカーを出力してください：

- プレフィックス: `###TASK`
- 中間部: `_COMPLETE_`
- Issue番号: `{{issue_number}}`
- サフィックス: `###`

上記を連結して**行頭から直接**1行で出力してください（コードブロックやインデントは使用しないこと）。
これにより、worktreeとセッションが自動的にクリーンアップされます。

> **重要**: このマーカーは外部プロセス（`watch-session.sh`）によって監視されています。
> マーカーは必ず行頭から出力してください。インデントやコードブロック内での出力は検出されません。

## エラー報告

回復不能なエラーが発生した場合は、以下の形式でエラーマーカーを出力してください：

- プレフィックス: `###TASK`
- 中間部: `_ERROR_`
- Issue番号: `{{issue_number}}`
- サフィックス: `###`

上記を連結して**行頭から直接**1行で出力し、次の行にエラーの説明を記載してください。
（例: PRマージに失敗しました。CIが失敗しています。）

> **重要**: このマーカーは外部プロセス（`watch-session.sh`）によって監視されています。
> マーカーは必ず行頭から出力してください。インデントやコードブロック内での出力は検出されません。

これにより、ユーザーに通知が送信され、手動での対応が可能になります。

