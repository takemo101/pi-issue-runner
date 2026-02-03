#!/usr/bin/env bash
# uninstall.sh - pi-issue-runner をアンインストール
#
# 使用方法:
#   ./uninstall.sh
#   INSTALL_DIR=/usr/local/bin ./uninstall.sh
#
# install.sh で作成したラッパースクリプトを削除します。

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# コマンド一覧
COMMANDS="
pi-run
pi-batch
pi-list
pi-attach
pi-status
pi-stop
pi-cleanup
pi-force-complete
pi-improve
pi-wait
pi-watch
pi-init
pi-nudge
pi-context
"

echo "Uninstalling pi-issue-runner from $INSTALL_DIR..."

removed_count=0
for cmd in $COMMANDS; do
    # 空行をスキップ
    [[ -z "$cmd" ]] && continue
    
    wrapper="$INSTALL_DIR/$cmd"
    
    # ラッパースクリプトが存在し、pi-issue-runnerのものであるか確認
    if [[ -f "$wrapper" ]] && grep -q "pi-issue-runner" "$wrapper" 2>/dev/null; then
        rm "$wrapper"
        echo "  ✓ Removed $cmd"
        ((removed_count++)) || true
    fi
done

echo ""
if [[ $removed_count -eq 0 ]]; then
    echo "ℹ️  削除するコマンドがありませんでした"
else
    echo "✅ アンインストール完了！ ($removed_count コマンドを削除)"
fi
