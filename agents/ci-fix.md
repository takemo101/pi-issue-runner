# CI Fix Agent

GitHub Issue #{{issue_number}} のCI失敗を検出し、自動修正を試行します。

> **重要: 非対話的実行**
> このセッションはバックグラウンドで実行されます。
> **絶対にエディタを開くコマンドを使用しないでください**。
> - `git commit` は必ず `-m` オプションを使用
> - 対話的なプロンプトが出るコマンドは使用しない

> **🚫 禁止事項**
> - **`gh issue close` を絶対に実行しないでください**
> - IssueのCloseはPRマージ時に `Closes #xxx` で自動的に行われます

## コンテキスト

- **Issue番号**: #{{issue_number}}
- **ブランチ**: {{branch_name}}
- **作業ディレクトリ**: {{worktree_path}}
- **PR番号**: {{pr_number}} (if available)

## タスク

### 1. CI状態確認

```bash
# PR番号を特定（環境変数からまたはgh CLIで取得）
PR_NUMBER="${PR_NUMBER:-{{pr_number}}}"
if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr list --head "{{branch_name}}" --json number -q '.[0].number' 2>/dev/null)
fi

# CI状態を確認
echo "Checking CI status for PR #$PR_NUMBER..."
gh pr checks "$PR_NUMBER" 2>/dev/null || echo "No checks found"
```

### 2. CI失敗の検出と自動修正（推奨: ヘルパースクリプト使用）

```bash
# ヘルパースクリプトのパス
HELPER_SCRIPT="./scripts/ci-fix-helper.sh"

# 失敗タイプを検出
FAILURE_TYPE=$("$HELPER_SCRIPT" detect "$PR_NUMBER")
echo "Detected failure type: $FAILURE_TYPE"

# 自動修正を試行
cd "{{worktree_path}}"
if "$HELPER_SCRIPT" fix "$FAILURE_TYPE" "{{worktree_path}}"; then
    echo "✅ Auto-fix successful"
    
    # 変更をコミット＆プッシュ
    git add -A
    git commit -m "fix: CI修正 - ${FAILURE_TYPE}対応

Refs #{{issue_number}}"
    git push
    
    echo "Changes pushed. CI will re-run automatically."
else
    FIX_RESULT=$?
    if [[ $FIX_RESULT -eq 2 ]]; then
        echo "⚠️ AI-based fixing required for $FAILURE_TYPE"
        # 次のセクションに進む
    else
        echo "❌ Auto-fix failed"
        exit 1
    fi
fi
```

### 3. AI修正が必要な場合（テスト/ビルド失敗）

ヘルパースクリプトが自動修正できなかった場合（終了コード2）：

```bash
# 失敗ログを詳細に取得
RUN_ID=$(gh run list --limit 1 --status failure --json databaseId -q '.[0].databaseId' 2>/dev/null)
FAILURE_LOG=$(gh run view "$RUN_ID" --log-failed 2>/dev/null || echo "")

echo "Analyzing failure logs..."
echo "$FAILURE_LOG" | head -50
```

**手動修正ステップ**:
1. エラーログを詳細に分析
2. 失敗しているファイルを特定
3. ソースコードを修正
4. ローカルで検証:
   ```bash
   cargo build
   cargo test --lib
   ```
5. 修正をコミット・プッシュ:
   ```bash
   git add -A
   git commit -m "fix: CI修正 - テスト/ビルド対応

Refs #{{issue_number}}"
   git push
   ```

### 4. 代替方法: インラインスクリプト（後方互換性）

ヘルパースクリプトが使用できない環境では、以下を使用：

```bash
cd "{{worktree_path}}"

# フォーマット修正
cargo fmt --all 2>&1 && echo "Format fixed" || true

# Clippy修正
cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features 2>&1 && echo "Lint fixed" || true

# 変更を確認
if git diff --quiet && git diff --cached --quiet; then
    echo "No changes to commit"
else
    git add -A
    git commit -m "fix: CI修正 - フォーマット・Lint対応

Refs #{{issue_number}}"
    git push
fi
```

### 5. CI再実行待機

```bash
echo "Waiting for CI to complete..."
sleep 30

# ポーリングでCI状態を確認（最大10分）
for i in {1..20}; do
    STATUS=$(gh pr checks "$PR_NUMBER" --json state -q '.[0].state' 2>/dev/null || echo "PENDING")
    
    if [[ "$STATUS" == "SUCCESS" ]]; then
        echo "✅ CI passed!"
        exit 0
    elif [[ "$STATUS" == "FAILURE" ]]; then
        echo "❌ CI failed again"
        # リトライ回数をチェックし、最大回数未満なら再度修正
        exit 1
    fi
    
    echo "CI status: $STATUS (waiting...)"
    sleep 30
done

echo "⚠️ CI wait timeout"
exit 1
```

## 完了条件

- [ ] CI失敗タイプを特定した
- [ ] 自動修正を実行した
- [ ] 修正をコミット・プッシュした
- [ ] CI再実行の結果を確認した

## 完了報告

CI修正が正常に完了し、CIがパスした場合は、以下の形式で完了マーカーを出力してください：

- プレフィックス: `###TASK`
- 中間部: `_COMPLETE_`
- Issue番号: `{{issue_number}}`
- サフィックス: `###`

上記を連結して**行頭から直接**1行で出力してください（コードブロックやインデントは使用しないこと）。
これにより、CI修正フローが完了します。

> **重要**: このマーカーは外部プロセス（`watch-session.sh`）によって監視されています。
> マーカーは必ず行頭から出力してください。インデントやコードブロック内での出力は検出されません。

## エスカレーション条件

以下の場合はエスカレーション（Draft化＆手動対応）してください：

1. **修正が不明確** - どのファイルをどう修正すべきか判断できない
2. **3回リトライ後も失敗** - 同じ失敗が繰り返される
3. **新しいタイプのエラー** - 対応パターンにないエラー

エスカレーション時は以下を実行：

```bash
# PRをDraft化
gh pr ready "$PR_NUMBER" --undo 2>/dev/null || true

# コメント追加
gh pr comment "$PR_NUMBER" --body "## 🤖 CI自動修正: エスカレーション

自動修正が困難なため手動対応が必要です。

失敗ログ:
\`\`\`
$(gh run view --log-failed 2>/dev/null | head -50)
\`\`\`
"
```

## エラー報告

回復不能なエラーが発生した場合は、以下の形式でエラーマーカーを出力してください：

- プレフィックス: `###TASK`
- 中間部: `_ERROR_`
- Issue番号: `{{issue_number}}`
- サフィックス: `###`

上記を連結して**行頭から直接**1行で出力し、次の行にエラーの説明を記載してください。

> **重要**: マーカーは必ず行頭から出力してください。インデントやコードブロック内での出力は検出されません。
