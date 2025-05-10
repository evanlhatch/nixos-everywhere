#!/usr/bin/env bash
# scripts/deps_check.sh
# Checks for necessary local command-line tool dependencies.

# Source the core library for logging and error handling
LIB_CORE_PATH="$(dirname "$0")/lib_core.sh"
if [[ ! -f "$LIB_CORE_PATH" ]]; then
    echo "Critical Error: Core library script (lib_core.sh) not found at $LIB_CORE_PATH" >&2
    exit 1
fi
source "$LIB_CORE_PATH"
enable_robust_error_handling # Exit on error, etc.

log_info "Starting dependency check..."

# List of required commands
# Format: "command_name|installation_suggestion"
REQUIRED_COMMANDS=(
    "just|Please install Just: https://just.systems/man/en/chapter_4.html"
    "hcloud|Please install Hetzner Cloud CLI (hcloud): https://github.com/hetznercloud/cli#installation"
    "ssh|Please install an SSH client (e.g., OpenSSH)."
    "curl|Please install curl."
    "jq|Please install jq (JSON processor)."
    "base64|Please install base64 (usually part of coreutils)."
    "git|Please install Git."
)

ALL_DEPS_MET=true

for item in "${REQUIRED_COMMANDS[@]}"; do
    IFS="|" read -r cmd_name suggestion <<< "$item"
    if command -v "$cmd_name" &> /dev/null; then
        log_info "✅ Dependency '${cmd_name}' found: $(command -v "$cmd_name")"
    else
        log_warn "❌ Dependency '${cmd_name}' NOT FOUND."
        log_warn "   Suggestion: ${suggestion}"
        ALL_DEPS_MET=false
    fi
done

if [[ "$ALL_DEPS_MET" == "true" ]]; then
    log_info "All critical dependencies are met."
    exit 0
else
    log_error "One or more critical dependencies are missing. Please install them and try again."
    exit 1
fi