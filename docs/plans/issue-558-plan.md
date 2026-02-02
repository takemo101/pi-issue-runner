# Implementation Plan: Issue #558

## 概要

AGENTS.md のディレクトリ構造セクションに、実際に存在するが記載されていない2つのファイルを追加するドキュメント修正です。

## 変更対象

### 1. `lib/daemon.sh` の追加
- **位置**: `lib/dependency.sh` の後
- **追加内容**:
```
│   ├── daemon.sh      # プロセスデーモン化
```

### 2. `scripts/nudge.sh` の追加
- **位置**: `scripts/improve.sh` の後
- **追加内容**:
```
│   ├── nudge.sh       # セッションへメッセージ送信
```

## 実装ステップ

1. AGENTS.md を編集して `lib/daemon.sh` を追加
2. AGENTS.md を編集して `scripts/nudge.sh` を追加
3. 検証コマンドで欠落がないことを確認

## テスト方針

Issue に記載されている検証コマンドを実行して、すべてのファイルが存在することを確認:

```bash
grep -E "^\s+[├└].*\.sh" AGENTS.md | sed "s/.*[├└]── //" | sed "s/ .*$//" | while read f; do
  test -f "lib/$f" || test -f "scripts/$f" || echo "Missing: $f"
done
```

## リスクと対策

- **リスク**: なし（純粋なドキュメント修正）
- **対策**: 検証コマンドで変更前後のファイル存在確認を実行

## 完了条件

- [ ] `lib/daemon.sh` をAGENTS.mdのlib/セクションに追加
- [ ] `scripts/nudge.sh` をAGENTS.mdのscripts/セクションに追加
- [ ] 検証コマンドで欠落なし
