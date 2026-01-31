# 実装計画: Issue #328 - 複数コーディングエージェント対応

## 概要

現在 `pi` コマンド専用の実行ロジックを汎用化し、Claude Code、OpenCode等の他のコーディングエージェントでも動作するようにする。

## 影響範囲

### 変更が必要なファイル

| ファイル | 変更内容 |
|---------|---------|
| `lib/agent.sh` | **新規作成** - エージェント実行ロジック |
| `lib/config.sh` | `agent` セクションのパース追加 |
| `scripts/run.sh` | コマンド生成を `agent.sh` に委譲 |
| `docs/configuration.md` | `agent` 設定の説明追加 |
| `README.md` | マルチエージェント対応の説明追加 |
| `test/lib/agent.bats` | **新規作成** - agent.sh のテスト |
| `test/lib/config.bats` | agent設定のテスト追加 |

### 新規作成ファイル

| ファイル | 目的 |
|---------|------|
| `lib/agent.sh` | エージェント実行コマンドの生成 |
| `test/lib/agent.bats` | agent.sh のBatsテスト |

## 実装ステップ

### Step 1: lib/agent.sh の作成

1. プリセット定義（pi, claude, opencode）
2. コマンド生成関数 `build_agent_command`
3. プリセット取得関数 `get_agent_preset`
4. 設定からエージェント情報を取得する関数

**プリセット定義:**
```bash
# pi プリセット
AGENT_PRESET_PI_COMMAND="pi"
AGENT_PRESET_PI_PROMPT_STYLE="@file"
AGENT_PRESET_PI_TEMPLATE='{{command}} {{args}} @"{{prompt_file}}"'

# claude プリセット
AGENT_PRESET_CLAUDE_COMMAND="claude"
AGENT_PRESET_CLAUDE_PROMPT_STYLE="positional"
AGENT_PRESET_CLAUDE_TEMPLATE='{{command}} {{args}} --print "{{prompt_file}}"'

# opencode プリセット
AGENT_PRESET_OPENCODE_COMMAND="opencode"
AGENT_PRESET_OPENCODE_PROMPT_STYLE="stdin"
AGENT_PRESET_OPENCODE_TEMPLATE='cat "{{prompt_file}}" | {{command}} {{args}}'
```

**主要関数:**
```bash
# エージェント実行コマンドを構築
build_agent_command() {
    local prompt_file="$1"
    local extra_args="$2"
    # 設定からテンプレートを取得し、変数を置換
}

# プリセット情報を取得
get_agent_preset() {
    local preset_name="$1"
    # プリセット情報を返す
}
```

### Step 2: lib/config.sh の拡張

1. `agent` セクションのパース追加
2. 新しい設定変数の追加:
   - `CONFIG_AGENT_TYPE` (pi | claude | opencode | custom)
   - `CONFIG_AGENT_COMMAND`
   - `CONFIG_AGENT_PROMPT_STYLE`
   - `CONFIG_AGENT_TEMPLATE`
   - `CONFIG_AGENT_ARGS`
3. 既存の `pi` セクションを後方互換として維持

**設定の優先順位:**
1. `agent` セクションが設定されている場合、それを使用
2. `agent` セクションがない場合、`pi` セクションにフォールバック

### Step 3: scripts/run.sh の修正

1. `lib/agent.sh` の読み込み追加
2. コマンド生成を `build_agent_command` に委譲
3. 既存の pi 固有コード削除

**変更前:**
```bash
local full_command="$pi_command $pi_args $extra_pi_args @\"$prompt_file\""
```

**変更後:**
```bash
local full_command
full_command="$(build_agent_command "$prompt_file" "$extra_pi_args")"
```

### Step 4: テスト作成

1. `test/lib/agent.bats` 新規作成
   - プリセット取得テスト
   - コマンド生成テスト
   - カスタムテンプレートテスト
2. `test/lib/config.bats` 拡張
   - agent設定のパーステスト

### Step 5: ドキュメント更新

1. `docs/configuration.md` に `agent` セクションの説明追加
2. `README.md` にマルチエージェント対応の概要追加

## テスト方針

### ユニットテスト

| テストケース | 説明 |
|------------|------|
| `build_agent_command returns pi preset command` | piプリセットのコマンド生成 |
| `build_agent_command returns claude preset command` | claudeプリセットのコマンド生成 |
| `build_agent_command returns opencode preset command` | opencodeプリセットのコマンド生成 |
| `build_agent_command uses custom template` | カスタムテンプレートの使用 |
| `get_agent_preset returns correct values` | プリセット値の取得 |
| `config parses agent section` | agent設定のパース |
| `config falls back to pi section` | pi設定へのフォールバック |

### 統合テスト

| テストケース | 説明 |
|------------|------|
| `run.sh uses agent config` | run.shでagent設定が反映される |
| `run.sh falls back to pi when no agent config` | agent設定なし時のフォールバック |

## リスクと対策

### リスク1: 後方互換性の破壊

**対策:** 
- `pi` セクションの既存設定を維持
- `agent` セクションが未設定の場合は従来どおり `pi` セクションを使用
- テストで後方互換性を検証

### リスク2: 各エージェントの実際のコマンド構文が不明確

**対策:**
- プリセットは一般的な構文で定義
- `custom` タイプで任意のテンプレートを指定可能
- ドキュメントに調査結果と注意事項を記載

### リスク3: 完了マーカーの互換性

**対策:**
- 完了マーカーはプロンプトで指示する形式なので、どのエージェントでも対応可能と想定
- 動作確認ができない場合はドキュメントに制限事項を記載

## 設定例

### 最小構成（後方互換）

```yaml
# 既存の設定のまま動作
pi:
  command: pi
```

### 新規構成（agent セクション使用）

```yaml
# Claude Code を使用
agent:
  type: claude

# OpenCode を使用
agent:
  type: opencode

# カスタムエージェント
agent:
  type: custom
  command: my-agent
  template: '{{command}} --prompt "{{prompt_file}}" {{args}}'
```

## 完了条件

- [ ] `lib/agent.sh` が作成され、全プリセットが定義されている
- [ ] `lib/config.sh` で `agent` セクションがパースできる
- [ ] `scripts/run.sh` が `agent.sh` を使用してコマンドを生成する
- [ ] 既存の `pi` 設定のみの場合も正常に動作する（後方互換）
- [ ] Batsテストが全てパスする
- [ ] ドキュメントが更新されている
- [ ] ShellCheckでエラーがない
