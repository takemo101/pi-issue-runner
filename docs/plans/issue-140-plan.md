# 実装計画: GitHub Actions CI/CDワークフローの追加

## Issue #140

## 概要

PR/pushに対してCI（継続的インテグレーション）を実行するGitHub Actionsワークフローを追加する。主に以下を自動化する：
- ShellCheck による静的解析
- ユニットテストの実行

## 影響範囲

### 新規作成ファイル
- `.github/workflows/ci.yaml` - メインCIワークフロー

### 関連する既存ファイル（変更なし）
- `scripts/*.sh` - 静的解析対象
- `lib/*.sh` - 静的解析対象
- `test/*_test.sh` - テスト実行対象

## 実装ステップ

### 1. ディレクトリ構造の作成
```
.github/
└── workflows/
    └── ci.yaml
```

### 2. CIワークフローの実装

#### トリガー設定
- `push`: main/developブランチへのプッシュ
- `pull_request`: すべてのPR

#### ジョブ構成

1. **shellcheck** ジョブ
   - `ludeeus/action-shellcheck@master` を使用
   - `scripts/` と `lib/` ディレクトリをスキャン
   - 重大なエラーでCIを失敗させる

2. **unit-tests** ジョブ
   - 必要な依存関係をインストール（jq, yq, tmux）
   - `test/*_test.sh` を順次実行
   - 任意のテスト失敗でCIを失敗させる

#### マトリクス戦略
- ubuntu-latest（必須）
- macos-latest（オプション、コメントアウト）

### 3. 依存関係の設定
- jq: JSONパーサー（apt/brew）
- yq: YAMLパーサー（バイナリインストール）
- tmux: テスト実行環境

## テスト方針

1. **ローカルテスト**
   - 既存の全テストが通過することを確認
   - shellcheckでエラーがないことを確認

2. **CIテスト**
   - PRを作成してCIが正しく動作することを確認
   - CIステータスがPRに表示されることを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| shellcheckで既存コードにエラーがある | 警告レベルを調整、または事前に修正 |
| macOSでテストが異なる動作をする | 一旦Linuxのみで開始、後でmacOS追加 |
| テストがCI環境で失敗する | 必要な依存関係を明示的にインストール |
| yqのインストールが複雑 | バイナリダウンロードで対応 |

## 受け入れ条件（Issueより）

- [x] PRで自動的にCIが実行される → ワークフローのトリガー設定で対応
- [x] shellcheckでエラーがあればCIが失敗する → shellcheckジョブで対応
- [x] ユニットテストが失敗したらCIが失敗する → unit-testsジョブで対応
- [x] CIステータスがPRに表示される → GitHub Actionsのデフォルト動作
