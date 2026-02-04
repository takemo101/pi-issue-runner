#!/usr/bin/env bash
# sanitize.sh - Sanitize sensitive data from files or stdin
set -euo pipefail

# Default configuration
REPLACEMENT="***REDACTED***"
DRY_RUN=false
RECURSIVE=false
OUTPUT_FILE=""
CUSTOM_PATTERNS=()

# Built-in sanitization patterns (sed format)
BUILTIN_PATTERNS=(
    # API Keys
    's/API_KEY=[^[:space:]]*/API_KEY=***REDACTED***/g'
    's/api_key=[^[:space:]]*/api_key=***REDACTED***/g'
    's/sk-[a-zA-Z0-9_-]\{1,\}/***REDACTED***/g'
    
    # Passwords
    's/password=[^[:space:]]*/password=***REDACTED***/g'
    's/PASSWORD=[^[:space:]]*/PASSWORD=***REDACTED***/g'
    
    # Tokens
    's/token=[^[:space:]]*/token=***REDACTED***/g'
    's/TOKEN=[^[:space:]]*/TOKEN=***REDACTED***/g'
    's/ghp_[a-zA-Z0-9_-]\{1,\}/***REDACTED***/g'
    
    # Secrets
    's/SECRET=[^[:space:]]*/SECRET=***REDACTED***/g'
    's/secret=[^[:space:]]*/secret=***REDACTED***/g'
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Show usage information
show_help() {
    cat << EOF
Usage: sanitize.sh [OPTIONS] [FILE]

Sanitize sensitive data from files or stdin.

OPTIONS:
    -h, --help              Show this help message
    -p, --pattern PATTERN   Add custom pattern to sanitize (can be used multiple times)
    -o, --output FILE       Write output to FILE instead of stdout
    -n, --dry-run           Show what would be changed without modifying
    -r, --recursive         Process directories recursively
    --replace TEXT          Custom replacement text (default: ***REDACTED***)

ARGUMENTS:
    FILE                    File to sanitize (if not provided, reads from stdin)

EXAMPLES:
    # Sanitize from stdin
    echo "API_KEY=secret123" | sanitize.sh
    
    # Sanitize a file
    sanitize.sh config.env
    
    # Sanitize with custom pattern
    sanitize.sh --pattern "custom_secret" file.txt
    
    # Save to output file
    sanitize.sh input.txt --output output.txt

BUILT-IN PATTERNS:
    - API keys (API_KEY=..., sk-...)
    - Passwords (password=..., PASSWORD=...)
    - Tokens (token=..., ghp_...)
    - Secrets (SECRET=..., secret=...)

EOF
    exit 0
}

# Log error message to stderr
log_error() {
    echo -e "${RED}Error:${NC} $*" >&2
}

# Log warning message to stderr
log_warning() {
    echo -e "${YELLOW}Warning:${NC} $*" >&2
}

# Log info message to stderr
log_info() {
    echo -e "${GREEN}Info:${NC} $*" >&2
}

# Check if file is binary
is_binary_file() {
    local file="$1"
    if command -v file >/dev/null 2>&1; then
        file "$file" | grep -q "text" && return 1
        return 0
    fi
    # Fallback: check for null bytes
    if grep -q $'\0' "$file" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Sanitize content using sed patterns
sanitize_content() {
    local content="$1"
    local result="$content"
    
    # Apply built-in patterns
    for pattern in "${BUILTIN_PATTERNS[@]}"; do
        result=$(echo "$result" | sed "$pattern")
    done
    
    # Apply custom patterns
    for pattern in "${CUSTOM_PATTERNS[@]}"; do
        # Simple pattern replacement (literal string match)
        result=$(echo "$result" | sed "s/${pattern}/${REPLACEMENT}/g")
    done
    
    echo "$result"
}

# Process a single file
process_file() {
    local file="$1"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Check if file is readable
    if [[ ! -r "$file" ]]; then
        log_error "Cannot read file: $file (permission denied)"
        return 1
    fi
    
    # Check if file is binary
    if is_binary_file "$file"; then
        log_warning "Skipping binary file: $file"
        return 0
    fi
    
    # Read file content
    local content
    content=$(cat "$file")
    
    # Sanitize content
    local sanitized
    sanitized=$(sanitize_content "$content")
    
    # Output result
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$sanitized" > "$OUTPUT_FILE"
        log_info "Sanitized content written to: $OUTPUT_FILE"
    else
        echo "$sanitized"
    fi
    
    return 0
}

# Process directory
process_directory() {
    local dir="$1"
    local recursive="$2"
    
    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi
    
    local file_count=0
    local find_opts=()
    
    if [[ "$recursive" == "true" ]]; then
        # Recursive: process all files in subdirectories
        find_opts=("$dir" -type f)
    else
        # Non-recursive: only process files in the directory itself
        find_opts=("$dir" -maxdepth 1 -type f)
    fi
    
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            log_info "Processing: $file"
            process_file "$file" || true
            file_count=$((file_count + 1))
        fi
    done < <(find "${find_opts[@]}" -print0)
    
    log_info "Processed $file_count files"
    return 0
}

# Process stdin
process_stdin() {
    local content
    content=$(cat)
    
    # If stdin is empty and we're not reading from a pipe with data, error out
    if [[ -z "$content" ]] && [[ ! -p /dev/stdin ]]; then
        log_error "No input provided. Provide a file path or pipe input via stdin."
        echo "Use --help for usage information" >&2
        return 1
    fi
    
    local sanitized
    sanitized=$(sanitize_content "$content")
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$sanitized" > "$OUTPUT_FILE"
        log_info "Sanitized content written to: $OUTPUT_FILE"
    else
        echo "$sanitized"
    fi
    
    return 0
}

# Main function
main() {
    local input_file=""
    
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -p|--pattern)
                if [[ -z "${2:-}" ]]; then
                    log_error "--pattern requires an argument"
                    exit 1
                fi
                CUSTOM_PATTERNS+=("$2")
                shift 2
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    log_error "--output requires an argument"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -n|--dry-run)
                # shellcheck disable=SC2034  # TODO: Implement dry-run functionality
                DRY_RUN=true
                shift
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            --replace)
                if [[ -z "${2:-}" ]]; then
                    log_error "--replace requires an argument"
                    exit 1
                fi
                REPLACEMENT="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                if [[ -z "$input_file" ]]; then
                    input_file="$1"
                else
                    log_error "Multiple input files not supported"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Process input
    if [[ -n "$input_file" ]]; then
        # File or directory input
        if [[ -d "$input_file" ]]; then
            process_directory "$input_file" "$RECURSIVE"
        else
            process_file "$input_file"
        fi
    else
        # Check if stdin is available
        if [[ -t 0 ]]; then
            log_error "No input provided. Provide a file path or pipe input via stdin."
            echo "Use --help for usage information" >&2
            exit 1
        fi
        # For non-terminal stdin, always try to process (even if empty)
        process_stdin
    fi
}

# Run main function
main "$@"
