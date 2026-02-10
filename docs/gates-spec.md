# Gates（品質ゲート）仕様書

## 概要

COMPLETEマーカー検出後に外部コマンドで品質検証し、失敗ならAIに差し戻す仕組み。
AIセッションは分割せず、既存の watcher + nudge を拡張して実現する。

## 背景・動機

現状のpi-issue-runnerはAIが「完了」と自己申告すればそのままcleanupされる。
テスト未実行、lint警告無視、CI失敗でもPRがマージされる可能性がある。

TAKTのようなステップ分割型オーケストレーターはこの問題を解決するが、
ステップごとにセッションを切るためAIがコンテキストを失うという欠点がある。

本機能は**セッションを切らずに外部検証を行う**ことで、
コンテキスト保持と品質保証を両立する。

## 設計原則

1. **AIセッションは1つのまま** - コンテキスト喪失なし
2. **実コマンドの終了コードで判定** - AIの自己申告に頼らない
3. **失敗時は実際のエラー出力をAIに送信** - 何を直すべきか正確にわかる
4. **既存アーキテクチャの延長** - watcher + nudge の拡張で実現

## 動作フロー

```
AI「完了！」（COMPLETEマーカー検出）
    ↓
[ゲート1] shellcheck → 失敗
    ↓
nudge: "ゲート失敗: shellcheck\n\nscripts/run.sh:42: warning SC2086..."
    ↓
AI修正 →「完了！」（COMPLETEマーカー再検出）
    ↓
[ゲート1] shellcheck → 成功 ✅
[ゲート2] bats test/ → 成功 ✅
[ゲート3] call: code-review → 指摘あり
    ↓
nudge: "レビュー指摘: lib/gates.sh:15 エラーハンドリング不足..."
    ↓
AI修正 →「完了！」
    ↓
[ゲート1] shellcheck → 成功 ✅
[ゲート2] bats test/ → 成功 ✅
[ゲート3] call: code-review → APPROVED ✅
[ゲート4] gh pr checks → CI通過 ✅
    ↓
従来のPR確認 → cleanup → 終了
```

## 設定

### `.pi-runner.yaml` の記述

```yaml
# ワークフロー固有のゲート
workflows:
  default:
    description: 標準ワークフロー
    steps:
      - plan
      - implement
      - merge
    gates:
      - "shellcheck -x scripts/*.sh lib/*.sh"
      - "bats --jobs 4 test/"
      - call: code-review
        max_retry: 2
      - command: "gh pr checks ${pr_number} --watch"
        timeout: 600

  # ゲートから呼ばれるレビューワークフロー
  code-review:
    description: コードレビュー（ゲート用）
    steps:
      - review
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5

  feature:
    description: 新機能開発
    steps:
      - plan
      - implement
      - test
      - merge
    gates:
      - "shellcheck -x scripts/*.sh lib/*.sh"
      - "bats --jobs 4 test/"
      - call: code-review
        max_retry: 2
      - command: "gh pr checks ${pr_number} --watch"
        timeout: 600

# グローバルゲート（全ワークフロー共通）
# ワークフロー固有の gates が未定義の場合に使用
gates:
  - "shellcheck -x scripts/*.sh lib/*.sh"
  - "bats --jobs 4 test/"
```

### ゲートの3つの形式

#### 1. シンプル形式（文字列）

```yaml
gates:
  - "shellcheck -x scripts/*.sh lib/*.sh"
  - "bats --jobs 4 test/"
```

exit 0 で通過、非0で失敗。

#### 2. 詳細形式（command）

```yaml
gates:
  - command: "gh pr checks ${pr_number} --watch --fail-level all"
    timeout: 600          # タイムアウト秒（デフォルト: 300）
    max_retry: 3          # リトライ回数（デフォルト: 0）
    retry_interval: 30    # リトライ間隔秒（デフォルト: 10）
    continue_on_fail: false  # 失敗しても続行（デフォルト: false）
    description: "CI通過待ち"  # ログ表示用
```

#### 3. ワークフロー呼び出し形式（call）

```yaml
gates:
  - call: code-review     # workflows セクションのワークフロー名
    max_retry: 2
    timeout: 300
```

別ワークフローを別AIインスタンスで実行し、結果を取得する。
ワークフロー内のエージェントが出力した内容がゲートの出力となる。
ワークフローが正常完了（COMPLETEマーカー出力）すれば通過、
エラー終了やタイムアウトで失敗。

### テンプレート変数

ゲートコマンド内で使用可能：

| 変数 | 説明 |
|------|------|
| `${issue_number}` | Issue番号 |
| `${pr_number}` | PR番号 |
| `${branch_name}` | ブランチ名 |
| `${worktree_path}` | worktreeのパス |

### ゲートの優先順位

1. ワークフロー固有の `gates`（`workflows.<name>.gates`）
2. グローバル `gates`（トップレベル `gates`）
3. 未定義ならゲートなし（従来動作）

ワークフロー固有の gates が定義されている場合、グローバル gates は実行されない。

## call: の仕様

### 動作

1. 指定されたワークフロー名を `workflows` セクションから読み込む
2. ワークフローのエージェント設定（type, args）でAIインスタンスを起動
3. worktree内のdiffを対象にワークフローを実行
4. AIの出力をキャプチャ
5. 正常完了 → ゲート通過（exit 0）
6. 異常終了/タイムアウト → ゲート失敗、AI出力がnudgeで送信される

### 循環呼び出し検出

`call:` は循環呼び出しをエラーとする。

```yaml
# 直接循環 → エラー
workflows:
  default:
    gates:
      - call: default  # 自分自身を呼ぶ → NG

# 間接循環 → エラー
workflows:
  default:
    gates:
      - call: code-review
  code-review:
    gates:
      - call: default  # defaultに戻る → NG
```

ゲート実行前に呼び出しチェーンを構築し、循環を検出した場合は
ゲート実行を行わずエラーログを出力して失敗とする。

### call先ワークフローの制約

- `call:` で呼ばれるワークフローは `steps` と `agent` を持つ通常のワークフロー
- `call:` 先のワークフローも `gates` を持てる（循環しない限り）
- `call:` 先は元セッションとは独立した別AIインスタンスで実行される

## ゲート失敗時の挙動

1. ゲートコマンドの stdout/stderr をキャプチャ
2. nudge でAIセッションにエラー内容を送信
   - メッセージ形式: `"ゲート失敗: <コマンドまたはワークフロー名>\n\n<出力内容>"`
3. AIが修正してCOMPLETEマーカーを再出力するのを待つ
4. COMPLETEマーカー再検出 → ゲートを最初から再実行
5. max_retry を超えたら ERROR マーカー扱いで通知

### max_retry のスコープ

- `max_retry` は**個別ゲート**の連続失敗回数
- COMPLETEマーカーの再検出ごとにカウントはリセットされない
- 全ゲートの合計リトライ上限（`max_total_retry`）も設定可能（デフォルト: 10）

## 実行環境

- ゲートコマンドは **worktree内** で実行される（cwdがworktree_path）
- `call:` も同じworktreeを対象に実行される
- 環境変数 `PI_ISSUE_NUMBER`, `PI_BRANCH_NAME`, `PI_WORKTREE_PATH` が設定される

## スキップ

```bash
# 一時的にゲートをスキップ
scripts/run.sh 42 --no-gates

# 特定のゲートのみスキップ（将来拡張）
scripts/run.sh 42 --skip-gate "shellcheck"
```

## tracker連携

ゲートの実行結果を `tracker.jsonl` に記録：

```json
{
  "issue": 42,
  "workflow": "default",
  "result": "success",
  "duration_sec": 1234,
  "gates": {
    "shellcheck": {"result": "pass", "attempts": 1},
    "bats": {"result": "pass", "attempts": 2},
    "code-review": {"result": "pass", "attempts": 1},
    "gh-pr-checks": {"result": "pass", "attempts": 1}
  },
  "total_gate_retries": 1,
  "timestamp": "2026-02-10T12:00:00Z"
}
```

## 実装対象ファイル

### 新規
- `lib/gates.sh` - ゲート実行エンジン
  - `run_gates()` - ゲートリスト実行
  - `run_single_gate()` - 単一ゲート実行（タイムアウト・リトライ）
  - `run_call_gate()` - ワークフロー呼び出しゲート実行
  - `parse_gate_config()` - YAML設定パース
  - `expand_gate_variables()` - テンプレート変数展開
  - `detect_call_cycle()` - 循環呼び出し検出
- `test/lib/gates.bats` - ゲートエンジンのユニットテスト

### 変更
- `scripts/watch-session.sh` - `handle_complete` にゲート実行を追加
- `scripts/run.sh` - `--no-gates` オプション追加
- `lib/config.sh` - gates設定の読み込み
- `lib/tracker.sh` - ゲート結果の記録
- `schemas/pi-runner.schema.json` - ゲート設定のスキーマ追加

### ドキュメント
- `docs/gates.md` - ゲート機能の利用ガイド（本仕様書とは別）
- `docs/configuration.md` - 設定リファレンス更新
- `README.md` - 機能紹介追加
- `AGENTS.md` - ディレクトリ構造更新
