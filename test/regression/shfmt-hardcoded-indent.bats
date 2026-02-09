#!/usr/bin/env bats
# test/regression/shfmt-hardcoded-indent.bats
# Issue #1245: shfmt should not hardcode -i 4

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    source "$PROJECT_ROOT/lib/ci-fix/bash.sh"
}

@test "_fix_format_bash does not pass -i option to shfmt" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shfmt" << 'MOCK_EOF'
#!/usr/bin/env bash
# Fail if -i option is passed (hardcoded indent size)
for arg in "$@"; do
    if [[ "$arg" == "-i" || "$arg" =~ ^-i[0-9] ]]; then
        echo "ERROR: shfmt should not receive -i option (hardcoded indent size)" >&2
        exit 1
    fi
done
echo "shfmt executed without -i option"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"shfmt executed without -i option"* ]]
}
