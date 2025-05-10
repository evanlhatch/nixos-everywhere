#!/usr/bin/env bash
# scripts/cloud_init_generator.sh
# Dynamically generates the cloud-init YAML user-data.

# Source the core library for logging and robust error handling
LIB_CORE_PATH="$(dirname "$0")/lib_core.sh"
if [[ ! -f "$LIB_CORE_PATH" ]]; then
    echo "Critical Error: Core library script (lib_core.sh) not found at $LIB_CORE_PATH" >&2
    exit 1
fi
source "$LIB_CORE_PATH"
enable_robust_error_handling

# --- Expected Environment Variables (to be set by hetzner_provision.sh) ---
# NIXOS_FLAKE_URI (full URI like github:owner/repo)
# NIXOS_FLAKE_HOST_ATTR (the #attribute part)
# HETZNER_SSH_KEY_PUBLIC_CONTENT (actual public key string)
# DEPLOY_METHOD ("convert" or "direct")
# NIXOS_CHANNEL_ENV
# HOSTNAME_INIT_ENV
# TIMEZONE_INIT_ENV
# LOCALE_LANG_INIT_ENV
# STATE_VERSION_INIT_ENV
# INFISICAL_CLIENT_ID (optional)
# INFISICAL_CLIENT_SECRET (optional)
# INFISICAL_BOOTSTRAP_ADDRESS (optional)
# NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG (path to local nixos-everywhere.sh, if configured)
# NIXOS_EVERYWHERE_REMOTE_URL_CONFIG (URL for nixos-everywhere.sh, if configured)
# ---

log_info "Starting cloud-init YAML generation..."

# Validate required environment variables
ensure_env_vars "NIXOS_FLAKE_URI" "NIXOS_FLAKE_HOST_ATTR" "HETZNER_SSH_KEY_PUBLIC_CONTENT" "DEPLOY_METHOD" \
                "NIXOS_CHANNEL_ENV" "HOSTNAME_INIT_ENV" "TIMEZONE_INIT_ENV" \
                "LOCALE_LANG_INIT_ENV" "STATE_VERSION_INIT_ENV"

# Determine the main execution script content based on DEPLOY_METHOD
EXECUTION_SCRIPT_PATH=""
EXECUTION_SCRIPT_CONTENT_BASE64="" # Initialize

if [[ "$DEPLOY_METHOD" == "convert" ]]; then
    EXECUTION_SCRIPT_PATH="$(dirname "$0")/nixos_convert_on_debian.sh"
    log_info "Deployment method: 'convert'. Using script: ${EXECUTION_SCRIPT_PATH}"
elif [[ "$DEPLOY_METHOD" == "direct" ]]; then
    EXECUTION_SCRIPT_PATH="$(dirname "$0")/nixos_install_direct.sh"
    log_info "Deployment method: 'direct'. Using script: ${EXECUTION_SCRIPT_PATH}"
else
    log_error "Invalid DEPLOY_METHOD: '${DEPLOY_METHOD}'. Must be 'convert' or 'direct'."
    exit 1
fi

if [[ ! -f "$EXECUTION_SCRIPT_PATH" ]]; then
    log_error "Execution script not found at: ${EXECUTION_SCRIPT_PATH}"
    exit 1
fi

# Base64 encode the chosen execution script to embed it safely in cloud-init
EXECUTION_SCRIPT_CONTENT_BASE64=$(base64 -w0 < "${EXECUTION_SCRIPT_PATH}")
if [[ -z "$EXECUTION_SCRIPT_CONTENT_BASE64" ]]; then
    log_error "Failed to base64 encode execution script: ${EXECUTION_SCRIPT_PATH}"
    exit 1
fi
log_debug "Execution script content base64 encoded successfully."

# Prepare variables for nixos-everywhere.sh sourcing by nixos_convert_on_debian.sh
# These will be passed into the cloud-init template, then exported by the runcmd script block,
# then used by nixos_convert_on_debian.sh to decide how to get nixos-everywhere.sh
export NIXOS_EVERYWHERE_EMBEDDED_BASE64="" # Default to empty
export NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT="" # Default to empty

# Logic to determine if nixos-everywhere.sh should be embedded or downloaded
# NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG is the path to nixos-everywhere.sh in *this* project structure
# NIXOS_EVERYWHERE_REMOTE_URL_CONFIG is the URL to download it from
# These are passed from hetzner_provision.sh, which gets them from justfile/config.
PATH_TO_NIXOS_EVERYWHERE_SH_IN_PROJECT="$(dirname "$0")/nixos_everywhere.sh"

if [[ -n "${NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG}" && -f "${NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG}" ]]; then
    log_info "Embedding local nixos-everywhere.sh from configured path: ${NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG}"
    NIXOS_EVERYWHERE_EMBEDDED_BASE64=$(base64 -w0 < "${NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG}")
    if [[ -z "$NIXOS_EVERYWHERE_EMBEDDED_BASE64" ]]; then
        log_error "Failed to base64 encode nixos-everywhere.sh from ${NIXOS_EVERYWHERE_LOCAL_PATH_CONFIG}"
        exit 1
    fi
elif [[ -f "$PATH_TO_NIXOS_EVERYWHERE_SH_IN_PROJECT" ]]; then # Fallback to default location
    log_info "Embedding local nixos-everywhere.sh from default project path: ${PATH_TO_NIXOS_EVERYWHERE_SH_IN_PROJECT}"
    NIXOS_EVERYWHERE_EMBEDDED_BASE64=$(base64 -w0 < "${PATH_TO_NIXOS_EVERYWHERE_SH_IN_PROJECT}")
     if [[ -z "$NIXOS_EVERYWHERE_EMBEDDED_BASE64" ]]; then
        log_error "Failed to base64 encode nixos-everywhere.sh from ${PATH_TO_NIXOS_EVERYWHERE_SH_IN_PROJECT}"
        exit 1
    fi
elif [[ -n "${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}" ]]; then
    log_info "Configuring nixos-everywhere.sh to be downloaded from URL: ${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}"
    export NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT="${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}"
else
    log_error "Source for nixos-everywhere.sh is not defined. Neither local path nor remote URL is configured, and default local path not found."
    exit 1
fi


# --- Template Substitution ---
# Export all variables that are used in the cloud_init_base.yaml template
# so that envsubst can replace them.
export NIXOS_FLAKE_URI="${NIXOS_FLAKE_URI}"
export NIXOS_FLAKE_HOST_ATTR="${NIXOS_FLAKE_HOST_ATTR}"
export SSH_AUTHORIZED_KEYS_CONTENT="${HETZNER_SSH_KEY_PUBLIC_CONTENT}"
export EXECUTION_SCRIPT_CONTENT_BASE64="${EXECUTION_SCRIPT_CONTENT_BASE64}" # This is the base64 of nixos_convert_on_debian.sh (or _direct.sh)

export NIXOS_CHANNEL_ENV="${NIXOS_CHANNEL_ENV}"
export HOSTNAME_INIT_ENV="${HOSTNAME_INIT_ENV}"
export TIMEZONE_INIT_ENV="${TIMEZONE_INIT_ENV}"
export LOCALE_LANG_INIT_ENV="${LOCALE_LANG_INIT_ENV}"
export STATE_VERSION_INIT_ENV="${STATE_VERSION_INIT_ENV}"

export INFISICAL_CLIENT_ID="${INFISICAL_CLIENT_ID:-}" # Default to empty if not set
export INFISICAL_CLIENT_SECRET="${INFISICAL_CLIENT_SECRET:-}" # Default to empty
export INFISICAL_BOOTSTRAP_ADDRESS="${INFISICAL_BOOTSTRAP_ADDRESS:-}" # Default to empty

# NIXOS_EVERYWHERE_EMBEDDED_BASE64 and NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT are already exported above.

TEMPLATE_FILE="$(dirname "$0")/../templates/cloud_init_base.yaml"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Cloud-init base template not found at: ${TEMPLATE_FILE}"
    exit 1
fi

log_debug "Substituting variables into cloud-init template: ${TEMPLATE_FILE}"

# Use envsubst to replace placeholders in the template.
# Only substitute specific, known variables to avoid issues with other '$' signs in scripts.
# Create a string of variable names for envsubst: '${VAR1} ${VAR2}'
# Note: envsubst substitutes environment variables. Ensure they are EXPORTED.
# The EXECUTION_SCRIPT_CONTENT_BASE64 contains the base64 of the *wrapper* script (e.g. nixos_convert_on_debian.sh)
# This wrapper script then handles getting and running nixos-everywhere.sh itself.
SUBST_VARS=$(printf '${%s} ' \
    NIXOS_FLAKE_URI NIXOS_FLAKE_HOST_ATTR SSH_AUTHORIZED_KEYS_CONTENT \
    EXECUTION_SCRIPT_CONTENT_BASE64 NIXOS_CHANNEL_ENV HOSTNAME_INIT_ENV \
    TIMEZONE_INIT_ENV LOCALE_LANG_INIT_ENV STATE_VERSION_INIT_ENV \
    INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET INFISICAL_BOOTSTRAP_ADDRESS \
    NIXOS_EVERYWHERE_EMBEDDED_BASE64 NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT \
)

# Perform substitution and output to stdout
envsubst "$SUBST_VARS" < "$TEMPLATE_FILE"

log_info "Cloud-init YAML generation complete."