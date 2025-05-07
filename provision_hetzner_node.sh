#!/usr/bin/env bash
set -euo pipefail

# provision_hetzner_node.sh
# Helper script called by Justfile to provision a Hetzner server and infect it with NixOS.

log() {
    local level="$1"
    local message="$2"
    echo "$(date --iso-8601=seconds) - ${level^^} - ${message}"
}

# --- Parameters expected from Justfile (Positional) ---
if [[ "$#" -ne 20 ]]; then
    log "FATAL" "Incorrect number of arguments received by provision_hetzner_node.sh. Expected 20, got $#."
    exit 1
fi

ARG_SERVER_NAME="$1"
ARG_FLAKE_LOCATION="$2"          # CRITICAL: This MUST be a publicly accessible Flake URL for cloud deployment (e.g., github:owner/repo)
ARG_FLAKE_ATTRIBUTE_INPUT="$3"
ARG_SERVER_TYPE="$4"
ARG_IMAGE="$5"
ARG_LOCATION="$6"
ARG_SSH_KEY_NAME="$7"
ARG_NETWORK="$8"                 # Optional: Name of an existing private network
ARG_VOLUME="$9"                  # Optional: Name of an existing volume
ARG_FIREWALL="${10}"             # Optional: Name of an existing firewall
ARG_PLACEMENT_GROUP="${11}"      # Optional: Name of an existing placement group
ARG_LABELS_STR="${12}"
ARG_NIXOS_CHANNEL="${13}"        # For nixos-everywhere.sh bootstrap phase
ARG_TARGET_HOSTNAME_PARAM="${14}" # User's desired hostname for the OS, can be same as ARG_SERVER_NAME
NIXOS_EVERYWHERE_LOCAL_PATH="${15}" # Path to local nixos-everywhere.sh (if embedding)
NIXOS_EVERYWHERE_REMOTE_URL="${16}" # URL to remote nixos-everywhere.sh (if downloading)
DEFAULT_TARGET_HOSTNAME_BASE="${17}"# Fallback base for HOSTNAME_INIT
DEFAULT_TARGET_TIMEZONE="${18}"     # For HOSTNAME_INIT
DEFAULT_TARGET_LOCALE="${19}"       # For HOSTNAME_INIT
DEFAULT_TARGET_STATE_VERSION="${20}"# For HOSTNAME_INIT

log "INFO" "--- provision_hetzner_node.sh started ---"
log "INFO" "Server Name (Hetzner): $ARG_SERVER_NAME"
log "INFO" "Flake Location received: $ARG_FLAKE_LOCATION"
log "INFO" "Flake Attribute Input: $ARG_FLAKE_ATTRIBUTE_INPUT"

# Determine Effective Hostname for NixOS (passed to nixos-everywhere.sh)
EFFECTIVE_HOSTNAME=""
if [[ -n "$ARG_TARGET_HOSTNAME_PARAM" ]]; then
    EFFECTIVE_HOSTNAME="$ARG_TARGET_HOSTNAME_PARAM"
elif [[ -n "$ARG_SERVER_NAME" ]]; then
    EFFECTIVE_HOSTNAME="$ARG_SERVER_NAME"
else
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
    EFFECTIVE_HOSTNAME="${DEFAULT_TARGET_HOSTNAME_BASE:-nixos}-${RANDOM_SUFFIX}"
fi
log "INFO" "Effective Hostname for NixOS (HOSTNAME_INIT): $EFFECTIVE_HOSTNAME"

# Determine Actual Flake Attribute Name
ACTUAL_FLAKE_ATTRIBUTE_NAME=""
if [[ "$ARG_FLAKE_ATTRIBUTE_INPUT" == "AUTO_HOSTNAME" ]]; then
    ACTUAL_FLAKE_ATTRIBUTE_NAME="$EFFECTIVE_HOSTNAME"
    log "INFO" "Flake attribute will be based on effective hostname: '$ACTUAL_FLAKE_ATTRIBUTE_NAME'"
else
    ACTUAL_FLAKE_ATTRIBUTE_NAME="$ARG_FLAKE_ATTRIBUTE_INPUT"
    log "INFO" "Using specific Flake attribute: '$ACTUAL_FLAKE_ATTRIBUTE_NAME'"
fi
if [[ -z "$ACTUAL_FLAKE_ATTRIBUTE_NAME" ]]; then
    log "FATAL" "Flake attribute name could not be determined or is empty."
    exit 1
fi

# Construct the final Flake URI for cloud-init
# ARG_FLAKE_LOCATION ($2) is now expected to be the deployable URL (e.g., "github:owner/repo")
CONSTRUCTED_FLAKE_URI="${ARG_FLAKE_LOCATION}#${ACTUAL_FLAKE_ATTRIBUTE_NAME}"
log "INFO" "Final Flake URI for cloud-init: $CONSTRUCTED_FLAKE_URI"

# Verify HCLOUD_TOKEN is in environment (should be exported by the calling Justfile recipe)
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    log "FATAL" "HCLOUD_TOKEN environment variable is not set. It should be exported by the Justfile."
    exit 1
fi
log "INFO" "HCLOUD_TOKEN is present in environment."

log "INFO" "Fetching SSH public key for Hetzner key '$ARG_SSH_KEY_NAME'..."
if ! command -v jq &> /dev/null; then log "FATAL" "jq is not installed."; exit 1; fi

# hcloud command will use HCLOUD_TOKEN from environment
SSH_PUBLIC_KEY_CONTENT=$(hcloud ssh-key describe "$ARG_SSH_KEY_NAME" -o json | jq -r .public_key)
if [[ -z "$SSH_PUBLIC_KEY_CONTENT" || "$SSH_PUBLIC_KEY_CONTENT" == "null" ]]; then
    log "FATAL" "Failed to fetch public key for '$ARG_SSH_KEY_NAME'."
    exit 1
fi
log "INFO" "SSH public key fetched successfully."

# nixos-everywhere.sh Sourcing Logic for Cloud-Init Execution Block
NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=""
if [[ -f "$NIXOS_EVERYWHERE_LOCAL_PATH" ]]; then
    log "INFO" "Using local nixos-everywhere.sh from $NIXOS_EVERYWHERE_LOCAL_PATH for embedding."
    SCRIPT_CONTENT_BASE64=$(base64 -w0 "$NIXOS_EVERYWHERE_LOCAL_PATH")
    if [[ -z "$SCRIPT_CONTENT_BASE64" ]]; then
        log "ERROR" "Local nixos-everywhere.sh at '$NIXOS_EVERYWHERE_LOCAL_PATH' is empty or base64 encoding failed. Falling back to remote URL if available."
        # Fall through to elif block for remote URL
    else
        NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=$(cat <<EOF_INNER_SCRIPT
    echo 'INFO: Decoding embedded nixos-everywhere.sh...'
    base64 -d > /tmp/nixos-everywhere.sh <<'ENDOFSCRIPTBASE64MARKER'
${SCRIPT_CONTENT_BASE64}
ENDOFSCRIPTBASE64MARKER
    chmod +x /tmp/nixos-everywhere.sh
    echo 'INFO: Executing embedded nixos-everywhere.sh...'
    if /tmp/nixos-everywhere.sh; then
      echo 'INFO: nixos-everywhere.sh (embedded) script execution finished successfully.'
    else
      echo 'FATAL: nixos-everywhere.sh (embedded) script execution failed.' >&2; exit 1;
    fi
EOF_INNER_SCRIPT
)
    fi
fi

# Fallback to remote URL if local embedding was not chosen or failed (e.g. empty local script)
if [[ -z "$NIXOS_EVERYWHERE_EXEC_BLOCK_VAR" ]]; then
    if [[ -n "$NIXOS_EVERYWHERE_REMOTE_URL" ]]; then
        log "INFO" "Local nixos-everywhere.sh not used or empty. Using remote URL: ${NIXOS_EVERYWHERE_REMOTE_URL}"
        # Escape NIXOS_EVERYWHERE_REMOTE_URL for use in the heredoc
        ESCAPED_REMOTE_URL=$(printf '%s\n' "$NIXOS_EVERYWHERE_REMOTE_URL" | sed 's/[&/\]/\\&/g') # Basic escaping for sed in heredoc expansion
        NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=$(cat <<EOF_INNER_SCRIPT
    echo 'INFO: Downloading nixos-everywhere.sh from ${ESCAPED_REMOTE_URL}...'
    if curl -sSL -f "${ESCAPED_REMOTE_URL}" -o /tmp/nixos-everywhere.sh; then
      chmod +x /tmp/nixos-everywhere.sh
      echo 'INFO: Executing downloaded nixos-everywhere.sh...'
      if /tmp/nixos-everywhere.sh; then
        echo 'INFO: nixos-everywhere.sh (downloaded) script execution finished successfully.'
      else
        echo 'FATAL: nixos-everywhere.sh (downloaded) script execution failed.' >&2; exit 1;
      fi
    else
      echo 'FATAL: Failed to download nixos-everywhere.sh from ${ESCAPED_REMOTE_URL}' >&2
      exit 1 # Make cloud-init fail if download fails
    fi
EOF_INNER_SCRIPT
)
    else
        log "FATAL" "nixos-everywhere.sh source not found. Local path '$NIXOS_EVERYWHERE_LOCAL_PATH' not used/empty and no remote URL configured."
        exit 1
    fi
fi


# Construct User Data for cloud-init
USER_DATA_CONTENT=$(cat <<EOF_USER_DATA
#cloud-config
runcmd:
  - |
    # This whole block is executed by cloud-init on the new server
    set -x # Log executed commands to /var/log/cloud-init-output.log
    # Environment variables for nixos-everywhere.sh
    export FLAKE_URI="${CONSTRUCTED_FLAKE_URI}"
    export SSH_AUTHORIZED_KEYS='${SSH_PUBLIC_KEY_CONTENT}'
    export NIXOS_CHANNEL="${ARG_NIXOS_CHANNEL}"
    export HOSTNAME_INIT="${EFFECTIVE_HOSTNAME}"
    export TIMEZONE_INIT="${DEFAULT_TARGET_TIMEZONE}"
    export LOCALE_LANG_INIT="${DEFAULT_TARGET_LOCALE}"
    export STATE_VERSION_INIT="${DEFAULT_TARGET_STATE_VERSION}"
    # export INFISICAL_CLIENT_ID_FOR_FLAKE="..." # These should be set here if needed by nixos-everywhere.sh->Flake
    # export INFISICAL_CLIENT_SECRET_FOR_FLAKE="..."
    # export INFISICAL_ADDRESS_FOR_FLAKE="..."

${NIXOS_EVERYWHERE_EXEC_BLOCK_VAR}
EOF_USER_DATA
)
log "INFO" "--- User Data for cloud-init (first 25 lines) ---"
echo "${USER_DATA_CONTENT}" | head -n 25
log "INFO" "----------------------------------------------"

# Build hcloud command arguments
HCLOUD_SERVER_CREATE_ARGS_ARRAY=(
    --name "$ARG_SERVER_NAME"
    --type "$ARG_SERVER_TYPE"
    --image "$ARG_IMAGE"
    --location "$ARG_LOCATION"
    --ssh-key "$ARG_SSH_KEY_NAME"
)
if [[ -n "$ARG_NETWORK" ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--network "$ARG_NETWORK"); fi
if [[ -n "$ARG_VOLUME" ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--volume "$ARG_VOLUME"); fi
if [[ -n "$ARG_FIREWALL" ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--firewall "$ARG_FIREWALL"); fi
if [[ -n "$ARG_PLACEMENT_GROUP" ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--placement-group "$ARG_PLACEMENT_GROUP"); fi
if [[ -n "$ARG_LABELS_STR" ]]; then
    IFS=';' read -ra LABELS_ARRAY_INTERNAL <<< "$ARG_LABELS_STR"
    for label_item_internal in "${LABELS_ARRAY_INTERNAL[@]}"; do HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--label "$label_item_internal"); done
fi

# Flag for disabling public IPv4. User needs to verify the correct flag for their hcloud CLI version.
# Common options are removing public network attachment, or specific flags if available.
# Assuming the user will verify and use the correct current flag if '--without-ipv4' is not it.
# The user's `hcloud_create_server.fish` script currently uses `--disable-public-ipv4`.
# The error from `hcloud` implies this flag might be incorrect for their version.
# For now, I'll use a placeholder comment and user should confirm.
# HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--some-flag-to-disable-ipv4)
# Example from previous discussion if it was correct for their version:
# HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--disable-public-ipv4)
log "WARNING" "Ensure the hcloud flag for managing public IPv4 (e.g. disabling it) is correct for your hcloud CLI version."
log "WARNING" "Currently, no specific flag for IPv4 disablement is being added by this helper. Server might get public IPv4 by default."


log "INFO" "Initiating server creation with hcloud CLI..."
# HCLOUD_TOKEN is expected to be in the environment, exported by the Justfile recipe
if hcloud server create "${HCLOUD_SERVER_CREATE_ARGS_ARRAY[@]}" --user-data-from-file <(echo "$USER_DATA_CONTENT"); then
    log "INFO" "Server '$ARG_SERVER_NAME' creation initiated successfully."
    log "INFO" "The server will boot, cloud-init will run, then nixos-everywhere.sh will attempt to install NixOS."
    log "INFO" "Monitor progress via Hetzner Cloud console and server logs (e.g., /var/log/cloud-init-output.log on the server)."
else
    SERVER_CREATE_STATUS=$?
    log "FATAL" "Server creation failed. hcloud CLI exited with status: $SERVER_CREATE_STATUS"
    exit $SERVER_CREATE_STATUS
fi

log "INFO" "--- provision_hetzner_node.sh finished ---"
