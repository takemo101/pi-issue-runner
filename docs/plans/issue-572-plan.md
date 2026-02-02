# Issue #572 Implementation Plan

## 概要

`./scripts/test.sh` のテスト実行時間を60秒以内に短縮するための最適化を実施します。

## 現状分析

### テストファイル数
- lib/ ディレクトリ: 24ファイル
- scripts/ ディレクトリ: 14ファイル
- 合計: 38テストファイル

### ボトルネック特定

実行時間計測結果:

| テストファイル | 実行時間 | 主な原因 |
|---------------|---------|---------|
| cleanup-orphans.bats | 45秒 | `touch -t` によるタイムスタンプ操作 |
| daemon.bats | 34秒 | `sleep 10`, `sleep 30`, 30秒ループ |
| status.bats | タイムアウト | `touch -t` によるタイムスタンプ操作 |
| config.bats | 16秒 | 設定ファイルの繰り返し読み込み |
| notify.bats | 15秒 | 不明（要調査） |

### 根本原因

1. **`touch -t` コマンドの遅延**: 特定の日時を設定する `touch -t 202001010000` がmacOSで遅い
2. **`sleep` コマンド**: daemon.bats で長時間の sleep を使用
3. **逐次実行**: テストが並列実行されていない

## 実装ステップ

### Step 1: 並列実行の有効化（scripts/test.sh）

- `bats --jobs 4` オプションを追加
- 環境変数 `BATS_JOBS` で並列度を制御可能に

### Step 2: 遅いテストの修正

#### daemon.bats
- `sleep 10` → `sleep 0.5` に短縮
- `sleep 30` → `sleep 2` に短縮
- 30秒ループ → 3秒ループに短縮

#### cleanup-orphans.bats
- `touch -t` の使用を減らす
- テスト間でファイルを再利用して削減

#### status.bats
- `touch -t` の使用を減らす
- または、`touch -t` をモック化

### Step 3: 高速モードの追加

- `--fast` フラグを追加
- 重いテスト（daemon, sleep含む）をスキップ

### Step 4: 検証

- 最適化前後の実行時間を比較
- 目標: 60秒以内

## 影響範囲

### 変更対象ファイル

1. `scripts/test.sh` - 並列実行、高速モード追加
2. `test/lib/daemon.bats` - sleep時間短縮
3. `test/lib/cleanup-orphans.bats` - touch -t最適化
4. `test/lib/status.bats` - touch -t最適化

### 非対象
- テストロジックの変更なし
- 機能的な変更なし

## リスクと対策

| リスク | 対策 |
|-------|------|
| sleep短縮でテストが不安定になる | 必要最小限のsleep時間を維持 |
| 並列実行でテストが衝突 | 各テストで独立したtmpdirを使用 |
| touch -t削除でカバレッジ低下 | 代替テスト手法で補完 |

## テスト方針

1. 最適化後の `./scripts/test.sh` を実行
2. 目標時間（60秒以内）を達成することを確認
3. 全テストがパスすることを確認

## 完了条件

- [ ] 並列実行が有効化されている
- [ ] daemon.bats の実行時間が5秒以内
- [ ] cleanup-orphans.bats の実行時間が10秒以内
- [ ] status.bats の実行時間が10秒以内
- [ ] 全体の実行時間が60秒以内
