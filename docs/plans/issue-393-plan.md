# Issue #393 実装計画書

## 概要

CIが継続的に失敗している問題を修正する。

## 調査結果

### 問題1: action-shellcheckのscandirパラメータ
- `scandir: "./scripts ./lib"` が正しく解析されていなかった
- `find: './scripts ./lib': No such file or directory` エラーが発生

### 問題2: test.shのrun_bats_tests関数
- batsコマンドの終了コードが正しく親関数に返されていなかった
- すべてのテストがパスしても終了コード1で失敗していた

### 問題3: test/test_helper.bashのSC2155警告
- `export VAR=$(command)` の形式でShellCheck警告が発生
- severity: warning の設定によりCIが失敗

## 実装ステップ

1. ✅ CIワークフローの修正
   - `scandir: "."` に変更（カレントディレクトリをスキャン）

2. ✅ test.shの修正
   - `run_bats_tests` 関数で `bats` コマンドの終了コードを明示的に返す

3. ✅ test/test_helper.bashの修正
   - 変数の宣言と代入を分離（SC2155警告対応）

## テスト結果

- ShellCheck: ✅ パス
- Unit Tests: 一部既存の環境依存テストが失敗（cleanup関連）
  - これらは本Issueのスコープ外（別途対応が必要）

## 変更ファイル

1. `.github/workflows/ci.yaml`
2. `scripts/test.sh`
3. `test/test_helper.bash`

## コミット

- `1d46c8e` fix: CIが継続的に失敗している問題の修正
- `8933d90` fix: ShellCheck SC2155警告の修正
