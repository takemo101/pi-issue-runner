# Issue #181 実装計画書

## 概要

`improve.sh` でpiコマンドを実行する際、パイプ (`|`) を通すと標準出力がTTYではなくパイプになるため、piがターミナル幅を認識できず、表示幅が狭くなる問題を修正する。

## 問題の原因

現在のコード:
```bash
COLUMNS="$cols" stdbuf -oL "$pi_command" --message "$review_prompt" 2>&1 | stdbuf -oL tee "$output_file"
```

- `COLUMNS` 環境変数を設定しても、パイプ経由ではpiが `isatty()` でチェックするとTTYではないと判定される
- その結果、ターミナル幅が取得できず、狭い幅（通常80カラム）でフォールバックする

## 影響範囲

- `scripts/improve.sh` - `review_and_create_issues` 関数

## 実装ステップ

### 1. PTY保持関数の作成

`run_pi_interactive` ヘルパー関数を作成:

1. **方法1 (推奨)**: `script` コマンドでPTY（疑似端末）を作成
   - macOS: `script -q "$output_file" command...`
   - Linux: `script -q -c "command..." "$output_file"`

2. **方法2**: `unbuffer` コマンド（expectパッケージ）を使用

3. **方法3 (フォールバック)**: 従来どおりのパイプ（幅が狭くなる可能性あり）

### 2. improve.sh の修正

- `review_and_create_issues` 関数内のpiコマンド実行部分を新しいヘルパー関数に置き換え

### 3. macOS/Linux両対応

- `script` コマンドのオプションがOSで異なるため、`uname` で判定して切り替え

## テスト方針

1. **単体テスト**: 関数単体の動作確認は難しいため、手動テストが中心
2. **手動テスト**: 
   - `./scripts/improve.sh --dry-run` で表示幅を確認
   - macOSとLinux（Docker等）で動作確認
3. **フォールバック確認**: `script`/`unbuffer` がない環境でのフォールバック動作

## リスクと対策

| リスク | 対策 |
|--------|------|
| `script` コマンドが環境によって動作が異なる | OSを判定し、適切なオプションを使用 |
| `unbuffer` がインストールされていない | フォールバックを用意 |
| 出力ファイルへの保存が正しく行われない | `script` は直接ファイルに出力するため問題なし |

## 受け入れ条件チェックリスト

- [ ] piがターミナル幅いっぱいに表示される
- [ ] 出力ファイルへの保存機能は維持される
- [ ] macOSとLinux両方で動作する
- [ ] script/unbufferがない環境でもフォールバックで動作する
