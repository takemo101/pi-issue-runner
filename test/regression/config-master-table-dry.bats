#!/usr/bin/env bats
# Regression test: config master table DRY refactoring (Issue #1130)
# Ensures that _CONFIG_MASTER is the single source of truth and
# all derived mappings are consistent.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    unset _CONFIG_LOADED
    unset _CONFIG_SH_SOURCED
    
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "all _CONFIG_MASTER entries produce valid _CONFIG_SIMPLE_MAPPINGS" {
    source "$PROJECT_ROOT/lib/config.sh"
    
    # Every master entry should have a corresponding simple mapping
    for entry in "${_CONFIG_MASTER[@]}"; do
        local yaml_path env_suffix api_key config_var
        IFS=':' read -r yaml_path env_suffix api_key config_var <<< "$entry"
        
        local found=false
        for mapping in "${_CONFIG_SIMPLE_MAPPINGS[@]}"; do
            if [[ "$mapping" == "${yaml_path}:${config_var}" ]]; then
                found=true
                break
            fi
        done
        
        [[ "$found" == "true" ]] || {
            echo "Missing simple mapping for: $yaml_path -> $config_var"
            false
        }
    done
}

@test "all _CONFIG_MASTER entries produce valid _ENV_OVERRIDE_MAP" {
    source "$PROJECT_ROOT/lib/config.sh"
    
    for entry in "${_CONFIG_MASTER[@]}"; do
        local yaml_path env_suffix api_key config_var
        IFS=':' read -r yaml_path env_suffix api_key config_var <<< "$entry"
        
        local found=false
        for mapping in "${_ENV_OVERRIDE_MAP[@]}"; do
            if [[ "$mapping" == "${env_suffix}:${config_var}" ]]; then
                found=true
                break
            fi
        done
        
        [[ "$found" == "true" ]] || {
            echo "Missing env override for: $env_suffix -> $config_var"
            false
        }
    done
}

@test "all _CONFIG_MASTER entries produce valid _CONFIG_KEY_MAP" {
    source "$PROJECT_ROOT/lib/config.sh"
    
    for entry in "${_CONFIG_MASTER[@]}"; do
        local yaml_path env_suffix api_key config_var
        IFS=':' read -r yaml_path env_suffix api_key config_var <<< "$entry"
        
        set +u
        local mapped_var="${_CONFIG_KEY_MAP[$api_key]:-}"
        set -u
        
        [[ "$mapped_var" == "$config_var" ]] || {
            echo "Key map mismatch for '$api_key': expected '$config_var', got '$mapped_var'"
            false
        }
    done
}

@test "all _CONFIG_MASTER_ARRAYS entries are in _ENV_OVERRIDE_MAP and _CONFIG_KEY_MAP" {
    source "$PROJECT_ROOT/lib/config.sh"
    
    for entry in "${_CONFIG_MASTER_ARRAYS[@]}"; do
        local yaml_path env_suffix api_key config_var
        IFS=':' read -r yaml_path env_suffix api_key config_var <<< "$entry"
        
        # Check env override map
        local found=false
        for mapping in "${_ENV_OVERRIDE_MAP[@]}"; do
            if [[ "$mapping" == "${env_suffix}:${config_var}" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == "true" ]] || {
            echo "Missing env override for array config: $env_suffix -> $config_var"
            false
        }
        
        # Check key map
        set +u
        local mapped_var="${_CONFIG_KEY_MAP[$api_key]:-}"
        set -u
        [[ "$mapped_var" == "$config_var" ]] || {
            echo "Key map mismatch for array config '$api_key': expected '$config_var', got '$mapped_var'"
            false
        }
    done
}

@test "no duplicate entries in _CONFIG_MASTER" {
    source "$PROJECT_ROOT/lib/config.sh"
    
    local count=${#_CONFIG_MASTER[@]}
    local unique_count
    unique_count=$(printf '%s\n' "${_CONFIG_MASTER[@]}" | sort -u | wc -l | tr -d ' ')
    
    [[ "$count" -eq "$unique_count" ]] || {
        echo "Found duplicate entries in _CONFIG_MASTER: $count total vs $unique_count unique"
        false
    }
}

@test "get_config works for all master-defined keys" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # All keys should be accessible via get_config (may return empty for optional configs)
    for entry in "${_CONFIG_MASTER[@]}" "${_CONFIG_MASTER_ARRAYS[@]}"; do
        local yaml_path env_suffix api_key config_var
        IFS=':' read -r yaml_path env_suffix api_key config_var <<< "$entry"
        
        # Should not fail
        run get_config "$api_key"
        [ "$status" -eq 0 ] || {
            echo "get_config failed for key: $api_key"
            false
        }
    done
}
