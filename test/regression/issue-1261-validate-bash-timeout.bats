#!/usr/bin/env bats
# Regression test for Issue #1261
# _validate_bash() should use timeout to prevent long-running bats tests
# from blocking CI fix validation.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/ci-fix/bash.sh"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "_validate_bash uses timeout for bats execution" {
    mkdir -p "$BATS_TEST_TMPDIR/proj/scripts" "$BATS_TEST_TMPDIR/proj/test"
    touch "$BATS_TEST_TMPDIR/proj/scripts/run.sh"

    local bats_args_file="$BATS_TEST_TMPDIR/bats_args.log"
    local timeout_args_file="$BATS_TEST_TMPDIR/timeout_args.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$BATS_TEST_TMPDIR/mocks/timeout" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" > "$timeout_args_file"
# Execute the actual command (skip timeout arg)
shift
"\$@"
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" > "$bats_args_file"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/timeout" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/proj"
    run _validate_bash
    [ "$status" -eq 0 ]
    # timeout was called with default 120s
    [[ -f "$timeout_args_file" ]]
    grep -q "^120 bats" "$timeout_args_file"
}

@test "_validate_bash respects CI_FIX_BATS_TIMEOUT env var" {
    mkdir -p "$BATS_TEST_TMPDIR/proj2/scripts" "$BATS_TEST_TMPDIR/proj2/test"
    touch "$BATS_TEST_TMPDIR/proj2/scripts/run.sh"

    local timeout_args_file="$BATS_TEST_TMPDIR/timeout_args2.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$BATS_TEST_TMPDIR/mocks/timeout" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" > "$timeout_args_file"
shift
"\$@"
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/timeout" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
    export CI_FIX_BATS_TIMEOUT=60

    cd "$BATS_TEST_TMPDIR/proj2"
    run _validate_bash
    [ "$status" -eq 0 ]
    grep -q "^60 bats" "$timeout_args_file"

    unset CI_FIX_BATS_TIMEOUT
}

@test "_validate_bash returns 0 on bats timeout (exit code 124)" {
    mkdir -p "$BATS_TEST_TMPDIR/proj3/scripts" "$BATS_TEST_TMPDIR/proj3/test"
    touch "$BATS_TEST_TMPDIR/proj3/scripts/run.sh"

    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    # Mock timeout to simulate timeout (exit 124)
    cat > "$BATS_TEST_TMPDIR/mocks/timeout" << 'EOF'
#!/usr/bin/env bash
exit 124
EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/timeout"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/proj3"
    run _validate_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"timed out"* ]]
    [[ "$output" == *"skipping"* ]]
}

@test "_validate_bash returns 1 on bats failure (non-timeout)" {
    mkdir -p "$BATS_TEST_TMPDIR/proj4/scripts" "$BATS_TEST_TMPDIR/proj4/test"
    touch "$BATS_TEST_TMPDIR/proj4/scripts/run.sh"

    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    # Mock timeout to simulate test failure (exit 1)
    cat > "$BATS_TEST_TMPDIR/mocks/timeout" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/timeout"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/proj4"
    run _validate_bash
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bats test failed"* ]]
}
