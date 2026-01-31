# 実装計画書: Issue #262

## 概要

`config.sh`と`workflow.sh`が異なるYAMLパーサーを使用している問題を修正し、共通の`lib/yaml.sh`を作成して統一する。

## 現状分析

### config.sh
- **パーサー**: 独自実装（`_parse_config_file`関数）
- **特徴**: 
  - line-by-line解析
  - セクション（worktree, tmux, pi等）を認識
  - 配列形式（`- item`）をサポート
  - 外部依存なし

### workflow.sh
- **パーサー**: `yq`（外部コマンド）
- **特徴**:
  - `check_yq()`で存在確認
  - 存在しない場合はビルトインにフォールバック
  - `.workflow.steps[]`などのパス指定をサポート

## 影響範囲

### 変更対象ファイル
1. `lib/yaml.sh` - 新規作成
2. `lib/config.sh` - yaml.shを使用するよう修正
3. `lib/workflow.sh` - yaml.shを使用するよう修正

### テストファイル
4. `test/lib/yaml.bats` - 新規作成
5. `test/lib/config.bats` - 必要に応じて更新
6. `test/lib/workflow.bats` - 必要に応じて更新

## 実装ステップ

### Step 1: lib/yaml.sh 作成

```bash
# 主要関数
check_yq()              # yqの存在確認（キャッシュ機能付き）
yaml_get()              # 単一値取得
yaml_get_array()        # 配列取得
_simple_yaml_get()      # フォールバック用簡易パーサー
_simple_yaml_get_array() # フォールバック用配列パーサー
```

### Step 2: lib/config.sh 修正

- `_parse_config_file()`の代わりに`yaml_get()`/`yaml_get_array()`を使用
- フォールバック処理は`yaml.sh`に委譲

### Step 3: lib/workflow.sh 修正

- 独自の`check_yq()`を削除し、`yaml.sh`の関数を使用
- `get_workflow_steps()`内のyq呼び出しを`yaml_get_array()`に置き換え

### Step 4: テスト追加

- `test/lib/yaml.bats`を新規作成
- yqがある場合/ない場合のテスト
- 既存テストが引き続きパスすることを確認

## テスト方針

1. **ユニットテスト**: `yaml.sh`の各関数をテスト
   - `yaml_get`の基本動作
   - `yaml_get_array`の基本動作
   - yqなし環境でのフォールバック
   
2. **統合テスト**: 既存テストの実行
   - `test/lib/config.bats` - すべてパス
   - `test/lib/workflow.bats` - すべてパス

3. **手動テスト**:
   - yqをPATHから除外して動作確認
   - 実際の`.pi-runner.yaml`での動作確認

## リスクと対策

### リスク1: 既存機能の破壊
- **対策**: 既存テストをすべてパスさせる。修正前にテストを実行し、修正後も同じ結果を得る。

### リスク2: フォールバックパーサーの機能不足
- **対策**: config.shの既存パーサーロジックを活用し、必要な機能をカバー。

### リスク3: パフォーマンス低下
- **対策**: yqが利用可能な場合は優先使用。キャッシュ機能を維持。

## 完了条件

- [ ] `lib/yaml.sh`が新規作成されている
- [ ] `config.sh`が`lib/yaml.sh`を使用している
- [ ] `workflow.sh`が`lib/yaml.sh`を使用している
- [ ] yqがない環境でも動作する（フォールバック）
- [ ] すべての既存テストがパス
- [ ] 新しいテスト（`test/lib/yaml.bats`）が追加されている
