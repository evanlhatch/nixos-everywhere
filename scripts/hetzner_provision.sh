#!/usr/bin/env bash
# scripts/hetzner_provision.sh
# Provisions a Hetzner Cloud server with cloud-init data for NixOS setup.

# Source the core library for logging and robust error handling
LIB_CORE_PATH="$(dirname "$0")/lib_core.sh"
if [[ ! -f "$LIB_CORE_PATH" ]]; then
    echo "Critical Error: Core library script (lib_core.sh) not found at $LIB_CORE_PATH" >&2
    exit 1
fi
source "$LIB_CORE_PATH"
enable_robust_error_handling

log_info "--- Hetzner Provisioning Script Started ---"

# --- Expected Environment Variables (set by calling justfile recipe) ---
# HCLOUD_TOKEN (critical, for hcloud CLI)
# HETZNER_SERVER_NAME
# HETZNER_SERVER_TYPE
# HETZNER_BASE_IMAGE (for 'convert' method)
# HETZNER_LOCATION
# HETZNER_SSH_KEY_NAME (name of the key in Hetzner Cloud project)
# NIXOS_FLAKE_URI (full flake URI including #attribute, e.g., github:owner/repo#host)
# DEPLOY_METHOD ('convert' or 'direct')
#
# Optional / for nixos-everywhere.sh via cloud-init:
# NIXOS_CHANNEL_ENV
# HOSTNAME_INIT_ENV (if not derived from NIXOS_FLAKE_HOST_ATTR)
# TIMEZONE_INIT_ENV
# LOCALE_LANG_INIT_ENV
# STATE_VERSION_INIT_ENV
# INFISICAL_CLIENT_ID
# INFISICAL_CLIENT_SECRET
# INFISICAL_BOOTSTRAP_ADDRESS
#
# Optional Hetzner server parameters:
# HETZNER_NETWORK (name of private network)
# HETZNER_VOLUME (name of volume to attach)
# HETZNER_FIREWALLS (comma-separated list of firewall names)
# HETZNER_LABELS (semicolon-separated key=value pairs)
# HETZNER_ENABLE_IPV4 (true or false, defaults to true if not specified)
#
# Configuration for nixos-everywhere.sh URL:
# NIXOS_EVERYWHERE_SCRIPT_URL (URL to download nixos-everywhere.sh from)
# ---

# Validate critical environment variables
ensure_env_vars "HCLOUD_TOKEN" "HETZNER_SERVER_NAME" "HETZNER_SERVER_TYPE" \
                "HETZNER_LOCATION" "HETZNER_SSH_KEY_NAME" "NIXOS_FLAKE_URI" "DEPLOY_METHOD"

if [[ "$DEPLOY_METHOD" == "convert" ]]; then
    ensure_env_var "HETZNER_BASE_IMAGE" "HETZNER_BASE_IMAGE must be set for 'convert' deployment method."
fi

# Parse NIXOS_FLAKE_URI to get URL and Host Attribute parts
# extract_flake_parts sets EXTRACTED_FLAKE_URL and EXTRACTED_FLAKE_ATTR
if ! extract_flake_parts "$NIXOS_FLAKE_URI"; then
    log_error "Failed to parse NIXOS_FLAKE_URI: '$NIXOS_FLAKE_URI'"
    exit 1
fi
if [[ -z "$EXTRACTED_FLAKE_ATTR" ]]; then
    log_error "The #attribute part of NIXOS_FLAKE_URI is missing or empty (e.g., github:owner/repo#hostname). This is required."
    exit 1
fi
# Export them for cloud_init_generator.sh
export NIXOS_FLAKE_URI_FOR_GEN="${EXTRACTED_FLAKE_URL}" # The part before #
export NIXOS_FLAKE_HOST_ATTR_FOR_GEN="${EXTRACTED_FLAKE_ATTR}" # The part after #

# Default HOSTNAME_INIT_ENV if not provided
: "${HOSTNAME_INIT_ENV:=${NIXOS_FLAKE_HOST_ATTR_FOR_GEN}}" # Default to the flake host attribute
export HOSTNAME_INIT_ENV # Ensure it's exported for cloud_init_generator

# Get the URL for nixos-everywhere.sh
: "${NIXOS_EVERYWHERE_SCRIPT_URL:=$(grep -E "^NIXOS_EVERYWHERE_SCRIPT_URL=" "$(dirname "$0")/../config/nixos.env" | cut -d= -f2- | tr -d '"')}"
if [[ -z "$NIXOS_EVERYWHERE_SCRIPT_URL" ]]; then
    log_error "NIXOS_EVERYWHERE_SCRIPT_URL is not set. Please set it in config/nixos.env or as an environment variable."
    exit 1
fi
export NIXOS_EVERYWHERE_REMOTE_URL_CONFIG="$NIXOS_EVERYWHERE_SCRIPT_URL"

log_info "Server Name: ${HETZNER_SERVER_NAME}"
log_info "Server Type: ${HETZNER_SERVER_TYPE}"
log_info "Location: ${HETZNER_LOCATION}"
log_info "SSH Key Name (Hetzner): ${HETZNER_SSH_KEY_NAME}"
log_info "Deployment Method: ${DEPLOY_METHOD}"
log_info "Flake URL part: ${NIXOS_FLAKE_URI_FOR_GEN}"
log_info "Flake Host Attribute: ${NIXOS_FLAKE_HOST_ATTR_FOR_GEN}"
log_info "Effective Hostname for Init: ${HOSTNAME_INIT_ENV}"
log_info "NixOS-Everywhere Script URL: ${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}"
[[ "$DEPLOY_METHOD" == "convert" ]] && log_info "Base Image (for conversion): ${HETZNER_BASE_IMAGE}"

# --- Fetch SSH Public Key from Hetzner Cloud ---
log_info "Fetching public key content for Hetzner SSH key: '${HETZNER_SSH_KEY_NAME}'..."
ensure_command "jq" "jq (JSON processor) is required to fetch SSH key content."
HETZNER_SSH_KEY_PUBLIC_CONTENT=$(hcloud ssh-key describe "${HETZNER_SSH_KEY_NAME}" -o json | jq -r .public_key)

if [[ -z "$HETZNER_SSH_KEY_PUBLIC_CONTENT" || "$HETZNER_SSH_KEY_PUBLIC_CONTENT" == "null" ]]; then
    log_error "Failed to fetch public key content for '${HETZNER_SSH_KEY_NAME}'. Check if the key exists in your Hetzner project and HCLOUD_TOKEN has permissions."
    exit 1
fi
log_info "Successfully fetched SSH public key content."
export HETZNER_SSH_KEY_PUBLIC_CONTENT # Export for cloud_init_generator.sh

# --- Generate Cloud-Init User Data ---
log_info "Generating cloud-init user data..."
CLOUD_INIT_GENERATOR_SCRIPT="$(dirname "$0")/cloud_init_generator.sh"
if [[ ! -x "$CLOUD_INIT_GENERATOR_SCRIPT" ]]; then
    log_error "Cloud-init generator script not found or not executable: ${CLOUD_INIT_GENERATOR_SCRIPT}"
    exit 1
fi

USER_DATA_CONTENT=$("$CLOUD_INIT_GENERATOR_SCRIPT")
if [[ -z "$USER_DATA_CONTENT" ]]; then
    log_error "Cloud-init user data generation failed (empty output)."
    exit 1
fi
log_info "Cloud-init user data generated successfully."
log_debug "--- Generated User Data (first 20 lines) ---"
log_debug "$(echo "${USER_DATA_CONTENT}" | head -n 20)"
log_debug "--- End of User Data Preview ---"

# --- Build hcloud server create command ---
HCLOUD_ARGS=()
HCLOUD_ARGS+=(--name "${HETZNER_SERVER_NAME}")
HCLOUD_ARGS+=(--type "${HETZNER_SERVER_TYPE}")

# Image depends on deployment method
if [[ "$DEPLOY_METHOD" == "convert" ]]; then
    HCLOUD_ARGS+=(--image "${HETZNER_BASE_IMAGE}")
elif [[ "$DEPLOY_METHOD" == "direct" ]]; then
    # For direct NixOS install, you might use a minimal rescue image or a specific NixOS ISO if hcloud supports it.
    # For now, let's assume it still starts from a common base image and nixos_install_direct.sh handles partitioning.
    # Or, if Hetzner supports NixOS ISOs directly via API:
    # HCLOUD_ARGS+=(--image "nixos-stable") # Fictional example
    log_warn "For 'direct' deploy method, ensure HETZNER_BASE_IMAGE ('${HETZNER_BASE_IMAGE}') is suitable for bootstrapping a NixOS install (e.g., minimal Linux or rescue)."
    HCLOUD_ARGS+=(--image "${HETZNER_BASE_IMAGE}")
else
    log_error "Unsupported DEPLOY_METHOD: ${DEPLOY_METHOD}"
    exit 1
fi

HCLOUD_ARGS+=(--location "${HETZNER_LOCATION}")
HCLOUD_ARGS+=(--ssh-key "${HETZNER_SSH_KEY_NAME}")

# Optional arguments - use if defined
if [[ -n "${HETZNER_NETWORK:-}" ]]; then
    HCLOUD_ARGS+=(--network "${HETZNER_NETWORK}")
fi

if [[ -n "${HETZNER_VOLUME:-}" ]]; then
    HCLOUD_ARGS+=(--volume "${HETZNER_VOLUME}")
fi

if [[ -n "${HETZNER_FIREWALLS:-}" ]]; then
    IFS=',' read -ra FW_ARRAY <<< "${HETZNER_FIREWALLS}"
    for fw in "${FW_ARRAY[@]}"; do
        trimmed_fw=$(echo "$fw" | xargs) # Trim whitespace
        [[ -n "$trimmed_fw" ]] && HCLOUD_ARGS+=(--firewall "$trimmed_fw")
    done
fi

if [[ -n "${HETZNER_LABELS:-}" ]]; then
    IFS=';' read -ra LABEL_ARRAY <<< "${HETZNER_LABELS}"
    for label in "${LABEL_ARRAY[@]}"; do
        trimmed_label=$(echo "$label" | xargs) # Trim whitespace
        [[ -n "$trimmed_label" ]] && HCLOUD_ARGS+=(--label "$trimmed_label")
    done
fi

# Handle public IPv4 (defaults to enabled if HETZNER_ENABLE_IPV4 is not 'false')
if [[ "${HETZNER_ENABLE_IPV4:-true}" == "false" ]]; then
    log_info "Disabling public IPv4 for the server."
    HCLOUD_ARGS+=(--without-ipv4) # Hetzner CLI flag might be different, e.g. --disable-public-ipv4
else
    log_info "Public IPv4 will be enabled (default or HETZNER_ENABLE_IPV4 is not 'false')."
    # No specific flag needed if IPv4 is enabled by default
fi

# Pass user data via a temporary file
USER_DATA_FILE=$(mktemp)
echo "${USER_DATA_CONTENT}" > "$USER_DATA_FILE"
HCLOUD_ARGS+=(--user-data-from-file "$USER_DATA_FILE")

# --- Create Server ---
log_info "Creating Hetzner server '${HETZNER_SERVER_NAME}' with the following arguments:"
log_info "hcloud server create ${HCLOUD_ARGS[*]}" # Note: user-data content won't be shown here

if hcloud server create "${HCLOUD_ARGS[@]}"; then
    log_info "Server '${HETZNER_SERVER_NAME}' creation initiated successfully!"
    SERVER_IP=$(hcloud server ip "${HETZNER_SERVER_NAME}")
    log_info "Server IP: ${SERVER_IP:-Not available yet}"
    log_info "Cloud-init and NixOS setup will now proceed on the server."
    log_info "Monitor progress using: just logs server_name=\"${HETZNER_SERVER_NAME}\""
    log_info "Once setup is complete, SSH using: just ssh server_name=\"${HETZNER_SERVER_NAME}\""
else
    CREATE_STATUS=$?
    log_error "Hetzner server creation failed with status: ${CREATE_STATUS}."
    rm -f "$USER_DATA_FILE" # Clean up temp file
    exit $CREATE_STATUS
fi

rm -f "$USER_DATA_FILE" # Clean up temp file
log_info "--- Hetzner Provisioning Script Finished ---"