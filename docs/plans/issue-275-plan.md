# Issue #275 実装計画

## 概要

`lib/*.sh` ファイルで定義されている `SCRIPT_DIR` 変数が、`improve.sh` の `SCRIPT_DIR` を上書きしてしまう問題を修正する。

## 原因分析

`improve.sh` では以下の順序で処理が行われる:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # → /path/to/scripts
source "$SCRIPT_DIR/../lib/config.sh"  # config.sh内でSCRIPT_DIRが上書きされる
```

その結果、後の `"$SCRIPT_DIR/run.sh"` が `lib/run.sh` を参照してしまい、ファイルが見つからないエラーが発生。

## 影響範囲

`SCRIPT_DIR` を定義しているライブラリファイル:
- `lib/config.sh` (line 8-9)
- `lib/notify.sh` (line 6-9, line 106)
- `lib/tmux.sh` (line 6-8)
- `lib/workflow.sh` (line 6-10)
- `lib/worktree.sh` (line 7, 10-11)

## 実装ステップ

### 方法1: lib/*.shの変数名を変更（採用）

各ファイルでユニークなプレフィックスを使用:

| ファイル | 現在の変数名 | 新しい変数名 |
|----------|-------------|-------------|
| lib/config.sh | SCRIPT_DIR | _CONFIG_LIB_DIR |
| lib/notify.sh | SCRIPT_DIR | _NOTIFY_LIB_DIR |
| lib/tmux.sh | SCRIPT_DIR | _TMUX_LIB_DIR |
| lib/workflow.sh | SCRIPT_DIR | _WORKFLOW_LIB_DIR |
| lib/worktree.sh | SCRIPT_DIR | _WORKTREE_LIB_DIR |

## テスト方針

1. 既存のBatsテストがすべてパスすることを確認
2. `improve.sh` が正常に動作することを手動で確認
3. ShellCheckでエラーがないことを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 変更漏れ | grep で全ての SCRIPT_DIR 参照を確認 |
| 他のスクリプトへの影響 | lib/*.sh の変更は内部変数のみなので影響なし |
