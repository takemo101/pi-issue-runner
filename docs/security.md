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

## evalの使用

本プロジェクトでは、以下の箇所で `eval` を使用しています。`eval` はシェルコマンドとして文字列を評価・実行するため、外部入力を含む場合はセキュリティリスクとなります。

### 使用箇所一覧

| ファイル | 行 | 関数 | 用途 | リスク |
|----------|-----|------|------|--------|
| `lib/hooks.sh` | 133 | `_execute_hook()` | インラインhookコマンドの実行 | 🔴 高 |
| `scripts/watch-session.sh` | 146 | `handle_error()` | シェルオプションの復元 | 🟢 低 |
| `scripts/watch-session.sh` | 278 | `handle_complete()` | シェルオプションの復元 | 🟢 低 |

### lib/hooks.sh でのeval（リスク：🟡 中）

**用途**: インラインhookコマンド（`.pi-runner.yaml` に記述された文字列コマンド）を実行するために使用。

```bash
# lib/hooks.sh:_execute_hook()
_execute_hook() {
    local hook="$1"
    ...
    # インラインコマンドの場合: 明示的許可が必要
    if [[ "${PI_RUNNER_ALLOW_INLINE_HOOKS:-false}" != "true" ]]; then
        log_warn "Inline hook commands are disabled for security."
        return 0
    fi
    ...
    eval "$hook"
}
```

**リスク**: 中（環境変数によるオプトイン制御あり）
- デフォルトでインラインhookは拒否される
- `PI_RUNNER_ALLOW_INLINE_HOOKS=true` を設定した場合のみ実行可能
- ファイルパスhookは常に許可される

**軽減策**:
- デフォルトで無効化（環境変数でオプトイン）
- 実行前に警告ログを出力
- ファイルパスベースのhookを推奨
- 詳細は後述の「[インラインhookの制御](#インラインhookの制御)」セクション参照

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
[WARN] To enable, set: export PI_RUNNER_ALLOW_INLINE_HOOKS=true
```

ファイルパスで指定されたhookスクリプトは、環境変数の設定に関係なく常に実行されます。

#### 有効化方法

インラインhookを使用する場合は、環境変数を設定してください：

```bash
export PI_RUNNER_ALLOW_INLINE_HOOKS=true
./scripts/run.sh 42
```

または、シェルの設定ファイルに追加：

```bash
# ~/.bashrc または ~/.zshrc
export PI_RUNNER_ALLOW_INLINE_HOOKS=true
```

#### 推奨事項

1. **ファイルベースのhookを使用**: インラインコマンドの代わりにスクリプトファイルを使用することを強く推奨します
2. **信頼できるリポジトリのみで有効化**: 環境変数は信頼できるプロジェクトでのみ設定してください
3. **プロジェクトごとの設定**: グローバルに設定せず、必要なプロジェクトでのみ一時的に有効化してください
4. **設定ファイルの確認**: 新しいリポジトリで作業する前に `.pi-runner.yaml` の内容を確認してください

### evalの使用

hookのインラインコマンドは `eval` を使用して実行されます（`lib/hooks.sh` の `_execute_hook()` 関数）。環境変数によるオプトイン制御が実装されています：

```bash
# lib/hooks.sh:_execute_hook()
_execute_hook() {
    local hook="$1"
    ...
    # インラインコマンドの場合: 明示的許可が必要
    if [[ "${PI_RUNNER_ALLOW_INLINE_HOOKS:-false}" != "true" ]]; then
        log_warn "Inline hook commands are disabled for security."
        return 0
    fi
    # インラインコマンドとして実行
    log_warn "Executing inline hook command (security note: ensure this is from a trusted source)"
    log_debug "Executing inline hook"
    eval "$hook"
}
```

実行時には警告ログが出力されるため、意図しないコマンド実行に気づくことができます。

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
  # ✅ 安全: シンプルな通知
  on_success: "echo 'Task completed: #{{issue_number}}'"
  
  # ✅ 安全: 信頼できるスクリプトファイル
  on_error: "./scripts/notify-error.sh"
  
  # ⚠️ 注意: 外部サービスへの送信は機密情報に注意
  on_start: "curl -X POST https://example.com/webhook -d '{\"issue\": \"{{issue_number}}\"}'"
```

## 関連ドキュメント

- [アーキテクチャ](architecture.md) - システム全体の設計
- [設定リファレンス](configuration.md) - 設定オプション
- [Hook機能](hooks.md) - hook の詳細仕様
