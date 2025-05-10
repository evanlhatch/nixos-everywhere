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
# NIXOS_FLAKE_URI_FOR_GEN (full URI like github:owner/repo)
# NIXOS_FLAKE_HOST_ATTR_FOR_GEN (the #attribute part)
# HETZNER_SSH_KEY_PUBLIC_CONTENT (actual public key string)
# NIXOS_CHANNEL_ENV
# HOSTNAME_INIT_ENV
# TIMEZONE_INIT_ENV
# LOCALE_LANG_INIT_ENV
# STATE_VERSION_INIT_ENV
# INFISICAL_CLIENT_ID (optional)
# INFISICAL_CLIENT_SECRET (optional)
# INFISICAL_BOOTSTRAP_ADDRESS (optional)
# NIXOS_EVERYWHERE_REMOTE_URL_CONFIG (URL for nixos-everywhere.sh)
# ---

log_info "Starting cloud-init YAML generation..."

# Validate required environment variables
ensure_env_vars "NIXOS_FLAKE_URI_FOR_GEN" "NIXOS_FLAKE_HOST_ATTR_FOR_GEN" "HETZNER_SSH_KEY_PUBLIC_CONTENT" \
                "NIXOS_CHANNEL_ENV" "HOSTNAME_INIT_ENV" "TIMEZONE_INIT_ENV" \
                "LOCALE_LANG_INIT_ENV" "STATE_VERSION_INIT_ENV" "NIXOS_EVERYWHERE_REMOTE_URL_CONFIG"

# --- Template Substitution ---
# Export all variables that are used in the cloud_init_base.yaml template
# so that envsubst can replace them.
export NIXOS_FLAKE_URI="${NIXOS_FLAKE_URI_FOR_GEN}"
export NIXOS_FLAKE_HOST_ATTR="${NIXOS_FLAKE_HOST_ATTR_FOR_GEN}"
export SSH_AUTHORIZED_KEYS_CONTENT="${HETZNER_SSH_KEY_PUBLIC_CONTENT}"
export NIXOS_CHANNEL_ENV="${NIXOS_CHANNEL_ENV}"
export HOSTNAME_INIT_ENV="${HOSTNAME_INIT_ENV}"
export TIMEZONE_INIT_ENV="${TIMEZONE_INIT_ENV}"
export LOCALE_LANG_INIT_ENV="${LOCALE_LANG_INIT_ENV}"
export STATE_VERSION_INIT_ENV="${STATE_VERSION_INIT_ENV}"
export INFISICAL_CLIENT_ID="${INFISICAL_CLIENT_ID:-}"
export INFISICAL_CLIENT_SECRET="${INFISICAL_CLIENT_SECRET:-}"
export INFISICAL_BOOTSTRAP_ADDRESS="${INFISICAL_BOOTSTRAP_ADDRESS:-}"
export NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT="${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}"

TEMPLATE_FILE="$(dirname "$0")/../templates/cloud_init_base.yaml"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Cloud-init base template not found at: ${TEMPLATE_FILE}"
    exit 1
fi

log_debug "Substituting variables into cloud-init template: ${TEMPLATE_FILE}"

# Create a temporary file to store the processed template
TEMP_FILE=$(mktemp)

# Read the template file
cat "$TEMPLATE_FILE" > "$TEMP_FILE"

# Replace placeholders with actual values using sed
sed -i "s|\${NIXOS_FLAKE_URI}|${NIXOS_FLAKE_URI}|g" "$TEMP_FILE"
sed -i "s|\${NIXOS_FLAKE_HOST_ATTR}|${NIXOS_FLAKE_HOST_ATTR}|g" "$TEMP_FILE"
sed -i "s|\${SSH_AUTHORIZED_KEYS_CONTENT}|${HETZNER_SSH_KEY_PUBLIC_CONTENT}|g" "$TEMP_FILE"
sed -i "s|\${NIXOS_CHANNEL_ENV}|${NIXOS_CHANNEL_ENV}|g" "$TEMP_FILE"
sed -i "s|\${HOSTNAME_INIT_ENV}|${HOSTNAME_INIT_ENV}|g" "$TEMP_FILE"
sed -i "s|\${TIMEZONE_INIT_ENV}|${TIMEZONE_INIT_ENV}|g" "$TEMP_FILE"
sed -i "s|\${LOCALE_LANG_INIT_ENV}|${LOCALE_LANG_INIT_ENV}|g" "$TEMP_FILE"
sed -i "s|\${STATE_VERSION_INIT_ENV}|${STATE_VERSION_INIT_ENV}|g" "$TEMP_FILE"
sed -i "s|\${INFISICAL_CLIENT_ID}|${INFISICAL_CLIENT_ID:-}|g" "$TEMP_FILE"
sed -i "s|\${INFISICAL_CLIENT_SECRET}|${INFISICAL_CLIENT_SECRET:-}|g" "$TEMP_FILE"
sed -i "s|\${INFISICAL_BOOTSTRAP_ADDRESS}|${INFISICAL_BOOTSTRAP_ADDRESS:-}|g" "$TEMP_FILE"
sed -i "s|\${NIXOS_EVERYWHERE_SCRIPT_URL_FOR_CLOUDINIT}|${NIXOS_EVERYWHERE_REMOTE_URL_CONFIG}|g" "$TEMP_FILE"

# Save a copy of the final cloud-init YAML for debugging
DEBUG_FILE="/tmp/cloud-init-final.yaml"
cp "$TEMP_FILE" "$DEBUG_FILE"
log_info "Generated cloud-init YAML saved to ${DEBUG_FILE} for debugging"

# Output the processed template to stdout
cat "$TEMP_FILE"

# Clean up the temporary file
rm -f "$TEMP_FILE"

log_info "Cloud-init YAML generation complete."