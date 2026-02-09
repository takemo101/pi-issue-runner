# セキュリティ

pi-issue-runnerは、GitHub Issueの内容を安全に処理するためのセキュリティ機能を備えています。

## 概要

GitHub Issueの本文は外部からの入力であり、悪意のあるコードが含まれる可能性があります。pi-issue-runnerは、プロンプトインジェクション攻撃やシェルコマンドインジェクションを防ぐため、Issue本文のサニタイズ機能を実装しています。

## 脅威モデル

### プロンプトインジェクション

Issue本文にシェルで解釈される特殊なパターンが含まれている場合、意図しないコマンドが実行される可能性があります。

**例:**
```
Issue本文に $(rm -rf /) が含まれている場合、
展開されると危険なコマンドが実行される可能性がある
```

## セキュリティ機能

### 1. 危険なパターンの検出

`has_dangerous_patterns()` 関数は、以下の危険なパターンを検出します：

| パターン | 説明 | 例 |
|----------|------|-----|
| `$(...)` | コマンド置換 | `$(whoami)` |
| `` `...` `` | バッククォートによるコマンド置換 | `` `whoami` `` |
| `${...}` | 変数展開 | `${HOME}` |
| `<(...)` | プロセス置換（入力） | `<(cat file)` |
| `>(...)` | プロセス置換（出力） | `>(gzip)` |
| `$((...))` | 算術展開 | `$((1+1))` |

危険なパターンが検出された場合、ログに警告が出力されます。

### 2. Issue本文のサニタイズ

`sanitize_issue_body()` 関数は、危険なパターンをエスケープして安全な形式に変換します：

| 元のパターン | 変換後 |
|-------------|--------|
| `$(` | `\$(` |
| `` ` `` | `` \` `` |
| `${` | `\${` |
| `<(` | `\ <(` |
| `>(` | `\ >(` |
| `$((` | `\$((` |

これにより、Issue本文がシェルやテンプレートエンジンで処理される際に、特殊文字として解釈されることを防ぎます。

## 実装詳細

セキュリティ機能は `lib/github.sh` に実装されています。

### has_dangerous_patterns()

```bash
# 使用例
if has_dangerous_patterns "$issue_body"; then
    echo "危険なパターンが検出されました"
fi
```

**戻り値:**
- `0`: 危険なパターンあり（Bash規約でtrue）
- `1`: 安全（危険なパターンなし）

### sanitize_issue_body()

```bash
# 使用例
sanitized_body=$(sanitize_issue_body "$raw_body")
```

**処理フロー:**
1. 入力テキストを受け取る
2. 危険なパターンを検出してログに警告
3. 各パターンをエスケープ文字でエスケープ
4. サニタイズされたテキストを返す

## 使用箇所

サニタイズ機能は以下の場面で使用されます：

- **エージェントテンプレートの展開時**: Issue本文をテンプレート変数として使用する前にサニタイズ
- **プロンプト生成時**: `.pi-prompt.md` ファイルにIssue情報を埋め込む際にサニタイズ

## ベストプラクティス

### ユーザー向け

1. **Issue本文を信頼しない**: 外部からの入力は常に検証・サニタイズする
2. **ログを確認する**: 危険なパターンが検出された場合、警告ログが出力されます

### 開発者向け

1. **Issue本文を直接使用しない**: 必ず `sanitize_issue_body()` を通してから使用する
2. **新しいパターンの追加**: 新たな危険パターンを発見した場合は `_DANGEROUS_PATTERNS` 配列と検出・サニタイズ関数を更新する

## 制限事項

現在のサニタイズ機能は以下のパターンを対象としています：

- シェルのコマンド置換：`$(...)`, `` `...` ``
- シェルの変数展開：`${...}`
- プロセス置換：`<(...)`, `>(...)`
- 算術展開：`$((...))`

以下のパターンは対象外です（必要に応じて拡張可能）：

- ワイルドカード展開（`*`, `?`）
- チルダ展開（`~`, `~user`）

## コマンド実行のセキュリティ

本プロジェクトでは、以下の箇所でシェルコマンドを動的に実行しています。

### 使用箇所一覧

| ファイル | 関数 | 用途 | リスク |
|----------|------|------|--------|
| `lib/hooks.sh` | `_execute_hook()` | インラインhookコマンドの実行 | 🟢 低（セキュリティ対策済み） |
| `scripts/watch-session.sh` | `handle_error()` | シェルオプションの復元（eval使用） | 🟢 低 |
| `scripts/watch-session.sh` | `handle_complete()` | シェルオプションの復元（eval使用） | 🟢 低 |

### lib/hooks.sh でのコマンド実行（リスク：🟢 低）

**用途**: インラインhookコマンド（`.pi-runner.yaml` に記述された文字列コマンド）を実行するために使用。

```bash
# lib/hooks.sh:_execute_hook()
_execute_hook() {
    local hook="$1"
    ...
    # インラインコマンドの場合: 明示的許可が必要
    if [[ "${PI_RUNNER_HOOKS_ALLOW_INLINE:-false}" != "true" ]]; then
        log_warn "Inline hook commands are disabled for security."
        return 0
    fi
    ...
    # bash -c を使用（eval は使用しない）
    # 環境変数は run_hook で設定済み
    bash -c "$hook"
}
```

**セキュリティ対策**:
- `eval` の代わりに `bash -c` を使用（Issue #875で修正）
- テンプレート変数（`{{...}}`）は非推奨、環境変数（`$PI_*`）を使用
- 環境変数経由で渡される値は文字列として安全に処理される
- デフォルトでインラインhookは拒否される
- `PI_RUNNER_HOOKS_ALLOW_INLINE=true` を設定した場合のみ実行可能
- ファイルパスhookは常に許可される

**環境変数の使用例**:
```yaml
# 安全：環境変数を使用
hooks:
  on_success: echo "Issue #$PI_ISSUE_NUMBER completed"

# 非推奨：テンプレート変数（コマンドインジェクションのリスク）
# on_success: echo "Issue #{{issue_number}} completed"
```

**環境変数のサニタイズ**:

バージョン 0.5.0 以降、ユーザー由来の環境変数（`PI_ISSUE_TITLE`, `PI_ERROR_MESSAGE`）に含まれる制御文字は自動的に除去されます。これにより、Issueタイトルやエラーメッセージに含まれる改行文字、タブ、ヌル文字等が `bash -c` 内で意図しない動作を引き起こすことを防ぎます。

| 環境変数 | サニタイズ | 理由 |
|----------|-----------|------|
| `PI_ISSUE_TITLE` | ✅ あり | ユーザー由来の入力（Issue本文から） |
| `PI_ERROR_MESSAGE` | ✅ あり | ユーザー由来の入力（エラーメッセージに含まれる可能性） |
| `PI_ISSUE_NUMBER` | ❌ なし | 数値のみ |
| `PI_SESSION_NAME` | ❌ なし | 内部生成（安全な文字のみ） |
| `PI_BRANCH_NAME` | ❌ なし | Git制約により安全な文字のみ |

詳細は[Hook機能ドキュメント](./hooks.md#マイグレーションガイド)を参照してください。

### scripts/watch-session.sh でのeval（リスク：🟢 低）

**用途**: `set +e` で一時的にエラーモードを解除した後、元のシェルオプションに戻すために使用。

```bash
# scripts/watch-session.sh:handle_error(), handle_complete()
local old_opts
old_opts="$(set +o)"
set +e
...
# 処理後に復元
eval "$old_opts"
```

**リスク**: 低
- 外部入力を含まない（`set +o` の出力のみ）
- シェルの内部状態の復元のみ
- コマンドインジェクションの可能性なし

**背景**: Bashでは `set -e` の状態を変数に保存して復元する標準的な方法がないため、`eval` を使用しています。

### 推奨事項

1. **hook設定の確認**: 新しいリポジトリで作業する前に `.pi-runner.yaml` の `hooks` セクションを確認
2. **信頼できるソースのみ**: 不明なリポジトリのhook設定は実行前に必ず内容を確認
3. **最小権限の原則**: hook内では必要最小限の操作のみを行う

詳細は次のセクション「[Hook機能のセキュリティリスク](#hook機能のセキュリティリスク)」を参照してください。

## Hook機能のセキュリティリスク

### インラインhookの制御

バージョン 0.3.0 以降、セキュリティ強化のためインラインhookコマンドはデフォルトで無効化されています。

#### デフォルト動作

インラインhookコマンド（`.pi-runner.yaml` に直接記述されたコマンド文字列）は、デフォルトで実行が拒否されます。代わりに警告メッセージが表示されます：

```
[WARN] Inline hook commands are disabled for security.
[WARN] To enable, set: export PI_RUNNER_HOOKS_ALLOW_INLINE=true
```

ファイルパスで指定されたhookスクリプトは、環境変数の設定に関係なく常に実行されます。

#### 有効化方法

インラインhookを使用する場合は、以下のいずれかの方法で有効化してください：

方法1: `.pi-runner.yaml` で設定（推奨）

```yaml
hooks:
  allow_inline: true
  on_success: |
    echo "Issue #$PI_ISSUE_NUMBER completed"
```

方法2: 環境変数で設定

```bash
export PI_RUNNER_HOOKS_ALLOW_INLINE=true
./scripts/run.sh 42
```

または、シェルの設定ファイルに追加：

```bash
# ~/.bashrc または ~/.zshrc
export PI_RUNNER_HOOKS_ALLOW_INLINE=true
```

#### 推奨事項

1. **ファイルベースのhookを使用**: インラインコマンドの代わりにスクリプトファイルを使用することを強く推奨します
2. **信頼できるリポジトリのみで有効化**: 環境変数は信頼できるプロジェクトでのみ設定してください
3. **プロジェクトごとの設定**: グローバルに設定せず、必要なプロジェクトでのみ一時的に有効化してください
4. **設定ファイルの確認**: 新しいリポジトリで作業する前に `.pi-runner.yaml` の内容を確認してください

### コマンド実行とテンプレート変数

hookのインラインコマンドは `bash -c` を使用して実行されます（`lib/hooks.sh` の `_execute_hook()` 関数）。環境変数および設定ファイルによるオプトイン制御が実装されています：

```bash
# lib/hooks.sh:_execute_hook()
_execute_hook() {
    local hook="$1"
    ...
    # インラインコマンドの場合: 明示的許可が必要
    local allow_inline="${PI_RUNNER_HOOKS_ALLOW_INLINE:-${PI_RUNNER_ALLOW_INLINE_HOOKS:-}}"
    if [[ -z "$allow_inline" ]]; then
        # 環境変数未設定の場合、設定ファイルの hooks.allow_inline を確認
        allow_inline="$(get_config hooks_allow_inline)" || allow_inline="false"
    fi
    
    if [[ "$allow_inline" != "true" ]]; then
        log_warn "Inline hook commands are disabled. Falling back to default notification."
        log_warn "To enable, add 'hooks.allow_inline: true' to .pi-runner.yaml"
        log_warn "  or set: export PI_RUNNER_HOOKS_ALLOW_INLINE=true"
        return 2  # 2 = blocked, triggers fallback to default notification
    fi
    
    # bash -c を使用（eval は使用しない）
    bash -c "$hook"
}
```

実行時には警告ログが出力されるため、意図しないコマンド実行に気づくことができます。

#### テンプレート変数の廃止

バージョン 0.4.0 以降、テンプレート変数（`{{issue_title}}`, `{{error_message}}` 等）は**非推奨**となりました。

**問題点**:
- テンプレート変数は文字列置換で展開されるため、特殊文字が含まれる場合にコマンドインジェクションのリスクがある
- Issueタイトルやエラーメッセージは外部からの入力であり、任意の文字列を含む可能性がある

**推奨される方法**:
- 環境変数（`$PI_ISSUE_NUMBER`, `$PI_ISSUE_TITLE` 等）を使用
- 環境変数経由で渡される値は文字列として安全に処理される

詳細は[Hook機能ドキュメント](./hooks.md#マイグレーションガイド)を参照してください。

### リスク

1. **任意コード実行**: `.pi-runner.yaml` の `hooks` セクションに定義されたコマンドは、そのまま実行される
2. **信頼されていない設定ファイル**: 悪意のあるリポジトリに含まれる `.pi-runner.yaml` が自動的に読み込まれる可能性がある
3. **環境変数の漏洩**: hook内で環境変数が参照される場合、機密情報が外部に送信される可能性がある

### 推奨事項

1. **信頼できる設定ファイルのみ使用**: `.pi-runner.yaml` は信頼できるソースからのみ取得
2. **hookの内容を確認**: 不明なリポジトリのhook設定は実行前に確認
3. **最小権限の原則**: hookスクリプトには必要最小限の権限のみ付与
4. **機密情報を含むhookは環境変数経由で設定**: 直接ハードコードしない
5. **外部スクリプトファイルを使用する場合はファイルの所有者とパーミッションを確認**

### 例: 安全なhook設定

```yaml
# .pi-runner.yaml
hooks:
  # ✅ 安全: 環境変数を使用
  on_success: "echo 'Task completed: #$PI_ISSUE_NUMBER'"
  
  # ✅ 安全: 信頼できるスクリプトファイル（例: ./hooks/notify-error.sh をユーザーが作成）
  on_error: "./hooks/notify-error.sh"
  
  # ⚠️ 注意: 外部サービスへの送信は機密情報に注意
  on_start: "curl -X POST https://example.com/webhook -d '{\"issue\": \"$PI_ISSUE_NUMBER\"}'"
  
  # ❌ 非推奨: テンプレート変数（コマンドインジェクションのリスク）
  # on_success: "echo 'Task completed: #{{issue_number}}'"
```

## 関連ドキュメント

- [アーキテクチャ](architecture.md) - システム全体の設計
- [設定リファレンス](configuration.md) - 設定オプション
- [Hook機能](hooks.md) - hook の詳細仕様
