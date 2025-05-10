#!/usr/bin/env bash
# scripts/lib_core.sh
# Core library functions for logging, error handling, and utilities.

# --- Logging Functions ---
# Usage: log_info "This is an info message."
#        log_warn "This is a warning."
#        log_error "This is an error." # Exits script by default
#        log_debug "This is a debug message." # Only prints if DEBUG_MODE is true

# Set DEBUG_MODE to true for verbose debug logging
# Example: export DEBUG_MODE=true
: "${DEBUG_MODE:=false}" # Default to false if not set

_log_base() {
    local level="$1"
    local color_start="$2"
    local color_end="\033[0m" # Reset color
    shift 2
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Print to stderr so stdout can be used for script output piping
    >&2 printf "${color_start}[%s] [%s] %s${color_end}\n" "$timestamp" "$level" "$message"
}

log_info() {
    _log_base "INFO" "\033[0;32m" "$@" # Green
}

log_warn() {
    _log_base "WARN" "\033[0;33m" "$@" # Yellow
}

log_error() {
    _log_base "ERROR" "\033[0;31m" "$@" # Red
    # Optionally, exit the script on error. Can be overridden by trap.
    # exit 1
}

log_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        _log_base "DEBUG" "\033[0;34m" "$@" # Blue
    fi
}

# --- Error Handling ---

# Default error handler function
# Usage: trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
#        set -e -o pipefail
handle_error() {
    local exit_code="$1"
    local line_number="$2"
    local command_name="$3"
    local script_name
    script_name=$(basename "${BASH_SOURCE[1]:-$0}") # Get the name of the script where error occurred

    log_error "In script '${script_name}': Command '${command_name}' failed with exit code ${exit_code} at line ${line_number}."
    # Consider adding more context here, like call stack if possible, or specific cleanup.
    exit "$exit_code"
}

# Function to enable robust error handling in scripts
# Call this at the beginning of your scripts: `enable_robust_error_handling`
enable_robust_error_handling() {
    set -Eeuo pipefail # -E: ERR trap inherited by functions, -e: exit on error, -u: unset var is error, -o pipefail: pipe fails if any command fails
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
    log_debug "Robust error handling enabled (set -Eeuo pipefail and ERR trap)."
}


# --- Utility Functions ---

# Check if a command exists
# Usage: ensure_command "curl" "Please install curl."
ensure_command() {
    local cmd_name="$1"
    local error_message="${2:-Command '${cmd_name}' not found. Please install it.}"
    if ! command -v "$cmd_name" &> /dev/null; then
        log_error "$error_message"
        exit 1 # Or return 1 if you want the calling script to handle it
    fi
    log_debug "Command '${cmd_name}' is available."
}

# Check if an environment variable is set and not empty
# Usage: ensure_env_var "HCLOUD_TOKEN" "HCLOUD_TOKEN is not set."
ensure_env_var() {
    local var_name="$1"
    local error_message="${2:-Environment variable '${var_name}' is not set or is empty.}"
    local var_value
    
    # Use eval to get the value of the variable by name
    eval "var_value=\${$var_name:-}"
    
    if [ -z "$var_value" ]; then
        log_error "$error_message"
        exit 1 # Or return 1
    fi
    log_debug "Environment variable '${var_name}' is set."
}

# Check if multiple environment variables are set
# Usage: ensure_env_vars "VAR1" "VAR2" "VAR3"
ensure_env_vars() {
    for var_name in "$@"; do
        ensure_env_var "$var_name" # Uses default error message from ensure_env_var
    done
}

# Helper to extract Flake URL and Attribute Name from a full Flake URI
# Sets global variables: EXTRACTED_FLAKE_URL and EXTRACTED_FLAKE_ATTR
# Usage: extract_flake_parts "github:owner/repo#host"
#        echo "URL: $EXTRACTED_FLAKE_URL, Attr: $EXTRACTED_FLAKE_ATTR"
extract_flake_parts() {
    local full_flake_uri="$1"
    EXTRACTED_FLAKE_URL=""
    EXTRACTED_FLAKE_ATTR=""

    if [[ -z "$full_flake_uri" ]]; then
        log_error "Flake URI cannot be empty for parsing."
        return 1
    fi

    if [[ "$full_flake_uri" =~ ^([^#]+)#([^#]+)$ ]]; then
        EXTRACTED_FLAKE_URL="${BASH_REMATCH[1]}"
        EXTRACTED_FLAKE_ATTR="${BASH_REMATCH[2]}"
    elif [[ "$full_flake_uri" =~ ^([^#]+)$ ]]; then
        # No attribute specified, this might be an error depending on context
        EXTRACTED_FLAKE_URL="${BASH_REMATCH[1]}"
        EXTRACTED_FLAKE_ATTR="" # Explicitly empty
        log_warn "Flake URI '${full_flake_uri}' does not contain a '#' attribute separator. Attribute will be empty."
    else
        log_error "Invalid Flake URI format: '${full_flake_uri}'. Expected format like 'url#attribute' or just 'url'."
        return 1
    fi

    if [[ -z "$EXTRACTED_FLAKE_URL" ]]; then
        log_error "Could not extract Flake URL part from '${full_flake_uri}'."
        return 1
    fi
    # Attribute can be legitimately empty if the flake URI is just a URL part

    log_debug "Parsed Flake URI: URL='${EXTRACTED_FLAKE_URL}', Attribute='${EXTRACTED_FLAKE_ATTR}'"
    return 0
}

# Example of how to use in other scripts:
# source "$(dirname "$0")/lib_core.sh"
# enable_robust_error_handling
# log_info "Script started."
# ensure_command "my_tool"
# ensure_env_var "MY_VAR"