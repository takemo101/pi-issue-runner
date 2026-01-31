# Issue #174 実装計画書

## 概要

`improve.sh`でpiを実行した際、`| tee`でパイプすることでpiがTTYではなくパイプに接続されていると認識し、ターミナル幅を取得できなくなる問題を修正する。

## 原因分析

**現在のコード** (line ~205):
```bash
if ! "$pi_command" --message "$review_prompt" 2>&1 | tee "$output_file"; then
```

パイプ (`|`) を使用すると、piの標準出力がパイプに接続され、isatty()がfalseを返すため、ターミナル幅の自動検出ができなくなる。

## 影響範囲

- **変更ファイル**: `scripts/improve.sh`
- **変更箇所**: `review_and_create_issues` 関数内のpi実行部分（1箇所）

## 解決策の選択

Issue に記載された4つの解決策を検討:

| 方法 | メリット | デメリット | 採用 |
|------|---------|-----------|------|
| 1. scriptコマンド | PTYを完全に維持 | macOS/Linux間で構文が異なる | × |
| 2. COLUMNS環境変数 | シンプル、クロスプラットフォーム | pi側のサポートが必要 | ○ |
| 3. プロセス置換 | teeを維持しつつTTY接続 | 一部のシェルで非対応の可能性 | × |
| 4. --widthオプション | 明示的な幅指定 | piがサポートしていない可能性 | × |

**採用: 方法2 (COLUMNS環境変数)**

理由:
- シンプルで理解しやすい
- macOSとLinux両方で動作
- piは内部で`$COLUMNS`を参照している可能性が高い

## 実装ステップ

1. `review_and_create_issues` 関数内のpi実行前にターミナル幅を取得
2. `COLUMNS`環境変数を設定してpiを実行
3. 既存の`| tee`とエラーハンドリングは維持

### 変更コード

```bash
# Before
if ! "$pi_command" --message "$review_prompt" 2>&1 | tee "$output_file"; then

# After
local cols
cols=$(tput cols 2>/dev/null || echo 120)
if ! COLUMNS="$cols" "$pi_command" --message "$review_prompt" 2>&1 | tee "$output_file"; then
```

## テスト方針

### 手動テスト
1. `./scripts/improve.sh --dry-run` を実行
2. piの出力がターミナル幅いっぱいに表示されることを確認
3. 出力ファイルへの保存が正常に動作することを確認

### 環境テスト
- macOSで動作確認
- (可能であれば) Linuxで動作確認

## リスクと対策

| リスク | 対策 |
|-------|------|
| piがCOLUMNSを無視する | フォールバック値(120)を使用しているため最悪でも動作する |
| tput colsが失敗する | `|| echo 120`でフォールバック |

## 見積もり

- 実装: 10分
- テスト: 15分
- レビュー・マージ: 10分
- **合計: 35分**
