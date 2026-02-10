# Gates（品質ゲート）

COMPLETEマーカー検出後に外部コマンドで品質検証し、失敗ならAIに差し戻す仕組み。

## 設定

### ワークフロー固有のゲート

```yaml
workflows:
  default:
    steps:
      - plan
      - implement
      - merge
    gates:
      - "shellcheck -x scripts/*.sh lib/*.sh"
      - "bats --jobs 4 test/"
      - command: "gh pr checks ${pr_number} --watch"
        timeout: 600
      - call: code-review
        max_retry: 2
```

### グローバルゲート

ワークフロー固有の `gates` が未定義の場合に使用されます。

```yaml
gates:
  - "shellcheck -x scripts/*.sh lib/*.sh"
  - "bats --jobs 4 test/"
```

## ゲートの3つの形式

### シンプル形式（文字列）

```yaml
gates:
  - "shellcheck -x scripts/*.sh lib/*.sh"
```

exit 0 で通過、非0で失敗。

### 詳細形式（command）

```yaml
gates:
  - command: "gh pr checks ${pr_number} --watch --fail-level all"
    timeout: 600
    max_retry: 3
    retry_interval: 30
    continue_on_fail: false
    description: "CI通過待ち"
```

| フィールド | デフォルト | 説明 |
|-----------|-----------|------|
| `command` | - | 実行するシェルコマンド |
| `timeout` | 300 | タイムアウト（秒） |
| `max_retry` | 0 | リトライ回数 |
| `retry_interval` | 10 | リトライ間隔（秒） |
| `continue_on_fail` | false | 失敗しても次のゲートへ続行 |
| `description` | - | ログ表示用の名前 |

### ワークフロー呼び出し形式（call）

```yaml
gates:
  - call: code-review
    max_retry: 2
    timeout: 300
```

別ワークフローを別AIインスタンスで実行し、COMPLETEマーカーで通過判定。

## テンプレート変数

ゲートコマンド内で使用可能：

| 変数 | 説明 |
|------|------|
| `${issue_number}` | Issue番号 |
| `${pr_number}` | PR番号 |
| `${branch_name}` | ブランチ名 |
| `${worktree_path}` | worktreeのパス |

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
[ゲート1] shellcheck → 成功
[ゲート2] bats test/ → 成功
    ↓
従来のPR確認 → cleanup → 終了
```

## スキップ

```bash
scripts/run.sh 42 --no-gates
```

## Tracker連携

ゲート結果は `tracker.jsonl` に自動記録されます。

```json
{
  "issue": 42,
  "workflow": "default",
  "result": "success",
  "duration_sec": 1234,
  "gates": {
    "shellcheck": {"result": "pass", "attempts": 1},
    "bats": {"result": "pass", "attempts": 2}
  },
  "total_gate_retries": 1,
  "timestamp": "2026-02-10T12:00:00Z"
}
```

統計表示：

```bash
scripts/tracker.sh --gates
```

## 優先順位

1. ワークフロー固有の `gates`（`workflows.<name>.gates`）
2. グローバル `gates`（トップレベル）
3. 未定義ならゲートなし（従来動作）

## 仕様書

詳細な仕様は [gates-spec.md](gates-spec.md) を参照してください。
