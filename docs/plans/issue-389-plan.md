# Issue #389 実装計画

## 概要

CI失敗時の自動修正機能を実装します。PR作成後のCIチェックが失敗した場合、失敗タイプを検出して自動修正を試行し、成功すればマージまで完了する機能です。

## 背景

- Issue #386 でCI結果確認機能は実装済み
- しかしCI失敗時は単にマージを中止するだけで自動修復は行われない
- 手動で修正→push→CI待機の繰り返しが発生し効率が悪い

## 影響範囲

### 新規作成ファイル

| ファイル | 説明 |
|---------|------|
| `lib/ci-fix.sh` | CI失敗検出・自動修正のコアライブラリ |
| `agents/ci-fix.md` | CI修正エージェントテンプレート |
| `test/lib/ci-fix.bats` | CI修正機能の単体テスト |

### 修正ファイル

| ファイル | 修正内容 |
|---------|---------|
| `agents/merge.md` | CI失敗時の自動修正フローを統合 |
| `lib/github.sh` | CI状態確認・PR Draft化関数を追加 |
| `workflows/default.yaml` | 必要に応じてci-fixステップを追加 |

## 実装ステップ

### Step 1: コアライブラリの作成 (`lib/ci-fix.sh`)

#### 1.1 CI失敗検出関数

```bash
# CI状態をポーリングして完了を待機（タイムアウト10分）
wait_for_ci_completion()

# 失敗したCIログを取得
get_failed_ci_logs()

# ログから失敗タイプを分類
classify_ci_failure()
```

#### 1.2 自動修正実行関数

```bash
# Lint/Clippy修正
try_fix_lint()

# フォーマット修正  
try_fix_format()

# AIによるテスト修正依頼
try_fix_test_failure()

# AIによるビルドエラー修正依頼
try_fix_build_error()
```

#### 1.3 リトライ管理

```bash
# リトライ回数を追跡
track_retry_count()

# 最大3回リトライ制御
should_continue_retry()
```

### Step 2: GitHub操作関数の追加 (`lib/github.sh`)

```bash
# PRをDraft化
mark_pr_as_draft()

# PRにコメント追加
add_pr_comment()

# CI状態を確認
get_pr_checks_status()
```

### Step 3: エージェントテンプレート作成 (`agents/ci-fix.md`)

CI修正専用のエージェントプロンプトを作成:
- 失敗ログの分析
- 修正方法の決定
- 自動修正コマンドの実行またはAI修正依頼

### Step 4: Mergeエージェントの修正 (`agents/merge.md`)

既存のmerge.mdを修正してCI自動修正フローを統合:

```bash
# CI失敗時の自動修正フロー
if ci_failed; then
    classify_failure_type
    if auto_fixable; then
        apply_auto_fix
        git commit -m "fix: CI修正"
        git push
        # CI再実行を待機
        if ci_passed; then
            merge_pr
        else
            # リトライまたはエスカレーション
        fi
    else
        escalate_to_draft
    fi
fi
```

### Step 5: テスト作成

- `test/lib/ci-fix.bats` - 各種関数の単体テスト
- モックを使用したCI状態シミュレーション

## 詳細仕様

### 失敗タイプ検出パターン

| 失敗カテゴリ | 検出パターン | 自動修正方法 |
|------------|-------------|-------------|
| **Lint/Clippy** | `warning:`, `clippy::` | `cargo clippy --fix --allow-dirty --allow-staged` |
| **フォーマット** | `Diff in`, `would have been reformatted` | `cargo fmt` |
| **Test失敗** | `FAILED`, `test result: FAILED` | テストコード修正（AI解析） |
| **ビルドエラー** | `error[E`, `cannot find` | ソースコード修正（AI解析） |

### ワークフロー

```
CI失敗検出 → ログ分析 → {自動修正可能?}
    ├── Yes → ホスト環境で修正 → push & CI再実行 → {CI成功?}
    │                                           ├── Yes → 自動マージ
    │                                           └── No → {リトライ回数 < 3?}
    │                                                               ├── Yes → ログ分析
    │                                                               └── No → エスカレーション
    └── No → エスカレーション → Draft化 & 手動対応
```

### エスカレーション処理

1. PRをDraft化: `gh pr ready <pr_number> --undo`
2. 失敗ログをコメント追加
3. エラーマーカー出力

## テスト方針

### 単体テスト

1. **CI状態検出テスト**
   - CI完了待機（成功ケース）
   - CI完了待機（失敗ケース）
   - タイムアウト処理

2. **失敗分類テスト**
   - 各種パターンの検出
   - 不明な失敗タイプの処理

3. **自動修正テスト**
   - Lint修正コマンド生成
   - Format修正コマンド生成
   - リトライ回数追跡

### 統合テスト

- 実際のPRでCIフローをテスト（手動）

## リスクと対策

| リスク | 対策 |
|--------|------|
| 自動修正が無限ループになる | 最大3回のリトライ制限を実装 |
| 誤った修正が適用される | 修正後にローカルで検証（cargo clippy/test） |
| 長時間のCI待機でセッションがハング | タイムアウト（10分）を設定 |
| ホスト環境にRustがない | cargoコマンド存在チェックを実施 |
| PRがDraft化できない権限 | エラーをキャッチして継続 |

## 技術的検討事項

- **修正実行環境**: ホスト環境（Sisyphus）で実施
- **修正後検証**: `cargo clippy` と `cargo test` をローカル実行
- **コミットメッセージ**: `fix: CI修正 (#<PR番号>)`
- **ポーリング間隔**: 30秒
- **タイムアウト**: 10分

## 受け入れ条件

- [ ] CI失敗時に自動修正が試行される
- [ ] Lint/Format系は自動コマンドで修正
- [ ] Test/Build失敗はAI修正を実施
- [ ] 最大3回リトライ後にエスカレーション
- [ ] 成功時は自動マージ、失敗時はDraft化
- [ ] 全てのテストがパスする

## 関連Issue

- #386 - CI結果確認機能の実装
