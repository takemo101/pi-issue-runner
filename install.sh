#!/usr/bin/env bash
# install.sh - pi-issue-runner をグローバルにインストール
#
# 使用方法:
#   ./install.sh
#   INSTALL_DIR=/usr/local/bin ./install.sh
#
# ラッパースクリプトを INSTALL_DIR に作成します。

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# コマンドマッピング（command:script 形式）
COMMANDS="
pi-run:scripts/run.sh
pi-list:scripts/list.sh
pi-attach:scripts/attach.sh
pi-status:scripts/status.sh
pi-stop:scripts/stop.sh
pi-cleanup:scripts/cleanup.sh
pi-improve:scripts/improve.sh
pi-wait:scripts/wait-for-sessions.sh
pi-watch:scripts/watch-session.sh
pi-init:scripts/init.sh
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
