# Issue #352 実装計画

## improve.sh: pi-issue-runnerで作成したIssueのみを処理するようにする

### 概要

`improve.sh`の継続的改善フローにおいて、複数のセッションが同時実行された場合に他のセッションで作成されたIssueも処理されてしまう問題を解決します。セッションごとにユニークなラベルを付与し、そのラベルを持つIssueのみを処理するようにします。

### 影響範囲

1. **lib/github.sh** - ラベル関連の関数追加
2. **scripts/improve.sh** - ラベル生成・フィルタリング・オプション追加
3. **test/lib/github.bats** - 新機能のテスト追加
4. **test/scripts/improve.bats** - 新機能のテスト追加

### 実装ステップ

#### Step 1: lib/github.sh にラベル関連関数を追加

```bash
# セッションラベル生成（例: pi-runner-20260201-082900）
generate_session_label() {
    echo "pi-runner-$(date +%Y%m%d-%H%M%S)"
}

# ラベルを作成（存在しない場合のみ）
create_label_if_not_exists() {
    local label="$1"
    local description="${2:-"Created by pi-issue-runner session"}"
    # gh label createを使用
}

# get_issues_created_afterにラベルフィルタを追加
get_issues_created_after() {
    local start_time="$1"
    local max_issues="${2:-20}"
    local label="${3:-}"  # 新規: オプショナルなラベルフィルタ
    # --label オプションを追加
}
```

#### Step 2: scripts/improve.sh の修正

1. **変数追加**:
   - `session_label` - セッションラベルを保持

2. **オプション追加**:
   - `--label LABEL` - カスタムラベル名を指定（未指定時は自動生成）

3. **Phase 1（レビュー・Issue作成）の修正**:
   - プロンプトにラベル付与を指示（`--label`を`gh issue create`に使用）

4. **Phase 2（Issue取得）の修正**:
   - `get_issues_created_after`にラベルを渡してフィルタ

5. **Phase 5（次イテレーション）の修正**:
   - `--label`オプションを再帰呼び出しに引き継ぐ

### テスト方針

#### ユニットテスト（test/lib/github.bats）

1. `generate_session_label` が正しい形式でラベルを生成する
2. `create_label_if_not_exists` が正しくghコマンドを呼び出す
3. `get_issues_created_after` がラベルフィルタを適用する

#### 統合テスト（test/scripts/improve.bats）

1. `--label`オプションが正しく解析される
2. ヘルプに`--label`オプションが表示される
3. ラベルが再帰呼び出しに引き継がれる

### リスクと対策

| リスク | 対策 |
|--------|------|
| ラベル作成時の権限不足 | エラーハンドリングを追加し、警告を表示して続行 |
| 同一秒に複数セッション開始 | 秒精度で十分だが、必要なら$RANDOMを追加可能 |
| 既存のラベルと衝突 | `pi-runner-`プレフィックスで識別可能 |
| gh labelコマンドの非互換性 | 標準的なghコマンドを使用し、エラーをキャッチ |

### 受け入れ基準チェックリスト

- [ ] `improve.sh` 実行時にセッション固有のラベルが自動生成される
- [ ] 作成されたIssueにのみそのセッションのラベルが付く
- [ ] `improve.sh` はそのセッションのラベル付きIssueのみを処理する
- [ ] 複数の `improve.sh` を同時実行しても、それぞれ独立して動作する
- [ ] `--label` オプションでラベル名を手動指定できる
- [ ] 既存のテストが通る
- [ ] 新しい機能のテストが追加されている
