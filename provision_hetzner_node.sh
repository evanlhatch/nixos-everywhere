#!/usr/bin/env bash
set -euo pipefail
set -x
# provision_hetzner_node.sh
# Version: 1.1.0
# Helper script called by Justfile to provision a Hetzner server.
# It prepares cloud-init data which then runs nixos-everywhere.sh on the target.

# Logging function (prepends [PROVISION_HELPER] to distinguish from nixos-everywhere.sh logs)
log() {
    local level="$1"
    local message="$2"
    echo "$(date --iso-8601=seconds) - [PROVISION_HELPER] ${level^^} - ${message}"
}

# --- Parameters expected from Justfile (Positional) ---
# This script now expects 23 arguments if Infisical creds are passed.
# Adjust the check if you decide not to pass Infisical creds directly as args here.
EXPECTED_ARGS=23 # 20 original + 3 for Infisical bootstrap
if [[ "$#" -ne "$EXPECTED_ARGS" ]]; then
    log "FATAL" "Incorrect number of arguments. Expected ${EXPECTED_ARGS}, got $#."
    log "FATAL" "Arguments received: $*"
    # Log the mapping of expected arguments if possible, or document it clearly.
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
ARG_LABELS_STR="${12}" # Labels for the server
ARG_NIXOS_CHANNEL="${13}" # For nixos-everywhere.sh bootstrap phase
ARG_TARGET_HOSTNAME_PARAM="${14}" # User's desired hostname for the OS, can be same as ARG_SERVER_NAME
NIXOS_EVERYWHERE_LOCAL_PATH="${15}" # Path to local nixos-everywhere.sh (if embedding)
NIXOS_EVERYWHERE_REMOTE_URL="${16}" # URL to remote nixos-everywhere.sh (if downloading)
DEFAULT_TARGET_HOSTNAME_BASE="${17}" # Fallback base for HOSTNAME_INIT
DEFAULT_TARGET_TIMEZONE="${18}" # For cloud-init environment variables
DEFAULT_TARGET_LOCALE="${19}" # For cloud-init environment variables
DEFAULT_TARGET_STATE_VERSION="${20}" # For cloud-init environment variables

# NEW: Infisical Bootstrap Credentials
ARG_INFISICAL_CLIENT_ID="${21}" # Infisical client ID for bootstrap
ARG_INFISICAL_CLIENT_SECRET="${22}" # Infisical client secret for bootstrap
ARG_INFISICAL_ADDRESS="${23}" # Infisical address for bootstrap


log "INFO" "--- provision_hetzner_node.sh (v1.1.0) started with $# arguments ---"
log "INFO" "Target Server Name (Hetzner): $ARG_SERVER_NAME"
log "INFO" "Flake Location (expected as URL for cloud): $ARG_FLAKE_LOCATION"
log "INFO" "Flake Attribute Input: $ARG_FLAKE_ATTRIBUTE_INPUT"
log "INFO" "Infisical Bootstrap Address: ${ARG_INFISICAL_ADDRESS}"
# Avoid logging client ID and secret directly

# --- Hostname Determination with Enhanced Debug Logging ---
log "DEBUG" "Determining Effective Hostname for NixOS..."
log "DEBUG" "ARG_TARGET_HOSTNAME_PARAM (from Justfile 'target_hostname'): '${ARG_TARGET_HOSTNAME_PARAM}'"
log "DEBUG" "ARG_SERVER_NAME (from Justfile 'server_name'): '${ARG_SERVER_NAME}'"
log "DEBUG" "DEFAULT_TARGET_HOSTNAME_BASE (from Justfile default): '${DEFAULT_TARGET_HOSTNAME_BASE}'"

set -x # Enable command tracing for this specific block

EFFECTIVE_HOSTNAME=""
if [[ -n "$ARG_TARGET_HOSTNAME_PARAM" ]]; then
    EFFECTIVE_HOSTNAME="$ARG_TARGET_HOSTNAME_PARAM"
elif [[ -n "$ARG_SERVER_NAME" ]]; then
    EFFECTIVE_HOSTNAME="$ARG_SERVER_NAME"
else
    # This log will only appear if this branch is taken
    log "INFO" "[set -x] Neither target_hostname nor server_name provided, generating fallback hostname."
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
    EFFECTIVE_HOSTNAME="${DEFAULT_TARGET_HOSTNAME_BASE:-nixos}-${RANDOM_SUFFIX}"
fi

set +x # Disable command tracing
log "INFO" "Effective Hostname for NixOS (to be used as HOSTNAME_INIT): $EFFECTIVE_HOSTNAME"

# --- Flake Attribute Determination ---
ACTUAL_FLAKE_ATTRIBUTE_NAME=""
if [[ "$ARG_FLAKE_ATTRIBUTE_INPUT" == "AUTO_HOSTNAME" ]]; then
    ACTUAL_FLAKE_ATTRIBUTE_NAME="$EFFECTIVE_HOSTNAME"
    log "INFO" "Flake attribute set to 'AUTO_HOSTNAME', will use effective hostname: '$ACTUAL_FLAKE_ATTRIBUTE_NAME'"
else
    ACTUAL_FLAKE_ATTRIBUTE_NAME="$ARG_FLAKE_ATTRIBUTE_INPUT"
    log "INFO" "Using specific Flake attribute: '$ACTUAL_FLAKE_ATTRIBUTE_NAME'"
fi

if [[ -z "$ACTUAL_FLAKE_ATTRIBUTE_NAME" ]]; then
    log "FATAL" "Flake attribute name could not be determined or is empty."
    # Trap will handle exit and line number
fi

# --- Construct Final Flake URI for Cloud-Init ---
CONSTRUCTED_FLAKE_URI="${ARG_FLAKE_LOCATION}#${ACTUAL_FLAKE_ATTRIBUTE_NAME}"
log "INFO" "Final Flake URI to be used in cloud-init: $CONSTRUCTED_FLAKE_URI"
# Warning if ARG_FLAKE_LOCATION doesn't look like a typical fetchable URL
if [[ ! ("$ARG_FLAKE_LOCATION" == github:* || "$ARG_FLAKE_LOCATION" == git+* || "$ARG_FLAKE_LOCATION" == http://* || "$ARG_FLAKE_LOCATION" == https://*) ]]; then
    log "WARN" "FLAKE_LOCATION ('$ARG_FLAKE_LOCATION') does not look like a common remote Flake URL type. Ensure it's accessible by the new server from the internet."
fi

# --- Verify HCLOUD_TOKEN (expected from Justfile's environment) ---
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    log "FATAL" "HCLOUD_TOKEN environment variable is not set. It should be exported by the calling Justfile recipe."
fi
log "INFO" "HCLOUD_TOKEN is present in environment."

# --- Fetch SSH Public Key ---
log "INFO" "Fetching SSH public key for Hetzner key '$ARG_SSH_KEY_NAME'..."
if ! command -v jq &> /dev/null; then log "FATAL" "jq is not installed. Please install it."; fi

SSH_PUBLIC_KEY_CONTENT=$(hcloud ssh-key describe "$ARG_SSH_KEY_NAME" -o json | jq -r .public_key)
if [[ -z "$SSH_PUBLIC_KEY_CONTENT" || "$SSH_PUBLIC_KEY_CONTENT" == "null" ]]; then
    log "FATAL" "Failed to fetch public key for '$ARG_SSH_KEY_NAME'. Check name and HCLOUD_TOKEN permissions."
fi
log "INFO" "SSH public key fetched successfully."

# --- nixos-everywhere.sh Sourcing Logic for Cloud-Init Execution Block ---
NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=""
SCRIPT_CONTENT_BASE64="" # Initialize

if [[ -f "$NIXOS_EVERYWHERE_LOCAL_PATH" ]]; then
    log "INFO" "Local nixos-everywhere.sh found at '$NIXOS_EVERYWHERE_LOCAL_PATH'. Preparing to embed."
    if [[ ! -s "$NIXOS_EVERYWHERE_LOCAL_PATH" ]]; then # Check if file has size > 0
        log "WARN" "Local nixos-everywhere.sh at '$NIXOS_EVERYWHERE_LOCAL_PATH' is empty. Will attempt to use remote URL."
    else
        SCRIPT_CONTENT_BASE64=$(base64 -w0 "$NIXOS_EVERYWHERE_LOCAL_PATH")
        if [[ -z "$SCRIPT_CONTENT_BASE64" ]]; then # Double check if base64 output is empty
            log "WARN" "base64 encoding of local script '$NIXOS_EVERYWHERE_LOCAL_PATH' resulted in empty string. Will attempt remote URL."
        else
            log "INFO" "Embedding local nixos-everywhere.sh (base64 encoded)."
            NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=$(cat <<EOF_INNER_SCRIPT
    echo 'INFO: Decoding embedded nixos-everywhere.sh...'
    base64 -d > /tmp/nixos-everywhere.sh <<'ENDOFSCRIPTBASE64MARKER'
${SCRIPT_CONTENT_BASE64}
ENDOFSCRIPTBASE64MARKER
    if [[ ! -s /tmp/nixos-everywhere.sh ]]; then echo 'FATAL: Embedded nixos-everywhere.sh is empty after decoding!' >&2; exit 1; fi
    chmod +x /tmp/nixos-everywhere.sh || { echo 'FATAL: chmod on embedded /tmp/nixos-everywhere.sh failed!' >&2; exit 1; }
    echo 'INFO: Executing embedded nixos-everywhere.sh...'
    if /tmp/nixos-everywhere.sh; then
      echo 'INFO: nixos-everywhere.sh (embedded) script execution finished successfully.'
    else
      # Capture exit code of nixos-everywhere.sh
      script_exit_code=\$?
      echo "FATAL: nixos-everywhere.sh (embedded) script execution FAILED with exit code \$script_exit_code." >&2; exit \$script_exit_code;
    fi
EOF_INNER_SCRIPT
)
        fi
    fi
fi

# Fallback to remote URL if local embedding was not chosen or failed (e.g. SCRIPT_CONTENT_BASE64 is still empty)
if [[ -z "$NIXOS_EVERYWHERE_EXEC_BLOCK_VAR" ]]; then
    if [[ -n "$NIXOS_EVERYWHERE_REMOTE_URL" ]]; then
        log "INFO" "Using remote nixos-everywhere.sh from URL: ${NIXOS_EVERYWHERE_REMOTE_URL}"
        # Escape for use inside the heredoc passed to cloud-init
        ESCAPED_REMOTE_URL_FOR_HEREDOC=$(printf '%s' "$NIXOS_EVERYWHERE_REMOTE_URL" | sed 's/[&/\]/\\&/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g; s/'\''/\\'\''/g')
        NIXOS_EVERYWHERE_EXEC_BLOCK_VAR=$(cat <<EOF_INNER_SCRIPT
    echo 'INFO: Downloading nixos-everywhere.sh from ${ESCAPED_REMOTE_URL_FOR_HEREDOC}...'
    # Use curl with options to fail on error and follow redirects, output to stdout if download fails for logging
    if curl_output=\$(curl --fail --silent --show-error --location "${ESCAPED_REMOTE_URL_FOR_HEREDOC}" -o /tmp/nixos-everywhere.sh 2>&1); then
      if [[ ! -s /tmp/nixos-everywhere.sh ]]; then echo "FATAL: Downloaded nixos-everywhere.sh from ${ESCAPED_REMOTE_URL_FOR_HEREDOC} is empty!" >&2; echo "Curl output: \$curl_output" >&2; exit 1; fi
      chmod +x /tmp/nixos-everywhere.sh || { echo 'FATAL: chmod on downloaded /tmp/nixos-everywhere.sh failed!' >&2; exit 1; }
      echo 'INFO: Executing downloaded nixos-everywhere.sh...'
      if /tmp/nixos-everywhere.sh; then
        echo 'INFO: nixos-everywhere.sh (downloaded) script execution finished successfully.'
      else
        script_exit_code=\$?
        echo "FATAL: nixos-everywhere.sh (downloaded) script execution FAILED with exit code \$script_exit_code." >&2; exit \$script_exit_code;
      fi
    else
      echo "FATAL: Failed to download nixos-everywhere.sh from ${ESCAPED_REMOTE_URL_FOR_HEREDOC}" >&2
      echo "Curl output: \$curl_output" >&2
      exit 1
    fi
EOF_INNER_SCRIPT
)
    else
        log "FATAL" "nixos-everywhere.sh source not defined. Local path '$NIXOS_EVERYWHERE_LOCAL_PATH' not found/empty, and no remote URL configured."
    fi
fi


# --- Construct User Data for cloud-init ---
log "INFO" "Constructing cloud-init user data..."
# Ensure SSH_PUBLIC_KEY_CONTENT is correctly escaped for embedding in a shell script within YAML
# A simple way is to ensure it doesn't contain single quotes if we wrap it in single quotes.
# Or, for multiline keys, heredoc for export is better.
# Using a direct variable expansion is generally fine if the content is clean.
# For maximum safety, one could base64 encode it here and decode in the cloud-init script part.
# However, cloud-init user-data is usually fine with multi-line env vars.

# Safely embed SSH_AUTHORIZED_KEYS (handles multi-line keys)
# This creates a file on the target and then exports from it, avoiding complex shell escaping
SSH_KEYS_SETUP_BLOCK=$(cat <<EOF_SSH_SETUP
    # Create a temporary file for SSH keys
    cat > /tmp/authorized_keys_for_nixos <<'END_OF_SSH_KEYS'
${SSH_PUBLIC_KEY_CONTENT}
END_OF_SSH_KEYS
    export SSH_AUTHORIZED_KEYS="\$(cat /tmp/authorized_keys_for_nixos)"
    rm -f /tmp/authorized_keys_for_nixos
EOF_SSH_SETUP
)

USER_DATA_CONTENT=$(cat <<EOF_USER_DATA
#cloud-config
runcmd:
  - |
    # This whole block is executed by cloud-init on the new server
    set -x # Log executed commands to /var/log/cloud-init-output.log for debugging

    # Environment variables for nixos-everywhere.sh
    export FLAKE_URI="${CONSTRUCTED_FLAKE_URI}"

${SSH_KEYS_SETUP_BLOCK}

    export NIXOS_CHANNEL="${ARG_NIXOS_CHANNEL}"
    export HOSTNAME_INIT="${EFFECTIVE_HOSTNAME}"
    export TIMEZONE_INIT="${DEFAULT_TARGET_TIMEZONE}"
    export LOCALE_LANG_INIT="${DEFAULT_TARGET_LOCALE}"
    export STATE_VERSION_INIT="${DEFAULT_TARGET_STATE_VERSION}"

    # Pass Infisical Bootstrap Credentials for the Flake build
    export INFISICAL_CLIENT_ID_FOR_FLAKE="${ARG_INFISICAL_CLIENT_ID}"
    export INFISICAL_CLIENT_SECRET_FOR_FLAKE="${ARG_INFISICAL_CLIENT_SECRET}"
    export INFISICAL_ADDRESS_FOR_FLAKE="${ARG_INFISICAL_ADDRESS}"

${NIXOS_EVERYWHERE_EXEC_BLOCK_VAR}
EOF_USER_DATA
)
log "INFO" "--- User Data for cloud-init (first 35 lines preview) ---"
echo "${USER_DATA_CONTENT}" | head -n 35
log "INFO" "-------------------------------------------------------"

# --- Build hcloud command arguments ---
HCLOUD_SERVER_CREATE_ARGS_ARRAY=(
    --name "$ARG_SERVER_NAME"
    --type "$ARG_SERVER_TYPE"
    --image "$ARG_IMAGE"
    --location "$ARG_LOCATION"
    --ssh-key "$ARG_SSH_KEY_NAME"
)
if [[ -n "$ARG_NETWORK" && "$ARG_NETWORK" != "null" && "$ARG_NETWORK" != '""' ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--network "$ARG_NETWORK"); fi
if [[ -n "$ARG_VOLUME" && "$ARG_VOLUME" != "null" && "$ARG_VOLUME" != '""' ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--volume "$ARG_VOLUME"); fi
if [[ -n "$ARG_FIREWALL" && "$ARG_FIREWALL" != "null" && "$ARG_FIREWALL" != '""' ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--firewall "$ARG_FIREWALL"); fi
if [[ -n "$ARG_PLACEMENT_GROUP" && "$ARG_PLACEMENT_GROUP" != "null" && "$ARG_PLACEMENT_GROUP" != '""' ]]; then HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--placement-group "$ARG_PLACEMENT_GROUP"); fi

if [[ -n "$ARG_LABELS_STR" ]]; then
    IFS=';' read -ra LABELS_ARRAY_INTERNAL <<< "$ARG_LABELS_STR"
    for label_item_internal in "${LABELS_ARRAY_INTERNAL[@]}"; do
        if [[ -n "$label_item_internal" ]]; then # Ensure label is not empty
            HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--label "$label_item_internal")
        fi
    done
fi

# Handle public IPv4. You confirmed --without-ipv4 works for your hcloud CLI version.
HCLOUD_SERVER_CREATE_ARGS_ARRAY+=(--without-ipv4)
log "INFO" "Using '--without-ipv4' flag for hcloud server create. Confirmed by user for their hcloud CLI version."


log "INFO" "Initiating server creation with hcloud CLI..."
# HCLOUD_TOKEN is expected to be in the environment, exported by the Justfile recipe calling this script.
if hcloud server create "${HCLOUD_SERVER_CREATE_ARGS_ARRAY[@]}" --user-data-from-file <(echo "$USER_DATA_CONTENT"); then
    log "INFO" "Server '$ARG_SERVER_NAME' creation initiated successfully by hcloud CLI."
    # ... (rest of success logging as before)
    NIXOS_EVERYWHERE_EXPECTED_LOG_ON_SERVER="/var/log/nixos-everywhere.log" # Default from nixos-everywhere.sh internal var
    log "INFO" "Monitor progress via Hetzner Cloud console and server logs (e.g., /var/log/cloud-init-output.log on the server, then ${NIXOS_EVERYWHERE_EXPECTED_LOG_ON_SERVER} once NixOS is up)."

else
    SERVER_CREATE_STATUS=$?
    log "FATAL" "hcloud server create command failed with status: $SERVER_CREATE_STATUS"
    exit $SERVER_CREATE_STATUS
fi

log "INFO" "--- provision_hetzner_node.sh finished successfully ---"
