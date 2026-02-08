#!/usr/bin/env bash
# ci-fix/detect.sh - プロジェクトタイプ検出
#
# プロジェクトの種類を自動検出します。
# 検出優先順位: rust > node > python > go > bash > unknown

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_DETECT_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_DETECT_SH_SOURCED="true"

# プロジェクトタイプを検出
# Usage: detect_project_type [worktree_path]
# Returns: rust | node | python | go | bash | unknown
detect_project_type() {
    local worktree_path="${1:-.}"
    
    # Rust: Cargo.toml の存在
    if [[ -f "$worktree_path/Cargo.toml" ]]; then
        echo "rust"
        return 0
    fi
    
    # Node/JavaScript: package.json の存在
    if [[ -f "$worktree_path/package.json" ]]; then
        echo "node"
        return 0
    fi
    
    # Python: pyproject.toml または setup.py の存在
    if [[ -f "$worktree_path/pyproject.toml" ]] || [[ -f "$worktree_path/setup.py" ]]; then
        echo "python"
        return 0
    fi
    
    # Go: go.mod の存在
    if [[ -f "$worktree_path/go.mod" ]]; then
        echo "go"
        return 0
    fi
    
    # Bash: *.bats ファイルまたは test/test_helper.bash の存在
    # shellcheck disable=SC2144
    if ls "$worktree_path"/*.bats &>/dev/null || [[ -f "$worktree_path/test/test_helper.bash" ]]; then
        echo "bash"
        return 0
    fi
    
    echo "unknown"
    return 1
}
