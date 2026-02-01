---
name: ci-workflow
description: PR作成後のCI監視、失敗時の分類と対応、自動マージまでの完全なワークフローを定義
---

# CI監視ワークフロー

> **責任範囲**: CI監視 → 失敗分析 → 自動修正 → 成功時マージ
> 
> | このスキル | pr-merge-workflow |
> |-----------|-------------------|
> | CIポーリング・ログ分析 | PR作成テンプレート |
> | 失敗時の自動修正（タイプ別設定） | ロールバック手順 |
> | リトライ管理（タイプ別） | クリーンアップ |
> | 成功時の自動マージ呼び出し | - |

---

## 設定パラメータ

CI監視の動作は以下のパラメータで調整可能：

### 基本設定

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `POLLING_INTERVAL` | 30秒 | CIチェックのポーリング間隔 |
| `BASE_TIMEOUT` | 600秒（10分） | 基本のCI待機タイムアウト |
| `MAX_TOTAL_TIME` | 3600秒（1時間） | 全体の最大実行時間 |

### 失敗タイプ別リトライ設定

| 失敗タイプ | リトライ回数 | タイムアウト | 理由 |
|-----------|-------------|-------------|------|
| `format` | 2回 | 300秒（5分） | フォーマット修正は単純で確実 |
| `lint` | 3回 | 600秒（10分） | 標準的な修正 |
| `build` | 4回 | 900秒（15分） | ビルドエラーは調査に時間がかかる |
| `test` | **5回** | **1200秒（20分）** | テスト失敗は複雑でflakyなことが多い |
| `unknown` | 3回 | 600秒（10分） | 不明な失敗は標準的な対応 |

```python
CI_CONFIG = {
    "polling_interval": 30,  # 秒
    "max_total_time": 3600,  # 秒（1時間）
    "failure_types": {
        "format": {
            "retries": 2,
            "timeout": 300,
            "auto_fixable": True,
            "fix_command": "cargo fmt"
        },
        "lint": {
            "retries": 3,
            "timeout": 600,
            "auto_fixable": True,
            "fix_command": "cargo clippy --fix --allow-dirty --allow-staged"
        },
        "build": {
            "retries": 4,
            "timeout": 900,
            "auto_fixable": False
        },
        "test": {
            "retries": 5,
            "timeout": 1200,
            "auto_fixable": False
        },
        "unknown": {
            "retries": 3,
            "timeout": 600,
            "auto_fixable": False
        }
    }
}
```

---

## 実行者の責任分担

| フェーズ | 実行者 | 理由 |
|---------|--------|------|
| 0-9 (実装→PR作成) | `Sisyphus` | ホスト環境/Worktreeでの作業 |
| **10 (CI監視→マージ)** | **`Sisyphus`** | GitHub API操作 |
| **11 (環境クリーンアップ)** | **`Sisyphus`** | Worktree削除等 |

> **Note**: CI監視やPRマージは `bash` ツールでGitHub APIを呼び出す。

---

## メインフロー

```python
def post_pr_workflow(pr_number: int):
    """PR作成後: CI待機 → 成功:マージ&削除 / 失敗:修正(タイプ別回数) / タイムアウト:報告"""
    ci_result = wait_for_ci(pr_number, timeout=CI_CONFIG["base_timeout"])
    
    if ci_result == SUCCESS:
        auto_merge_pr(pr_number) and cleanup_worktree(pr_number)
    elif ci_result == FAILURE:
        if handle_ci_failure(pr_number):
            # 修正成功 → マージ & 環境削除
            auto_merge_pr(pr_number) and cleanup_worktree(pr_number)
        else:
            # リトライ超過 → エスカレーション（環境保持）
            escalate_ci_failure(pr_number)
    elif ci_result == TIMEOUT:
        handle_ci_timeout(pr_number)  # 環境保持
```

---

## 1. CI完了待機

```python
def wait_for_ci(pr_number: int, timeout: int = None) -> CIResult:
    """設定された間隔でgh pr checksをポーリング"""
    timeout = timeout or CI_CONFIG["base_timeout"]
    interval = CI_CONFIG["polling_interval"]
    
    for _ in range(timeout // interval):
        checks = bash(f"gh pr checks {pr_number} --json state,name")
        if all_success(checks): return SUCCESS
        if any_failure(checks): return FAILURE
        wait(interval)
    return TIMEOUT
```

---

## 2. CI失敗の分類と対応

| 失敗カテゴリ | 検出パターン | 自動修正 | リトライ |
|------------|-------------|---------|---------|
| **フォーマット** | `Diff in`, `would have been reformatted` | ✅ `cargo fmt` | 2回 |
| **Lint/Clippy** | `warning:`, `clippy::` | ✅ `--fix` | 3回 |
| **ビルドエラー** | `error[E`, `cannot find` | ❌ 手動 | 4回 |
| **テスト失敗** | `FAILED`, `test result: FAILED` | ❌ 手動 | **5回** |
| **環境依存** | `platform exception`, `timeout` | ❌ 再実行 | 3回 |

```python
def analyze_failure(log: str) -> CIFailureAnalysis:
    """CIログを分析して失敗種別と設定を特定"""
    config = CI_CONFIG["failure_types"]
    
    if "would have been reformatted" in log or "Diff in" in log:
        return CIFailureAnalysis(
            type="format",
            **config["format"]
        )
    if "clippy::" in log or "warning:" in log:
        return CIFailureAnalysis(
            type="lint",
            **config["lint"]
        )
    if "error[E" in log or "cannot find" in log or " Compiling" in log:
        return CIFailureAnalysis(
            type="build",
            **config["build"]
        )
    if "FAILED" in log or "test result: FAILED" in log:
        return CIFailureAnalysis(
            type="test",
            **config["test"]
        )
    return CIFailureAnalysis(
        type="unknown",
        **config["unknown"]
    )
```

---

## 3. CI修正フロー（タイプ別リトライ）

```python
def handle_ci_failure(pr_number: int) -> bool:
    """CI失敗 → タイプ別リトライ回数で修正試行"""
    # 初回の失敗分析
    log = bash("gh run view --log-failed")
    analysis = analyze_failure(log)
    
    max_retries = analysis.retries
    timeout = analysis.timeout
    
    for attempt in range(1, max_retries + 1):
        log_info(f"CI修正試行 {attempt}/{max_retries} (タイプ: {analysis.type})")
        
        # ホスト環境で修正
        fix_in_host(pr_number, analysis)
        
        # 修正後のCI待機（タイプ別タイムアウト）
        ci_result = wait_for_ci(pr_number, timeout=timeout)
        
        if ci_result == SUCCESS:
            log_info(f"CI成功：{attempt}回目の試行で成功")
            return True
        elif ci_result == FAILURE:
            # 失敗タイプが変わった可能性があるので再分析
            log = bash("gh run view --log-failed")
            new_analysis = analyze_failure(log)
            if new_analysis.type != analysis.type:
                log_info(f"失敗タイプ変更：{analysis.type} → {new_analysis.type}")
                analysis = new_analysis
                max_retries = max(max_retries, analysis.retries)  # より多い方を採用
        elif ci_result == TIMEOUT:
            log_warn(f"CIタイムアウト：{timeout}秒待機したが完了せず")
            continue
    
    log_error(f"CI修正失敗：{max_retries}回試行したが成功せず")
    return False  # リトライ超過 → escalate_ci_failure()

def fix_in_host(pr_number: int, analysis: CIFailureAnalysis):
    """ホスト環境で修正を実施"""
    # 1. ブランチをチェックアウト
    branch = bash(f"gh pr view {pr_number} --json headRefName -q .headRefName")
    bash(f"git checkout {branch}")
    
    # 2. リモートの最新状態を取得
    bash("git pull origin HEAD")
    
    # 3. 修正を実施
    if analysis.auto_fixable and analysis.fix_command:
        log_info(f"自動修正実行：{analysis.fix_command}")
        bash(analysis.fix_command)
    else:
        log_info("手動修正が必要：AIによる修正を実施")
        ai_fix_ci_failure(pr_number, analysis)
    
    # 4. ローカルで検証（タイプ別）
    verify_locally(analysis.type)
    
    # 5. 修正をpush
    bash("git add . && git commit -m 'fix: CI修正' && git push")

def verify_locally(failure_type: str):
    """失敗タイプに応じたローカル検証"""
    if failure_type == "format":
        bash("cargo fmt -- --check")
    elif failure_type == "lint":
        bash("cargo clippy -- -D warnings")
    elif failure_type == "build":
        bash("cargo build")
    elif failure_type == "test":
        bash("cargo test")
    else:
        bash("cargo fmt -- --check && cargo clippy -- -D warnings && cargo test")
```

---

## 4. 自動マージ

```python
def auto_merge_pr(pr_number: int, issue_num: int) -> bool:
    """gh pr merge --merge --delete-branch"""
    result = bash(f"gh pr merge {pr_number} --merge --delete-branch")
    if result.exit_code == 0:
        # Issue ラベル更新: env:merged
        bash(f"bash .pi/skills/github-issue-state-management/scripts/issue-state.sh merged {issue_num}")
        return True
    return handle_merge_failure(pr_number, error=result.stderr)
```

---

## 5. エスカレーション

```python
def escalate_ci_failure(pr_number: int, analysis: CIFailureAnalysis = None):
    """PRをDraft化、詳細な失敗ログをコメント、ユーザーに報告"""
    bash(f"gh pr ready {pr_number} --undo")
    
    retry_info = f"（{analysis.retries}回リトライ済み）" if analysis else ""
    
    comment = f"""⚠️ CI修正が失敗しました{retry_info}

**失敗タイプ**: {analysis.type if analysis else 'unknown'}
**自動修正可能**: {'Yes' if analysis and analysis.auto_fixable else 'No'}

手動での確認と修正が必要です。詳細なログはActionsタブを確認してください。
"""
    bash(f"gh pr comment {pr_number} --body '{comment}'")
    report_to_user(f"⚠️ PR #{pr_number} のCI修正に失敗。手動確認が必要です。")
```

---

## 6. 環境クリーンアップ

```python
def cleanup_worktree(pr_number: int) -> bool:
    """worktreeを使用している場合は削除"""
    # worktreeの削除ロジック
    return True
```

> **Note**: 環境状態は GitHub Issue ラベルで管理。詳細は [github-issue-state-management](../github-issue-state-management/SKILL.md) を参照。

### クリーンアップタイミング

| 状況 | 環境の扱い |
|------|----------|
| PRマージ成功 | ✅ 即座に削除 |
| PRクローズ（マージなし） | ✅ 即座に削除 |
| CI修正中（リトライ中） | ❌ 削除しない |
| Draft PR（エスカレーション中） | ❌ 削除しない |
| PRレビュー修正待ち | ❌ 削除しない |

---

## パラメータ調整ガイド

### リトライ回数を増やす場合

**テストがflakyで失敗しやすい場合:**
```python
CI_CONFIG["failure_types"]["test"]["retries"] = 7  # 5→7
CI_CONFIG["failure_types"]["test"]["timeout"] = 1800  # 20分→30分
```

### タイムアウトを短縮する場合

**高速フィードバックが必要な場合:**
```python
CI_CONFIG["base_timeout"] = 300  # 10分→5分
CI_CONFIG["failure_types"]["format"]["timeout"] = 120  # 5分→2分
```

### ポーリング間隔を調整

**APIレート制限に対応:**
```python
CI_CONFIG["polling_interval"] = 60  # 30秒→60秒
```

---

## 関連ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| `pr-merge-workflow` skill | PR作成〜マージ〜ロールバックの全体フロー |
| `github-issue-state-management` skill | 環境状態管理（ラベル） |

---

## CLIスクリプト

**CI待機の自動化スクリプト：**

```bash
bash .pi/skills/ci-workflow/scripts/ci-wait.sh <pr-number> [timeout-seconds] [polling-interval]
```

| 引数 | 説明 | デフォルト |
|------|------|-----------|
| `pr-number` | PR番号 | 必須 |
| `timeout-seconds` | 最大待機時間（秒） | 600 |
| `polling-interval` | ポーリング間隔（秒） | 30 |

**終了コード：**
| コード | 意味 |
|--------|------|
| 0 | 全CIチェック成功 |
| 1 | CIチェック失敗 |
| 2 | タイムアウト |
| 3 | 引数エラー |

**使用例：**
```bash
# 基本（10分タイムアウト、30秒間隔）
bash .pi/skills/ci-workflow/scripts/ci-wait.sh 42

# テスト失敗対応（20分タイムアウト、60秒間隔）
bash .pi/skills/ci-workflow/scripts/ci-wait.sh 42 1200 60

# フォーマット修正待機（5分タイムアウト）
bash .pi/skills/ci-workflow/scripts/ci-wait.sh 42 300
```
