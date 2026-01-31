# Issue #125 - 設定ファイル拡張子の不整合修正 実装計画

## 概要

ドキュメントとテストで使用されている設定ファイルの拡張子を `.pi-runner.yml` から `.pi-runner.yaml` に統一する。

## 影響範囲

| ファイル | 変更箇所 | 変更内容 |
|----------|---------|---------|
| `docs/SPECIFICATION.md` | 2箇所 | `.pi-runner.yml` → `.pi-runner.yaml` |
| `docs/configuration.md` | 8箇所 | `.pi-runner.yml` → `.pi-runner.yaml` |
| `docs/worktree-management.md` | 1箇所 | `.pi-runner.yml` → `.pi-runner.yaml` |
| `test/critical_fixes_test.sh` | 1箇所 | テスト対象を `.pi-runner.yaml` に変更 |
| `test/fixtures/sample-config.yml` | ファイル名 | `sample-config.yaml` にリネーム |

## 実装ステップ

### Step 1: ドキュメント修正
1. `docs/SPECIFICATION.md` の2箇所を修正
2. `docs/configuration.md` の8箇所を修正
3. `docs/worktree-management.md` の1箇所を修正

### Step 2: テスト修正
1. `test/critical_fixes_test.sh` のテスト対象を変更
   - `assert_contains "config uses .pi-runner.yml"` → `assert_contains "config uses .pi-runner.yaml"`

### Step 3: テストフィクスチャ修正
1. `test/fixtures/sample-config.yml` を `sample-config.yaml` にリネーム

### Step 4: 検証
1. 全テスト実行（192件全パス確認）
2. grep で `.pi-runner.yml` が残っていないことを確認

## テスト方針

- 既存テストの実行（`./test/critical_fixes_test.sh`）
- 全テストスイートの実行

## リスクと対策

| リスク | 対策 |
|-------|------|
| 他に未発見の参照がある | grepで網羅的に検索して確認 |
| テストフィクスチャが使用されている可能性 | grep で参照を確認 |

## 見積もり

15分
