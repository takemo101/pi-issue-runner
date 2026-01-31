# Issue #132 実装計画書

## 概要
docs/configuration.mdに残っている`.yml`拡張子を`.yaml`に統一する。

## 影響範囲
- `docs/configuration.md` のみ

## 発見した`.yml`箇所

| 行番号 | 内容 | 対応 |
|--------|------|------|
| 13 | `~/.pi-runner/config.yml` | `.yaml`に変更 |
| 345 | `path.join(os.homedir(), '.pi-runner/config.yml')` | `.yaml`に変更 |
| 364 | `ext === '.yml' \|\| ext === '.yaml'` | **維持**（両拡張子サポートのロジック） |
| 482 | `./custom-config.yml` | `.yaml`に変更 |
| 575 | `.pi-runner.dev.yml`, `.pi-runner.prod.yml` | `.yaml`に変更 |

## 実装ステップ

1. Line 13: `~/.pi-runner/config.yml` → `~/.pi-runner/config.yaml`
2. Line 345: `'.pi-runner/config.yml'` → `'.pi-runner/config.yaml'`
3. Line 482: `custom-config.yml` → `custom-config.yaml`
4. Line 575: `.pi-runner.dev.yml`, `.pi-runner.prod.yml` → `.pi-runner.dev.yaml`, `.pi-runner.prod.yaml`

**注意**: Line 364は両拡張子をサポートするコードなので変更しない。

## テスト方針

```bash
# 変更後、.ymlがドキュメント中に残っていないか確認
# （ただしコード例の拡張子チェックロジックを除く）
grep '\.yml' docs/configuration.md | grep -v "ext === '\\.yml'"
```

## リスク

- リスク: なし（ドキュメントのみの変更）
