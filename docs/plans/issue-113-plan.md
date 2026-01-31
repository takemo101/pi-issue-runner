# Issue #113 実装計画: yqチェック結果のキャッシュ

## 概要

`lib/workflow.sh` の `check_yq()` 関数が毎回 `command -v yq` を実行しているため、
結果をグローバル変数にキャッシュして2回目以降の呼び出しを高速化する。

## 影響範囲

- `lib/workflow.sh` - `check_yq()` 関数のみ

## 現状分析

現在の `check_yq()` 関数:
```bash
check_yq() {
    if command -v yq &> /dev/null; then
        return 0
    else
        log_debug "yq not found, using builtin workflow"
        return 1
    fi
}
```

呼び出し箇所:
- L58: `find_workflow_file()` 内
- L136: `get_workflow_steps()` 内

## 実装ステップ

1. グローバルキャッシュ変数 `_YQ_CHECK_RESULT` を追加（未チェック: 空、存在: "1"、不在: "0"）
2. `check_yq()` を修正:
   - キャッシュが存在する場合はそれを返す
   - キャッシュがない場合のみ `command -v` を実行
   - 結果をキャッシュに保存

## テスト方針

- 既存の `test/workflow_test.sh` でテストが存在するか確認
- 新しいテストケース追加: キャッシュが効いていることの確認

## リスクと対策

- **リスク**: シェルスクリプトのサブシェルでキャッシュが効かない
  - **対策**: 通常の関数呼び出しではキャッシュが効くので問題なし

## 推定作業量

約10行の変更、20分以内に完了予定
