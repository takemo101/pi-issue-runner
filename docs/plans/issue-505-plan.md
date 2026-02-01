# 実装計画: Issue #505

## 概要

README.md の「インストールされるコマンド」表に重複して記載されている `pi-force-complete` エントリを削除する。

## 影響範囲

- `README.md` のみ（1箇所の削除）

## 実装ステップ

1. README.md の「インストールされるコマンド」表を確認
2. 重複している `pi-force-complete` の2つ目のエントリを削除
3. 削除後の整合性を確認

## テスト方針

- 手動検証:
  - `grep -c "pi-force-complete" README.md` で2を確認（表内1回 + SKILL.md参照で1回）
  - または `grep "pi-force-complete.*セッション強制完了" README.md | wc -l` で1を確認

## リスクと対策

- **リスク**: 誤って正しいエントリを削除する
- **対策**: 表の順序を確認し、正しい位置（pi-cleanupの後、pi-improveの前）にある1つ目は残し、2つ目（pi-watchの後、pi-initの前）を削除

## 修正内容

削除対象行:
```markdown
| `pi-force-complete` | セッション強制完了 |
```

この行が表内に2回出現するため、2つ目を削除する。
