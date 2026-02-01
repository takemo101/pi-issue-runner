#!/usr/bin/env bash
# run_test.sh - pi command argument format validation tests
# Issue #13: fix: correct pi command argument format
#
# This test validates that the pi command is constructed correctly:
# - Arguments should be separate (not combined in a single quoted string)
# - Flags like --auto should be separate from the prompt/issue number
#
# Usage:
#   bash test/run_test.sh

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
}

info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# Initialize variables needed by libraries (must be before set -u)
_CONFIG_LOADED=""

# Now enable strict mode for unbound variables
set -u

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the libraries
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/agent.sh"

info "Testing pi command argument format (Issue #13)"
echo ""

# ============================================
# Test 1: Verify command arguments are separate
# ============================================
test_args_separate() {
    info "Test 1: Arguments should be separate, not combined"
    
    # Create a test config with args
    local test_config
    test_config="$(mktemp)"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--auto"
EOF
    
    # Reset config and load test config
    _CONFIG_LOADED=""
    load_config "$test_config"
    
    # Build command with a prompt file
    local cmd
    cmd="$(build_agent_command "/tmp/test-prompt.md" "")"
    
    # Check that --auto is in the command and not combined with other args
    if [[ "$cmd" == *"--auto"* ]] && [[ "$cmd" != *"\"--auto\""* ]]; then
        pass "Arguments are properly separated (not over-quoted)"
    else
        fail "Arguments may be incorrectly quoted: $cmd"
    fi
    
    # Cleanup
    rm -f "$test_config"
}

# ============================================
# Test 2: Verify extra args are properly appended
# ============================================
test_extra_args() {
    info "Test 2: Extra arguments should be properly appended"
    
    local test_config
    test_config="$(mktemp)"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
EOF
    
    _CONFIG_LOADED=""
    load_config "$test_config"
    
    local cmd
    cmd="$(build_agent_command "/tmp/test-prompt.md" "--verbose")"
    
    # The command should contain --verbose as a separate argument
    if [[ "$cmd" == *" --verbose "* ]] || [[ "$cmd" == *" --verbose@"* ]]; then
        pass "Extra arguments are properly appended"
    else
        fail "Extra arguments not properly appended: $cmd"
    fi
    
    rm -f "$test_config"
}

# ============================================
# Test 3: Verify correct pi template format
# ============================================
test_pi_template_format() {
    info "Test 3: pi template should have correct format"
    
    local template
    template="$(get_agent_preset "pi" "template")"
    
    # The template should have {{args}} separate from {{prompt_file}}
    if [[ "$template" == *'{{command}} {{args}} @"{{prompt_file}}"'* ]]; then
        pass "pi template has correct format with separate args"
    else
        fail "pi template may have incorrect format: $template"
    fi
}

# ============================================
# Test 4: Verify command not constructed with combined args
# ============================================
test_no_combined_args() {
    info "Test 4: Command should not have combined quoted arguments"
    
    local test_config
    test_config="$(mktemp)"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--model"
    - "gpt-4"
EOF
    
    _CONFIG_LOADED=""
    load_config "$test_config"
    
    local cmd
    cmd="$(build_agent_command "/tmp/test.md" "")"
    
    # Should NOT have format like: pi "42 --auto" or similar combined args
    if [[ "$cmd" =~ \".*--.*\" ]]; then
        fail "Command has potentially combined quoted arguments: $cmd"
    else
        pass "Command arguments are properly separated"
    fi
    
    rm -f "$test_config"
}

# ============================================
# Test 5: Verify issue number is not combined with flags
# ============================================
test_issue_number_separate() {
    info "Test 5: Issue number analogy - value should be separate from flags"
    
    # This test simulates the original issue scenario:
    # INCORRECT: pi "42 --auto"
    # CORRECT:   pi --auto "42"
    
    local test_config
    test_config="$(mktemp)"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--auto"
EOF
    
    _CONFIG_LOADED=""
    load_config "$test_config"
    
    local cmd
    cmd="$(build_agent_command "/tmp/issue-42-prompt.md" "")"
    
    # The --auto flag should be separate, not like "42 --auto"
    # The command should look like: pi --auto @"/tmp/issue-42-prompt.md"
    if [[ "$cmd" == *" --auto "* ]] || [[ "$cmd" == *" --auto@"* ]]; then
        pass "Flag is properly separated from other values"
    else
        fail "Flag may be incorrectly combined: $cmd"
    fi
    
    rm -f "$test_config"
}

# ============================================
# Test 6: Verify claude template format
# ============================================
test_claude_template_format() {
    info "Test 6: claude template should have correct format"
    
    local template
    template="$(get_agent_preset "claude" "template")"
    
    # The template should have {{args}} separate from --print and prompt_file
    if [[ "$template" == *'{{command}} {{args}} --print "{{prompt_file}}"'* ]]; then
        pass "claude template has correct format with separate args"
    else
        fail "claude template may have incorrect format: $template"
    fi
}

# ============================================
# Test 7: Test with config args and extra args combined
# ============================================
test_combined_config_and_extra_args() {
    info "Test 7: Config args and extra args should both be present and separate"
    
    local test_config
    test_config="$(mktemp)"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--model"
    - "gpt-4"
EOF
    
    _CONFIG_LOADED=""
    load_config "$test_config"
    
    local cmd
    cmd="$(build_agent_command "/tmp/test.md" "--verbose --debug")"
    
    # Should have both config args and extra args
    if [[ "$cmd" == *"--model"* ]] && [[ "$cmd" == *"gpt-4"* ]] && [[ "$cmd" == *"--verbose"* ]]; then
        pass "Config args and extra args are both present and separate"
    else
        fail "Args may be incorrectly combined: $cmd"
    fi
    
    rm -f "$test_config"
}

# ============================================
# Test 8: Verify opencode template uses stdin correctly
# ============================================
test_opencode_template_format() {
    info "Test 8: opencode template should use stdin correctly"
    
    local template
    template="$(get_agent_preset "opencode" "template")"
    
    # The template should pipe to command with separate args
    if [[ "$template" == *'cat "{{prompt_file}}" | {{command}} {{args}}'* ]]; then
        pass "opencode template has correct format"
    else
        fail "opencode template may have incorrect format: $template"
    fi
}

# ============================================
# Run all tests
# ============================================
echo "============================================"
echo "Running command format validation tests"
echo "============================================"
echo ""

test_args_separate
echo ""

test_extra_args
echo ""

test_pi_template_format
echo ""

test_no_combined_args
echo ""

test_issue_number_separate
echo ""

test_claude_template_format
echo ""

test_combined_config_and_extra_args
echo ""

test_opencode_template_format
echo ""

# Summary
echo "============================================"
echo "Test Summary"
echo "============================================"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
