#!/usr/bin/env bash
# scripts/nixos_convert_on_debian.sh
# This script is run by cloud-init on the target Debian/Ubuntu server.
# It prepares the environment and executes nixos-everywhere.sh.

# --- Start of Script ---
# Detailed logging for this wrapper script will go to /var/log/nixos-conversion-detailed.log
# and also to cloud-init's output log.
exec > >(tee -a "/var/log/nixos-conversion-detailed.log") 2>&1
set -x # Log executed commands for debugging

echo "--- nixos_convert_on_debian.sh wrapper started at $(date) ---"

# Environment variables are expected to be EXPORTED by the cloud-init runcmd block.
# These variables are sourced from the justfile -> hetzner_provision.sh -> cloud_init_generator.sh -> cloud-init runcmd.
# Example: NIXOS_FLAKE_URI, NIXOS_FLAKE_HOST_ATTR, SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT, etc.

# Source the core library for logging, if available and adapted for Debian.
# For simplicity, we'll use basic echo for logging in this wrapper.
# If lib_core.sh is made generic enough, it could be included and sourced.
log_wrapper_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CONVERT_WRAPPER INFO] $1"
}
log_wrapper_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CONVERT_WRAPPER ERROR] $1" >&2
}

# Validate essential variables received from cloud-init
if [ -z "${NIXOS_FLAKE_URI}" ]; then
    log_wrapper_error "NIXOS_FLAKE_URI is not set. Cannot proceed."
    exit 1
fi
if [ -z "${NIXOS_FLAKE_HOST_ATTR}" ]; then
    log_wrapper_error "NIXOS_FLAKE_HOST_ATTR is not set. Cannot proceed."
    exit 1
fi
if [ -z "${SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT}" ]; then
    log_wrapper_error "SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT is not set. Cannot proceed."
    exit 1
fi

log_wrapper_info "Starting NixOS conversion process."
log_wrapper_info "Target Flake URI: ${NIXOS_FLAKE_URI}"
log_wrapper_info "Target Flake Host Attribute: ${NIXOS_FLAKE_HOST_ATTR}"
log_wrapper_info "NixOS Channel (for bootstrap): ${NIXOS_CHANNEL_ENV:-Using nixos-everywhere.sh default}"
log_wrapper_info "Initial Hostname: ${HOSTNAME_INIT_ENV:-Using nixos-everywhere.sh default}"
log_wrapper_info "Timezone: ${TIMEZONE_INIT_ENV:-Using nixos-everywhere.sh default}"
log_wrapper_info "Locale: ${LOCALE_LANG_INIT_ENV:-Using nixos-everywhere.sh default}"
log_wrapper_info "State Version: ${STATE_VERSION_INIT_ENV:-Using nixos-everywhere.sh default}"
# Do not log SSH keys or Infisical secrets here.

# Prepare environment variables for nixos-everywhere.sh
# The names must match what nixos-everywhere.sh expects (e.g., FLAKE_URI_INPUT)
export FLAKE_URI_INPUT="${NIXOS_FLAKE_URI}#${NIXOS_FLAKE_HOST_ATTR}"
export SSH_AUTHORIZED_KEYS_INPUT="${SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT}"
export NIXOS_CHANNEL_ENV="${NIXOS_CHANNEL_ENV}"
export HOSTNAME_INIT_ENV="${HOSTNAME_INIT_ENV:-${NIXOS_FLAKE_HOST_ATTR}}" # Default hostname to flake attr if not set
export TIMEZONE_INIT_ENV="${TIMEZONE_INIT_ENV}"
export LOCALE_LANG_INIT_ENV="${LOCALE_LANG_INIT_ENV}"
export STATE_VERSION_INIT_ENV="${STATE_VERSION_INIT_ENV}"

# Pass through Infisical credentials if they are set
if [ -n "${INFISICAL_CLIENT_ID_FOR_FLAKE}" ]; then
    export INFISICAL_CLIENT_ID_FOR_FLAKE="${INFISICAL_CLIENT_ID_FOR_FLAKE}"
fi
if [ -n "${INFISICAL_CLIENT_SECRET_FOR_FLAKE}" ]; then
    export INFISICAL_CLIENT_SECRET_FOR_FLAKE="${INFISICAL_CLIENT_SECRET_FOR_FLAKE}"
fi
if [ -n "${INFISICAL_BOOTSTRAP_ADDRESS_FOR_FLAKE}" ]; then
    export INFISICAL_ADDRESS_FOR_FLAKE="${INFISICAL_BOOTSTRAP_ADDRESS_FOR_FLAKE}"
fi

# --- Get nixos-everywhere.sh ---
NIXOS_EVERYWHERE_SCRIPT_PATH="/tmp/nixos-everywhere.sh"

if [ -n "${NIXOS_EVERYWHERE_EMBEDDED_BASE64}" ]; then
    log_wrapper_info "Decoding embedded nixos-everywhere.sh..."
    echo "${NIXOS_EVERYWHERE_EMBEDDED_BASE64}" | base64 --decode > "${NIXOS_EVERYWHERE_SCRIPT_PATH}"
    if [ ! -s "${NIXOS_EVERYWHERE_SCRIPT_PATH}" ]; then
        log_wrapper_error "Embedded nixos-everywhere.sh is empty after decoding! Cannot proceed."
        exit 1
    fi
    log_wrapper_info "Successfully decoded embedded nixos-everywhere.sh to ${NIXOS_EVERYWHERE_SCRIPT_PATH}"
elif [ -n "${NIXOS_EVERYWHERE_SCRIPT_URL}" ]; then
    log_wrapper_info "Downloading nixos-everywhere.sh from ${NIXOS_EVERYWHERE_SCRIPT_URL}..."
    # Retry curl command
    for i in {1..3}; do
        if curl -L --fail --silent --show-error "${NIXOS_EVERYWHERE_SCRIPT_URL}" -o "${NIXOS_EVERYWHERE_SCRIPT_PATH}"; then
            log_wrapper_info "Download successful (attempt $i)."
            break
        else
            log_wrapper_error "Failed to download nixos-everywhere.sh (attempt $i/3). Output/Error above."
            if [ $i -eq 3 ]; then
                log_wrapper_error "Cannot download nixos-everywhere.sh after 3 attempts. Aborting."
                exit 1
            fi
            log_wrapper_info "Retrying in 10 seconds..."
            sleep 10
        fi
    done
    if [ ! -s "${NIXOS_EVERYWHERE_SCRIPT_PATH}" ]; then
        log_wrapper_error "Downloaded nixos-everywhere.sh is empty! Cannot proceed."
        exit 1
    fi
    log_wrapper_info "Successfully downloaded nixos-everywhere.sh to ${NIXOS_EVERYWHERE_SCRIPT_PATH}"
else
    log_wrapper_error "Neither embedded script nor URL for nixos-everywhere.sh was provided. Cannot proceed."
    exit 1
fi

chmod +x "${NIXOS_EVERYWHERE_SCRIPT_PATH}"
log_wrapper_info "Made nixos-everywhere.sh executable."

# --- Execute nixos-everywhere.sh ---
log_wrapper_info "Executing ${NIXOS_EVERYWHERE_SCRIPT_PATH}..."
# The nixos-everywhere.sh script itself handles detailed logging to its own file
# and will output to stdout/stderr which is captured by this wrapper's exec redirection.
if "${NIXOS_EVERYWHERE_SCRIPT_PATH}"; then
    log_wrapper_info "nixos-everywhere.sh script execution finished successfully."
    # The nixos-everywhere.sh script should handle rebooting.
else
    script_exit_code=$?
    log_wrapper_error "nixos-everywhere.sh script execution FAILED with exit code ${script_exit_code}."
    # Ensure cloud-init knows about the failure.
    exit "${script_exit_code}"
fi

log_wrapper_info "--- nixos_convert_on_debian.sh wrapper finished at $(date) ---"
# If nixos-everywhere.sh handles reboot, this script might not complete its final log message if reboot is immediate.
# That's generally acceptable.
exit 0