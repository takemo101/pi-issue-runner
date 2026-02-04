# 実装計画書: Issue #363

## 概要

`scripts/init.sh` の `GITIGNORE_ENTRIES` に、pi-issue-runnerが生成するファイル/ディレクトリのエントリを追加する。

## 現状分析

### メインブランチの `GITIGNORE_ENTRIES`

```bash
GITIGNORE_ENTRIES="
# pi-issue-runner
.worktrees/
.improve-logs/
.pi-runner.yaml.local
.pi-runner.yaml
.pi-prompt.md
*.swp
"
```

### Issue で追加が求められているエントリ

| エントリ | 説明 | 生成元 | 状態 |
|---------|------|--------|------|
| `.improve-logs/` | improve.shのログディレクトリ | `scripts/improve.sh` | ✅ 既存 |
| `.pi-runner.yml` | 設定ファイル（yml形式） | ユーザー作成の可能性 | ⚠️ 追加必要 |
| `.pi-prompt.md` | プロンプトファイル | ユーザー作成の可能性 | ✅ 既存 |

### 問題点

現在のブランチ（issue-363-init-sh-gitignore）では：
- `.pi-runner.yaml` が削除されている
- `.pi-runner.yml` が追加されている

**これは間違い**: 両方の拡張子（`.yaml` と `.yml`）をサポートする必要がある。

## 影響範囲

### 変更ファイル
- `scripts/init.sh` - `GITIGNORE_ENTRIES` の修正

### テストファイル
- `test/scripts/init.bats` - 既にテストが存在（`.pi-runner.yml` のテストあり）

### 関連ドキュメント
- なし（`.gitignore` エントリの追加のみ）

## 実装ステップ

### 1. `scripts/init.sh` の修正

現在のブランチの `GITIGNORE_ENTRIES` を以下に修正：

```bash
GITIGNORE_ENTRIES="
# pi-issue-runner
.worktrees/
.improve-logs/
.pi-runner.yaml.local
.pi-runner.yaml
.pi-runner.yml
.pi-prompt.md
*.swp
"
```

**重要**: `.pi-runner.yaml` と `.pi-runner.yml` の両方を含めること。

### 2. テストの実行

```bash
./scripts/test.sh scripts/init
```

特に以下のテストが通ることを確認：
- `init.sh adds .pi-runner.yml to .gitignore`
- 既存の全テストがパス

### 3. 手動確認

```bash
cd /tmp/test-init
git init
/path/to/pi-issue-runner/scripts/init.sh
cat .gitignore
```

`.gitignore` に以下のエントリがすべて含まれることを確認：
- `.worktrees/`
- `.improve-logs/`
- `.pi-runner.yaml.local`
- `.pi-runner.yaml`
- `.pi-runner.yml`
- `.pi-prompt.md`
- `*.swp`

### 4. コミット

```bash
git add scripts/init.sh
git commit -m "fix: .gitignoreに.pi-runner.yamlと.pi-runner.ymlの両方を追加

Refs #363"
```

## テスト方針

### 既存テストの確認

`test/scripts/init.bats` に以下のテストが存在：

```bash
@test "init.sh adds .pi-runner.yml to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.pi-runner\.yml' ".gitignore"
}
```

このテストは現在の修正でパスするはず。

### 追加テスト（オプション）

`.pi-runner.yaml` のテストがない場合は追加を検討：

```bash
@test "init.sh adds .pi-runner.yaml to .gitignore" {
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    grep -q '\.pi-runner\.yaml' ".gitignore"
}
```

### テスト実行順序

1. ユニットテスト: `./scripts/test.sh lib`
2. スクリプトテスト: `./scripts/test.sh scripts/init`
3. 統合テスト: 実際のプロジェクトでの動作確認

## リスクと対策

### リスク1: 既存の `.gitignore` エントリの重複

**対策**: `init.sh` は既に重複チェック機能を実装済み
```bash
if [[ -f "$gitignore" ]] && grep -qF "$entry" "$gitignore" 2>/dev/null; then
    continue
fi
```

### リスク2: `.pi-runner.yaml` エントリの削除

**対策**: 明示的に両方のエントリ（`.yaml` と `.yml`）を含める

### リスク3: テストの失敗

**対策**: 
- テスト実行前に変更内容を確認
- 失敗した場合は ShellCheck で構文チェック

## 受け入れ基準

- [x] `.pi-runner.yml` が `GITIGNORE_ENTRIES` に追加されている
- [x] `.pi-runner.yaml` が `GITIGNORE_ENTRIES` に残っている
- [ ] `./scripts/test.sh scripts/init` が全てパス
- [ ] 手動テストで `.gitignore` に両エントリが追加される
- [ ] ShellCheck 警告なし

## 参考情報

### 関連コード

- `scripts/init.sh`: 初期化スクリプト（156-164行目付近）
- `test/scripts/init.bats`: 初期化スクリプトのテスト
- `lib/config.sh`: 設定ファイル読み込み（`.yaml` と `.yml` 両対応）

### 既存の設定ファイルサポート

`lib/config.sh` では以下の優先順位で設定ファイルを検索：
1. `PI_RUNNER_CONFIG` 環境変数
2. `.pi-runner.yaml.local`
3. `.pi-runner.yml.local`
4. `.pi-runner.yaml`
5. `.pi-runner.yml`

このため、両方の拡張子をサポートする必要がある。

## タイムライン

- **計画作成**: 完了
- **実装**: 5分（1ファイルの修正のみ）
- **テスト**: 5分
- **レビュー**: 5分
- **合計**: 約15分
