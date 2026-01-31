# Issue #170 実装計画書

## 概要

新しいプロジェクトでpi-issue-runnerを使い始める際に、必要な初期ファイル（`.pi-runner.yaml`、`.worktrees/`ディレクトリ、`.gitignore`更新）を自動生成する `init.sh` スクリプトを追加する。

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `scripts/init.sh` | 新規作成 - メイン初期化スクリプト |
| `install.sh` | `pi-init` コマンドを追加 |
| `README.md` | `pi-init` の使い方を追記 |
| `test/init_test.sh` | 新規作成 - 単体テスト |

## 実装ステップ

### Step 1: scripts/init.sh の作成

1. **オプション解析**
   - `--full`: 完全セットアップ（agents/, workflows/ も作成）
   - `--minimal`: 最小セットアップ（.pi-runner.yaml のみ）
   - `--force`: 既存ファイルを上書き
   - `-h, --help`: ヘルプ表示

2. **初期化処理**
   - `.pi-runner.yaml` の生成
   - `.worktrees/` ディレクトリ作成 + `.gitkeep`
   - `.gitignore` の更新（既存エントリ確認）
   - `--full` 時: `agents/custom.md` と `workflows/custom.yaml` 作成

3. **エラーハンドリング**
   - 既存ファイル検出時の警告
   - Git リポジトリ外での実行時のエラー

### Step 2: install.sh への追加

`pi-init:scripts/init.sh` をコマンドマッピングに追加。

### Step 3: テスト作成

`test/init_test.sh` で以下をテスト：
- 標準モードでの各ファイル生成
- `--full` モードでの追加ファイル生成
- `--minimal` モードでの最小ファイル生成
- `--force` による上書き
- 既存ファイル検出時の警告

### Step 4: README.md 更新

「インストールされるコマンド」表に `pi-init` を追加し、使用例を記載。

## テスト方針

1. **単体テスト** (`test/init_test.sh`)
   - 一時ディレクトリで各モードをテスト
   - ファイル内容の検証
   - 既存ファイル検出の検証

2. **手動テスト**
   - 実際のプロジェクトでの動作確認
   - `.gitignore` の重複エントリ防止確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存ファイルの誤上書き | デフォルトでは上書きせず警告を表示。`--force` で明示的に上書き |
| Git リポジトリ外での実行 | エラーを出力して終了 |
| `.gitignore` への重複追加 | 既存エントリをチェックしてからのみ追加 |

## 完了条件

- [x] 実装計画書を作成した（このファイル）
- [ ] `scripts/init.sh` が正常に動作する
- [ ] `.pi-runner.yaml` が作成される
- [ ] `.worktrees/` ディレクトリが作成される
- [ ] `.gitignore` が更新される（既存エントリがあればスキップ）
- [ ] `--full` オプションで agents/, workflows/ も作成される
- [ ] `--force` オプションで上書きできる
- [ ] 既存ファイルがある場合は警告を表示
- [ ] `install.sh` に `pi-init` を追加
- [ ] README に使い方を追記
- [ ] テストがパスする
