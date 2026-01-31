# 実装計画: Issue #224 - CI/開発環境へのshellcheck導入

## 概要

プロジェクトのシェルスクリプト品質を向上させるため、shellcheckをCI/開発環境に完全統合する。

## 現状分析

### CI
- 既に `.github/workflows/ci.yaml` にShellCheckジョブが存在
- `severity: error` のみで、警告は無視されている

### ローカル開発環境
- `scripts/test.sh` にshellcheckオプションがない
- `AGENTS.md` にshellcheckコマンドの記載があるが、インストール手順がない

### 既存の警告
1. **SC1091** (info): ソースファイルを追跡していない → `-x` オプションで解決
2. **SC2034** (warning): 未使用変数 → 実際に使用されているか確認、export注釈を追加
3. **SC2016** (info): シングルクォート内で展開されない → 意図的なので無視
4. **SC2001** (style): sed の代わりに ${var//...} を使用 → 可読性のため維持

## 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `scripts/test.sh` | `--shellcheck` オプション追加 |
| `.github/workflows/ci.yaml` | severity を warning に変更 |
| `AGENTS.md` | shellcheckインストール手順を追記 |
| `scripts/improve.sh` | SC2034 警告修正 |
| `scripts/init.sh` | SC2034 警告修正 |
| `lib/workflow.sh` | SC2034 警告修正 |
| `.shellcheckrc` | 新規作成、プロジェクト設定 |

## 実装ステップ

### Step 1: .shellcheckrc 作成
プロジェクトルートに設定ファイルを作成し、意図的に無視する警告を定義

### Step 2: 既存警告の修正
- 未使用変数に `export` を追加、または不要な変数を削除

### Step 3: scripts/test.sh 拡張
- `--shellcheck` オプションを追加
- shellcheckが利用可能な場合のみ実行

### Step 4: CI設定の改善
- severity を `warning` に変更
- shellcheck オプション `-x` を追加

### Step 5: AGENTS.md 更新
- shellcheckのインストール手順を追記
- test.sh --shellcheck の使用例を追加

## テスト方針

1. `./scripts/test.sh --shellcheck` が正常に動作すること
2. shellcheckがインストールされていない環境でスキップされること
3. CI上でshellcheckが正常に実行されること

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存CIが失敗する可能性 | severity を段階的に厳格化 |
| shellcheck未インストール時のエラー | コマンド存在チェックで回避 |
| 誤検知による警告 | .shellcheckrc で明示的に除外 |

## 見積もり

30-45分
