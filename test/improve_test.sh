#!/usr/bin/env bash
# improve_test.sh - Tests for improve.sh issue number extraction

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_array_equals() {
    local description="$1"
    shift
    local -a expected=()
    local -a actual=()
    
    # Parse expected and actual arrays
    local parsing_expected=true
    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            parsing_expected=false
            continue
        fi
        if $parsing_expected; then
            expected+=("$arg")
        else
            actual+=("$arg")
        fi
    done
    
    if [[ "${expected[*]:-}" == "${actual[*]:-}" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: (${expected[*]:-})"
        echo "  Actual:   (${actual[*]:-})"
        ((TESTS_FAILED++)) || true
    fi
}

# Function to extract issue numbers (same logic as improve.sh)
extract_issue_numbers() {
    local input_file="$1"
    local max_issues="${2:-5}"
    
    sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$input_file" \
        | grep -oE '[0-9]+' \
        | head -n "$max_issues"
}

# ==================== Tests ====================

echo "=== improve.sh issue extraction tests ==="
echo ""

# Test 1: Normal case - no leading spaces
test_normal_case() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
Some output from pi...
###CREATED_ISSUES###
152
153
154
###END_ISSUES###
Done.
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Normal case: extracts issue numbers without spaces" \
        "152" "153" "154" -- "${result[@]}"
}

# Test 2: Leading spaces - the bug case
test_leading_spaces() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
Some output from pi...
 ###CREATED_ISSUES###
 152
 153
 154
 ###END_ISSUES###
Done.
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Leading spaces: extracts issue numbers with leading spaces" \
        "152" "153" "154" -- "${result[@]}"
}

# Test 3: Trailing spaces
test_trailing_spaces() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
###CREATED_ISSUES###
152  
153	
154   
###END_ISSUES###
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Trailing spaces: extracts issue numbers with trailing spaces" \
        "152" "153" "154" -- "${result[@]}"
}

# Test 4: Mixed spaces (leading and trailing)
test_mixed_spaces() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
   ###CREATED_ISSUES###
   152   
   153   
   ###END_ISSUES###
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Mixed spaces: extracts issue numbers with mixed spaces" \
        "152" "153" -- "${result[@]}"
}

# Test 5: No markers found
test_no_markers() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
Some output without markers
152
153
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "No markers: returns empty array" \
        -- "${result[@]:-}"
}

# Test 6: Empty between markers
test_empty_between_markers() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
###CREATED_ISSUES###
###END_ISSUES###
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Empty between markers: returns empty array" \
        -- "${result[@]:-}"
}

# Test 7: Max issues limit
test_max_issues_limit() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
###CREATED_ISSUES###
1
2
3
4
5
6
7
###END_ISSUES###
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file" 3)
    
    rm -f "$tmp_file"
    
    assert_array_equals "Max issues limit: respects limit of 3" \
        "1" "2" "3" -- "${result[@]}"
}

# Test 8: Single issue number
test_single_issue() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
###CREATED_ISSUES###
 999
###END_ISSUES###
EOF
    
    local -a result=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && result+=("$line")
    done < <(extract_issue_numbers "$tmp_file")
    
    rm -f "$tmp_file"
    
    assert_array_equals "Single issue: extracts single issue number" \
        "999" -- "${result[@]}"
}

# Run all tests
test_normal_case
test_leading_spaces
test_trailing_spaces
test_mixed_spaces
test_no_markers
test_empty_between_markers
test_max_issues_limit
test_single_issue

# Summary
echo ""
echo "=========================================="
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "=========================================="

exit $TESTS_FAILED
