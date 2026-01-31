# Issue #141 実装計画

## 概要

ドキュメント（AGENTS.md, README.md）と実態の不整合を修正する。

## 影響範囲

- `AGENTS.md` - ディレクトリ構造とテンプレート変数表
- `README.md` - ディレクトリ構造

## 実装ステップ

### P1: 高優先度

1. **AGENTS.md の post-session.sh 参照を削除**
   - ディレクトリ構造から `│   └── post-session.sh # セッション終了後処理` を削除

2. **README.md の post-session.sh 参照を削除**
   - ディレクトリ構造から `│   ├── post-session.sh     # セッション終了後処理` を削除

3. **README.md の tests/ ディレクトリ参照を削除**
   - ディレクトリ構造から `├── tests/                   # Batsテスト` を削除

### P2: 中優先度

4. **AGENTS.md のテンプレート変数表を更新**
   - 追加する変数:
     - `{{issue_title}}` - Issueタイトル
     - `{{step_name}}` - 現在のステップ名
     - `{{workflow_name}}` - ワークフロー名

## テスト方針

- 変更はドキュメントのみなので自動テストは不要
- 目視で変更内容を確認

## リスクと対策

- リスク: 低（ドキュメント変更のみ）
- 対策: git diff で変更内容を確認

## 見積もり

- 作業時間: 約5分
