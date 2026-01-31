# Issue #134 実装計画: watch-session.sh ユニットテスト作成

## 概要
`scripts/watch-session.sh` のユニットテストを作成する。このスクリプトはtmuxセッションの出力を監視し、完了マーカーを検出したら自動的にcleanup.shを実行する。

## 影響範囲
- 新規ファイル: `test/watch_session_test.sh`

## テスト対象機能

### 1. マーカー検出ロジック
watch-session.shの核心機能は、ベースラインと比較して新しいマーカーを検出すること:
- `marker_count_baseline` と `marker_count_current` の比較
- 新しいマーカー（current > baseline）のみ検出

### 2. Issue番号抽出
`extract_issue_number` 関数（lib/tmux.shで定義）を使用:
- セッション名からIssue番号を正しく抽出
- 不正なセッション名でのエラーハンドリング

### 3. 引数処理
- `--marker <text>`: カスタムマーカー指定
- `--interval <sec>`: 監視間隔指定
- `--help`: ヘルプ表示

## 実装ステップ

1. テストファイル作成 (`test/watch_session_test.sh`)
2. テストヘルパー関数の実装
3. マーカー検出テストの実装
4. Issue番号抽出テストの実装
5. 引数処理テストの実装
6. テスト実行と検証

## テスト方針
- 既存のテストパターン（`test/tmux_test.sh`等）に従う
- tmux依存のテストはモック/スキップで対応
- 純粋なロジックテストに焦点

## リスクと対策
- **リスク**: tmuxがインストールされていない環境でのテスト失敗
- **対策**: tmux依存のテストは`command -v tmux`でスキップ条件を設定

## 推定
- 行数: 約150行
- 所要時間: 短時間
