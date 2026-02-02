#!/usr/bin/env bash
# install.sh - pi-issue-runner をグローバルにインストール
#
# 使用方法:
#   ./install.sh                    # ラッパースクリプトのみ
#   ./install.sh --with-deps        # 依存パッケージも含めてインストール
#   ./install.sh --deps-only        # 依存パッケージのみインストール
#   INSTALL_DIR=/usr/local/bin ./install.sh
#
# ラッパースクリプトを INSTALL_DIR に作成します。

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 必須依存パッケージ
REQUIRED_DEPS="gh tmux jq yq"

# 依存パッケージをインストール
install_dependencies() {
    # brewの確認
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew が見つかりません"
        echo ""
        echo "インストール方法:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo ""
        echo "または手動で依存パッケージをインストールしてください:"
        echo "  $REQUIRED_DEPS"
        return 1
    fi
    
    echo "📦 依存パッケージを確認中..."
    echo ""
    
    local missing=()
    
    # パッケージの確認
    for pkg in $REQUIRED_DEPS; do
        if command -v "$pkg" &> /dev/null; then
            echo "  ✓ $pkg (インストール済み)"
        else
            echo "  ○ $pkg (未インストール)"
            missing+=("$pkg")
        fi
    done
    
    echo ""
    
    # 未インストールパッケージのインストール
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "📥 パッケージをインストール中..."
        for pkg in "${missing[@]}"; do
            echo "  brew install $pkg"
            brew install "$pkg"
        done
        echo ""
    fi
    
    # piの確認（brewではインストールできない）
    if ! command -v pi &> /dev/null; then
        echo "⚠️  pi がインストールされていません"
        echo "   https://github.com/badlogic/pi を参照してインストールしてください"
        echo ""
    else
        echo "  ✓ pi (インストール済み)"
    fi
    
    echo "✅ 依存パッケージの確認完了"
}

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --with-deps     依存パッケージも含めてインストール (gh, tmux, jq, yq)
    --deps-only     依存パッケージのみインストール（ラッパー作成しない）
    -h, --help      このヘルプを表示

Environment Variables:
    INSTALL_DIR     インストール先ディレクトリ (default: ~/.local/bin)

Examples:
    $(basename "$0")                          # ラッパーのみ
    $(basename "$0") --with-deps              # ラッパー + 依存パッケージ
    $(basename "$0") --deps-only              # 依存パッケージのみ
    INSTALL_DIR=/usr/local/bin $(basename "$0")
EOF
}

# オプション解析
with_deps=false
deps_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-deps)
            with_deps=true
            shift
            ;;
        --deps-only)
            deps_only=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# 依存パッケージのインストール
if [[ "$with_deps" == "true" || "$deps_only" == "true" ]]; then
    install_dependencies
    echo ""
    
    if [[ "$deps_only" == "true" ]]; then
        exit 0
    fi
fi

# コマンドマッピング（command:script 形式）
COMMANDS="
pi-run:scripts/run.sh
pi-batch:scripts/run-batch.sh
pi-list:scripts/list.sh
pi-attach:scripts/attach.sh
pi-status:scripts/status.sh
pi-stop:scripts/stop.sh
pi-cleanup:scripts/cleanup.sh
pi-force-complete:scripts/force-complete.sh
pi-improve:scripts/improve.sh
pi-wait:scripts/wait-for-sessions.sh
pi-watch:scripts/watch-session.sh
pi-init:scripts/init.sh
pi-nudge:scripts/nudge.sh
"

echo "Installing pi-issue-runner to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

for mapping in $COMMANDS; do
    # 空行をスキップ
    [[ -z "$mapping" ]] && continue
    
    cmd="${mapping%%:*}"
    script="${mapping#*:}"
    target="$SCRIPT_DIR/$script"
    wrapper="$INSTALL_DIR/$cmd"
    
    # ターゲットが存在するか確認
    if [[ ! -f "$target" ]]; then
        echo "  ⚠️  Skipped $cmd (target not found: $script)"
        continue
    fi
    
    # ラッパースクリプトを生成
    cat > "$wrapper" << EOF
#!/usr/bin/env bash
# Auto-generated wrapper for pi-issue-runner
exec "$target" "\$@"
EOF
    chmod +x "$wrapper"
    echo "  ✓ $cmd"
done

echo ""
echo "✅ インストール完了！"
echo ""

# PATH確認
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠️  PATHに追加してください:"
    echo ""
    echo "  # bashの場合"
    echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc"
    echo ""
    echo "  # zshの場合"
    echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc"
    echo ""
    echo "  # 現在のセッションに適用"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi
