# 実装計画: Issue #184

## 概要

SKILL.md に記載されている `improve.sh` のオプションを完全な一覧に更新します。

## 現状分析

### SKILL.md（現在の状態）
```bash
scripts/improve.sh                    # レビュー→Issue作成→実行→待機のループ
scripts/improve.sh --dry-run          # レビューのみ
```

### improve.sh の実際のオプション（usage関数より）
- `--max-iterations N` - 最大イテレーション数（デフォルト: 3）
- `--max-issues N` - 1回あたりの最大Issue数（デフォルト: 5）
- `--auto-continue` - 承認ゲートをスキップ（自動継続）
- `--dry-run` - レビューのみ実行（Issue作成・実行しない）
- `--timeout <sec>` - 各イテレーションのタイムアウト（デフォルト: 3600）
- `--review-only` - project-reviewスキルで問題を表示するのみ
- `-v, --verbose` - 詳細ログを表示
- `-h, --help` - このヘルプを表示

### README.md（参考：より詳細な記載あり）
既に主要なオプションが記載されているが、SKILL.mdとは記載量が異なる。

## 影響範囲

- `SKILL.md` - クイックリファレンスセクション内の `improve.sh` 記載部分

## 実装ステップ

1. SKILL.md の `improve.sh` セクションを更新
   - 主要なオプションを追加: `--review-only`, `--max-iterations`, `--auto-continue`
   - コメントを正確に更新

2. README.md との整合性確認
   - 両ファイルの記載が矛盾しないことを確認

## テスト方針

- ドキュメントのみの変更のため、シェルスクリプトテストは不要
- 記載内容が `improve.sh --help` の出力と整合していることを確認

## リスクと対策

- リスク: 将来のオプション変更時に再び不整合が発生する可能性
- 対策: AGENTS.md にドキュメント更新のリマインダーを記載（今回のスコープ外）
