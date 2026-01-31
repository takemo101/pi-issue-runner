# Issue #294 実装計画

## 概要

SKILL.mdに記載されている `improve.sh` の3つのオプションを実装する：
1. `--dry-run` - レビューのみ（Issue作成しない）
2. `--review-only` - 問題表示のみ  
3. `--auto-continue` - 自動継続（承認スキップ）

## 影響範囲

- `scripts/improve.sh` - メインの変更対象
- `test/scripts/improve.bats` - テスト追加

## 現状分析

現在の `improve.sh` は以下のフローで動作：
1. Phase 1: `pi --print` でレビュー実行 → Issue自動作成
2. Phase 2: GitHub APIでIssue取得
3. Phase 3: `run.sh --no-attach` で並列実行
4. Phase 4: `wait-for-sessions.sh` で待機
5. Phase 5: 次のイテレーションへ再帰呼び出し

## 実装ステップ

### 1. 変数追加
```bash
local dry_run=false
local review_only=false
local auto_continue=false
```

### 2. オプションパース追加
```bash
--dry-run)
    dry_run=true
    shift
    ;;
--review-only)
    review_only=true
    shift
    ;;
--auto-continue)
    auto_continue=true
    shift
    ;;
```

### 3. 各オプションの動作

#### `--dry-run`
- Phase 1でレビュープロンプトを変更：「問題を報告するがIssueは作成しない」
- Phase 2〜5をスキップ
- レビュー結果のみを表示して終了

#### `--review-only`
- Phase 1のレビュー結果のみを表示
- Phase 2以降をスキップ
- `--dry-run` より軽量（Issue作成せず報告のみ）

#### `--auto-continue`
- イテレーション間の承認確認をスキップ
- 現在は自動継続が既定のため、将来の拡張用に準備
- （現在は実質的にnoop、ただしフラグとして受け付ける）

### 4. usage() 更新
ヘルプに新オプションを追加

### 5. テスト追加
- オプションがヘルプに表示されることを確認
- オプションパースのテスト
- 構造テスト（grep でオプション処理コードを確認）

## テスト方針

- ユニットテスト: オプションパースと構造確認
- 統合テスト: 実際の動作確認（モック使用）

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存の動作に影響 | デフォルト値をfalseに設定し、既存動作を維持 |
| pi --print のプロンプト変更 | dry-runフラグで条件分岐 |
