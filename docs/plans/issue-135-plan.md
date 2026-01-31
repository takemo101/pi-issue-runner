# Implementation Plan: Issue #135

## refactor: post-session.sh関連の冗長コード削除

### 概要

watch-session.shへの移行が完了したため、post-session.sh関連の冗長コードを削除する。
現在、run.shはwatch-session.shを使用して完了マーカーを監視し、cleanup.shを実行している。
post-session.shとlib/tmux.shのpost-session関連コードは不要になった。

### 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `lib/tmux.sh` | create_session関数からpost-session.sh関連ロジックを削除 |
| `scripts/post-session.sh` | ファイル削除 |
| `test/post_session_test.sh` | ファイル削除 |

### 現在の動作フロー

```
run.sh
  ├── create_session (lib/tmux.sh)
  │   └── [冗長] post-session.sh呼び出しロジック + remain-on-exit設定
  └── watch-session.sh をバックグラウンド起動
      └── 完了マーカー検出時に cleanup.sh 実行
```

### 変更後の動作フロー

```
run.sh
  ├── create_session (lib/tmux.sh) - シンプルなセッション作成のみ
  └── watch-session.sh をバックグラウンド起動
      └── 完了マーカー検出時に cleanup.sh 実行
```

### 実装ステップ

1. **lib/tmux.sh の修正**
   - `create_session`関数を簡略化
   - `cleanup_mode`と`issue_number`パラメータを削除
   - `remain-on-exit`設定を削除
   - post-session.sh呼び出しロジックを削除

2. **scripts/post-session.sh の削除**
   - ファイルを完全に削除

3. **test/post_session_test.sh の削除**
   - ファイルを完全に削除

4. **run.sh の修正**
   - `create_session`呼び出しを新しいシグネチャに合わせる

5. **テスト実行**
   - 全テストがパスすることを確認

### テスト方針

- 既存テスト（tmux_test.sh等）がパスすることを確認
- 手動テスト: `./scripts/run.sh <issue> --no-attach` でセッション作成確認

### リスクと対策

| リスク | 対策 |
|-------|------|
| 既存テストの失敗 | post-session.shに依存するテストを削除 |
| run.shの呼び出し変更 | create_sessionのシグネチャ変更に合わせて修正 |

### 推定

- 行数変更: 約-100行（削除主体）
- ファイル: 4つ（修正2、削除2）
