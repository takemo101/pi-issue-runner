# Issue #570 実装計画

## 概要

`lib/hooks.sh` でインラインフックコマンドを `eval` で実行している箇所に、セキュリティ警告ログを追加します。また、関連ドキュメントにセキュリティ注意事項を明記します。

## 影響範囲

### 変更対象ファイル
1. `lib/hooks.sh` - eval実行前に警告ログを追加
2. `docs/security.md` - 既存のHookセキュリティセクションを確認・更新
3. `README.md` - Hook機能セクションにセキュリティ警告を追加

### 依存関係
- `lib/log.sh` - `log_warn` 関数を使用

## 実装ステップ

### Step 1: lib/hooks.sh の修正

`_execute_hook()` 関数内の `eval "$hook"` の前に警告ログを追加:

```bash
# インラインコマンドとして実行
log_warn "Executing inline hook command (security note: ensure this is from a trusted source)"
log_debug "Executing inline hook"
eval "$hook"
```

### Step 2: docs/security.md の確認・更新

既存の「Hook機能のセキュリティリスク」セクションを確認し、必要に応じて以下を追加:
- eval使用時の警告ログ出力について言及
- 推奨事項の明確化

### Step 3: README.md の更新

「Hook機能」セクションにセキュリティ警告を追加:
- インラインフックのリスクについて言及
- `.pi-runner.yaml` の信頼性について警告
- `docs/security.md` へのリンク

## テスト方針

1. **単体テスト**: `test/lib/hooks.bats` を実行して既存テストがパスすることを確認
2. **手動テスト**: 警告ログが実際に出力されることを確認
3. **ドキュメント確認**: 変更後のドキュメントを読んで整合性を確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存機能への影響 | 警告ログのみ追加、evalの動作は変更しない |
| テスト失敗 | 既存テストを実行して確認 |
| ドキュメントの不整合 | 各ファイル間で表現を統一 |

## 完了条件

- [ ] `lib/hooks.sh` のeval前に警告ログが追加されている
- [ ] `docs/security.md` にセキュリティ情報が適切に記載されている
- [ ] `README.md` のHook機能セクションに警告が追加されている
- [ ] 既存のテストが全てパスする
- [ ] 変更がコミットされる
