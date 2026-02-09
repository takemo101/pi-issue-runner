#!/usr/bin/env bats
# test/regression/issue-1211-uninstall-missing-commands.bats
# 回帰テスト: uninstall.sh が install.sh の全コマンドをカバーしていることを検証

load '../test_helper'

@test "uninstall.sh covers all commands from install.sh" {
    local install_cmds uninstall_cmds diff_output

    install_cmds=$(grep -oE "pi-[a-z-]+" "$PROJECT_ROOT/install.sh" | sort -u)
    uninstall_cmds=$(grep -oE "pi-[a-z-]+" "$PROJECT_ROOT/uninstall.sh" | sort -u)

    diff_output=$(comm -23 <(echo "$install_cmds") <(echo "$uninstall_cmds"))

    if [[ -n "$diff_output" ]]; then
        echo "Commands in install.sh but missing from uninstall.sh:"
        echo "$diff_output"
        return 1
    fi
}

@test "install and uninstall round-trip leaves no files" {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # Install
    INSTALL_DIR="$tmp_dir" run "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]

    # Verify files were created
    local file_count
    file_count=$(find "$tmp_dir" -name 'pi-*' -type f | wc -l | tr -d ' ')
    [ "$file_count" -gt 0 ]

    # Uninstall
    INSTALL_DIR="$tmp_dir" run "$PROJECT_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]

    # Verify no pi-* files remain
    local remaining
    remaining=$(find "$tmp_dir" -name 'pi-*' -type f | wc -l | tr -d ' ')
    if [[ "$remaining" -ne 0 ]]; then
        echo "Remaining files after uninstall:"
        find "$tmp_dir" -name 'pi-*' -type f
        return 1
    fi

    rm -rf "$tmp_dir"
}
