# Issue #163 実装計画

## 概要

SKILL.md と README.md のオプション記載を統一し、run.sh --help との整合性を確保する。

## 現状分析

### 短縮形オプションの実装状況（scripts/run.sh）

| 短縮形 | 正式名 | 実装 |
|--------|--------|------|
| `-i` | `--issue` | ✅ |
| `-b` | `--branch` | ✅ |
| `-w` | `--workflow` | ✅ |

### ドキュメントの差異

| オプション | run.sh 実装 | run.sh --help | SKILL.md | README.md |
|------------|-------------|---------------|----------|-----------|
| `-i` (--issue短縮形) | ✅ | ❌ | ❌ | ❌ |
| `-b` (--branch短縮形) | ✅ | ❌ | ❌ | ❌ |
| `-w` (--workflow短縮形) | ✅ | ❌ | ✅ | ❌ |

## 影響範囲

- `scripts/run.sh` - ヘルプ出力の更新（2箇所）
- `README.md` - 使い方セクションに短縮形追記
- `SKILL.md` - クイックリファレンスに短縮形追記（一貫性のため）

## 実装ステップ

### Step 1: run.sh --help 出力の更新

2箇所のヘルプテキストに短縮形オプションを追記：

```diff
-    --branch NAME     カスタムブランチ名（デフォルト: issue-<num>-<title>）
+    -b, --branch NAME カスタムブランチ名（デフォルト: issue-<num>-<title>）

-    --workflow NAME   ワークフロー名（デフォルト: default）
+    -w, --workflow NAME ワークフロー名（デフォルト: default）
```

注: `-i` (--issue) は位置引数として使うのが一般的なため、ヘルプには追記しない

### Step 2: README.md の更新

使い方セクションに短縮形オプションを追記：

```diff
-scripts/run.sh 42 --workflow simple
+scripts/run.sh 42 --workflow simple    # または -w simple
```

### Step 3: SKILL.md の確認・調整

既に `-w` が記載されているが、`-b` も追記して一貫性を保つ

## テスト方針

1. `scripts/run.sh --help` の出力を確認
2. 各短縮形オプションの動作確認：
   - `scripts/run.sh 999 -w simple --no-attach` のパース確認
   - `scripts/run.sh 999 -b custom-branch --no-attach` のパース確認
3. ドキュメント間の記載が一致することを確認

## リスクと対策

- **リスク**: ドキュメント修正漏れ
  - **対策**: 全ファイルをgrepで確認

- **リスク**: ヘルプ出力のフォーマット崩れ
  - **対策**: 修正後に `--help` を実行して視覚的に確認

## 見積もり

| 作業 | 時間 |
|------|------|
| run.sh ヘルプ更新 | 5分 |
| README.md 更新 | 10分 |
| SKILL.md 確認・調整 | 5分 |
| テスト・確認 | 5分 |
| **合計** | **25分** |
