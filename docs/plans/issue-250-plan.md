# Implementation Plan: Issue #250

## 概要

`lib/workflow.sh` の `generate_workflow_prompt` 関数のフッター部分に、エラーマーカー（`###TASK_ERROR_<issue>###`）の説明を追加する。

## 影響範囲

- **変更ファイル**:
  - `lib/workflow.sh` - `generate_workflow_prompt` 関数のフッター部分
  
- **テスト追加**:
  - `test/lib/workflow.bats` - エラーマーカー説明がプロンプトに含まれることを確認

## 現状分析

### 問題点
1. `generate_workflow_prompt` 関数のフッター（L455-471）で完了マーカーは詳しく説明されているが、エラーマーカーの説明がない
2. `agents/*.md` ではエラーマーカーを説明しているが、ビルトインワークフロープロンプトでは欠けている
3. `watch-session.sh` はエラーマーカーも監視している（L105: `error_marker="###TASK_ERROR_${issue_number}###"`）

### 現在のフッター構造
```bash
### On Error
- If tests fail, fix the issue before committing
- If PR merge fails, report the error

### On Completion
**CRITICAL**: After completing all workflow steps...
```

## 実装ステップ

1. `lib/workflow.sh` のフッター部分を修正
   - `### On Error` セクションにエラーマーカーの説明を追加
   - `agents/plan.md` と同様のフォーマットを使用

2. テストを追加
   - `generate_workflow_prompt` の出力にエラーマーカー説明が含まれることを確認

3. 既存テストの実行確認

## テスト方針

- **単体テスト**: `generate_workflow_prompt` の出力に `###TASK_ERROR_` の説明が含まれることを確認
- **回帰テスト**: 既存のテストがすべてパスすることを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存のワークフロー動作への影響 | ドキュメント追加のみなので動作影響なし |
| エージェントテンプレートとの不整合 | `agents/*.md` のフォーマットに合わせる |

## 見積もり

作業時間: 約30分
