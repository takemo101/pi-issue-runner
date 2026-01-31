# Issue #171 Implementation Plan

## 概要

`lib/github.sh` の `detect_dangerous_patterns` 関数の戻り値ロジックを改善し、Bashの標準的な規約に従った直感的な実装に変更する。

## 問題点の詳細

### 現在の実装

```bash
detect_dangerous_patterns() {
    # ...
    return $found  # 危険パターンあり: 1, なし: 0
}

# 呼び出し側
if ! detect_dangerous_patterns "$body" 2>/dev/null; then
    log_info "sanitizing..."
fi
```

### 問題

- Bashでは戻り値0=true/成功、非0=false/失敗が規約
- 関数名「detect」は検出成功時に0を返すべき
- `if !` を使った条件分岐が分かりにくい

## 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `lib/github.sh` | 関数リネーム、戻り値ロジック変更 |
| `test/github_test.sh` | テストケースの更新 |

## 実装ステップ

### Step 1: 関数のリネームと戻り値変更

`detect_dangerous_patterns` → `has_dangerous_patterns`

```bash
# has_dangerous_patterns - 危険なパターンが含まれているかチェック
# 戻り値: 0=危険なパターンあり(true), 1=安全(false)
has_dangerous_patterns() {
    local text="$1"
    
    # コマンド置換 $(...)
    if echo "$text" | grep -qE '\$\([^)]+\)'; then
        log_warn "Dangerous pattern detected: command substitution \$(...)  "
        return 0  # 危険あり = true
    fi
    
    # バッククォート `...`
    if echo "$text" | grep -q '`[^`]*`'; then
        log_warn "Dangerous pattern detected: backtick command \`...\`"
        return 0  # 危険あり = true
    fi
    
    # 変数展開 ${...}
    if echo "$text" | grep -qE '\$\{[^}]+\}'; then
        log_warn "Dangerous pattern detected: variable expansion \${...}"
        return 0  # 危険あり = true
    fi
    
    return 1  # 安全 = false
}
```

### Step 2: 呼び出し側の更新

```bash
# Before
if ! detect_dangerous_patterns "$body" 2>/dev/null; then
    log_info "sanitizing..."
fi

# After
if has_dangerous_patterns "$body" 2>/dev/null; then
    log_info "Issue body contains potentially dangerous patterns, sanitizing..."
fi
```

### Step 3: テストの更新

テストコードも新しい関数名と戻り値に合わせて更新する。

## テスト方針

1. 既存の `test/github_test.sh` のテストを更新
2. 安全なテキスト → `has_dangerous_patterns` は 1 (false) を返す
3. 危険なテキスト → `has_dangerous_patterns` は 0 (true) を返す
4. サニタイズ処理が正常に動作することを確認

## リスクと対策

| リスク | 対策 |
|-------|------|
| 関数名変更による互換性問題 | 外部から呼ばれる関数ではないため影響は限定的 |
| テストの見落とし | 全テストを実行して確認 |

## 完了条件

- [x] 関数の動作とコメントが一致している
- [x] 呼び出し側のコードが直感的に理解できる
- [x] 既存のテストがパスする
