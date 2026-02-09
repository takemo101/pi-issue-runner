# 001: Test Parallel Jobs Limit (2026-02-08)

## 問題

テストスイート（`./scripts/test.sh`）が高並列度（16ジョブ）で実行時にハングする問題が発生した。

### 症状
- `./scripts/test.sh` がデフォルトで16並列ジョブで実行
- Bats がテスト計画（"1..1679"）を出力後にハング
- 単一ファイルのテスト（`bats test/lib/config.bats`）でも30秒でタイムアウト（16並列時）
- 1,679個のテストが存在

### 調査結果

```bash
# 16並列ジョブ（ハング）
$ timeout 30 bats --jobs 16 test/lib/config.bats
1..154
[ハング]

# 1ジョブ（動作）
$ timeout 60 bats --jobs 1 test/lib/config.bats
1..154
ok 1 get_config returns default worktree_base_dir
ok 2 get_config returns default session_prefix
...
[正常完了]

# 4並列ジョブ（動作するが遅い）
$ timeout 120 ./scripts/test.sh -j 4 lib
[正常完了だが時間がかかる]
```

### 原因
Batsのバージョン1.13.0で、並列度が高すぎる（16ジョブ）とテストフレームワークが内部的にハングする。
考えられる要因：
1. プロセス管理のオーバーヘッド
2. テストセットアップ/ティアダウンの競合
3. ファイルシステムI/Oの競合

## 対応

### scripts/test.sh の修正
デフォルト並列ジョブ数を 16 → 2 に変更

```bash
# 変更前
local jobs="${BATS_JOBS:-16}"

# 変更後
local jobs="${BATS_JOBS:-2}"
```

### 理由
- 2並列ジョブは安定して動作する
- 4並列でもBatsの並列実行で一時ファイル管理の競合が発生する場合がある
- macOS/Linux環境で安全な並列度
- 環境変数 `BATS_JOBS` で上書き可能（柔軟性を保持）
- 1,679テストを安定して実行できる

### 検証結果

```bash
# 1ジョブ（安定だが遅い）
$ timeout 300 ./scripts/test.sh -j 1 lib
[全テスト正常完了だが非常に遅い（~515s）]

# デフォルト（4ジョブ）で正常動作
$ timeout 300 ./scripts/test.sh lib
Running tests in parallel with 4 jobs...
[全テスト正常完了（~205s）]

# 8ジョブ以上（Bats並列実行の競合でハングのリスク）
$ BATS_JOBS=8 ./scripts/test.sh
[一時ファイル管理の競合でハングする可能性あり]

# 明示的に16ジョブ指定（非推奨）
$ BATS_JOBS=16 ./scripts/test.sh
[ほぼ確実にハング]
```

### 2026-02-09 更新: yqバッチ化による高速化

Issue #1133 の調査で、テストが遅い主原因は `config.sh` の `load_config()` が
各設定項目ごとに個別に `yq` サブプロセスを起動していたことが判明（39回/呼び出し）。

`yaml_get_bulk()` 関数を追加し、1回の `yq` 呼び出しで全項目を一括取得するよう最適化。
また `_yq_get()` も2回のyq呼び出しを1回に削減。

結果:
- config.bats: 57s → 10s（5.7x高速化）
- 全テスト: 12分 → 5分（2.4x高速化）
- デフォルトジョブ数を 2 → 4 に変更（4ジョブでも安定動作を確認）

## 教訓

### 今後の注意点
1. **並列度の設定は控えめに**: テストスイートの並列度はマシンスペックに応じて調整が必要
2. **デフォルト値の選定**: 安全性を優先し、控えめな値をデフォルトとする
3. **環境変数で上書き可能に**: ユーザーが環境に応じて調整できる柔軟性を残す
4. **CI環境での設定**: CI環境では `-j 2` や `-j 1` などさらに控えめな設定を推奨
5. **yqの呼び出し回数を最小化**: サブプロセス起動は1800+テスト×39回で深刻なボトルネックになる

### 関連する設定
- `BATS_JOBS`: 並列ジョブ数（デフォルト: 4）
- `./scripts/test.sh -j N`: コマンドライン引数で指定
- `./scripts/test.sh -j 1`: 最も安定（並列実行なし）
- `--fail-fast`: 並列実行をスキップし、1つずつ実行（最初の失敗で停止）

### 参考
- Bats version: 1.13.0
- Total tests: 1,876
- Test files: 72
