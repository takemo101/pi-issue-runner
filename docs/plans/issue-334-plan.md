# 実装計画: Issue #334 - Issue取得時にコメントも含める

## 概要

現在、Issue情報取得時に本文（body）のみ取得しているが、コメントも含めてAIに渡すようにする。これにより、Issueへの追加情報や議論がAIに伝わるようになる。

## 影響範囲

### 変更するファイル

1. **lib/github.sh** - Issue情報取得の拡張
2. **lib/config.sh** - コメント関連設定の追加
3. **lib/workflow-prompt.sh** - プロンプトへのコメント追加
4. **scripts/run.sh** - コメント取得の呼び出し追加

### テストファイル

1. **test/lib/github.bats** - 新機能のテスト追加
2. **test/lib/config.bats** - 設定テスト追加

## 実装ステップ

### Step 1: lib/config.sh の拡張

1. デフォルト設定の追加:
   ```bash
   CONFIG_GITHUB_INCLUDE_COMMENTS="${CONFIG_GITHUB_INCLUDE_COMMENTS:-true}"
   CONFIG_GITHUB_MAX_COMMENTS="${CONFIG_GITHUB_MAX_COMMENTS:-10}"
   ```

2. YAMLパース処理の追加（`_parse_config_file`）:
   - `.github.include_comments` の読み込み
   - `.github.max_comments` の読み込み

3. 環境変数上書きの追加（`_apply_env_overrides`）:
   - `PI_RUNNER_GITHUB_INCLUDE_COMMENTS`
   - `PI_RUNNER_GITHUB_MAX_COMMENTS`

4. `get_config` 関数の拡張:
   - `github_include_comments`
   - `github_max_comments`

### Step 2: lib/github.sh の拡張

1. `get_issue` 関数の変更:
   - `--json` フィールドに `comments` を追加

2. 新規関数 `get_issue_comments` の追加:
   ```bash
   get_issue_comments() {
       local issue_number="$1"
       local max_comments="${2:-0}"  # 0 = 無制限
       # gh issue view でコメントを取得してフォーマット
   }
   ```

3. 新規関数 `format_comments_section` の追加:
   - コメントをMarkdown形式でフォーマット
   - 各コメントに投稿者と日時を含める
   - max_comments による制限処理

### Step 3: lib/workflow-prompt.sh の拡張

1. `generate_workflow_prompt` 関数の変更:
   - 引数に `issue_comments` を追加
   - Description の後に `## Comments` セクションを追加

2. `write_workflow_prompt` 関数の変更:
   - コメント引数を追加

### Step 4: scripts/run.sh の拡張

1. コメント取得の追加:
   ```bash
   local issue_comments=""
   if [[ "$(get_config github_include_comments)" == "true" ]]; then
       local max_comments
       max_comments="$(get_config github_max_comments)"
       issue_comments="$(get_issue_comments "$issue_number" "$max_comments")"
   fi
   ```

2. `write_workflow_prompt` 呼び出しにコメントを追加

### Step 5: テストの追加

1. **test/lib/github.bats**:
   - `get_issue_comments` 関数のテスト
   - `format_comments_section` 関数のテスト
   - max_comments 制限のテスト

2. **test/lib/config.bats**:
   - `github_include_comments` 設定のテスト
   - `github_max_comments` 設定のテスト
   - 環境変数上書きのテスト

## 出力形式

### プロンプトへの出力例

```markdown
## Description
（Issue本文）

## Comments

### @username (2024-01-31)
コメント内容...

### @username2 (2024-01-31)
コメント内容...
```

### 設定ファイル例

```yaml
# .pi-runner.yaml
github:
  include_comments: true    # コメントを含める（デフォルト: true）
  max_comments: 10          # 最大コメント数（0 = 無制限）
```

## テスト方針

### ユニットテスト

- 新規関数 (`get_issue_comments`, `format_comments_section`) の単体テスト
- 設定読み込み・取得のテスト
- コメント数制限のテスト
- 空コメントの場合のテスト

### 統合テスト

- モックを使用したEnd-to-Endフロー確認
- 実際のIssueでの動作確認（手動）

## リスクと対策

### リスク1: 大量コメントによるプロンプト肥大化

- **対策**: `max_comments` 設定による制限（デフォルト: 10件）
- 古いコメントではなく最新N件を取得

### リスク2: コメント内の危険なパターン

- **対策**: 既存の `sanitize_issue_body` 関数を各コメントにも適用

### リスク3: APIレートリミット

- **影響**: `gh issue view` は1回の呼び出しでコメントも含まれるため、追加のAPI呼び出しは発生しない
- **対策**: 既存の1回の呼び出しでコメントも取得

### リスク4: 後方互換性

- **対策**: デフォルトで `include_comments: true` とし、無効化もオプションで可能

## 完了条件

- [ ] lib/config.sh にコメント関連設定を追加
- [ ] lib/github.sh に `get_issue_comments` 関数を追加
- [ ] lib/workflow-prompt.sh にコメントセクションを追加
- [ ] scripts/run.sh でコメント取得を呼び出し
- [ ] 全てのテストがパス
- [ ] ShellCheckが警告なくパス
