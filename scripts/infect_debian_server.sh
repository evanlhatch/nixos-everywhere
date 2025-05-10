#!/usr/bin/env bash
set -euxo pipefail

# Expected Environment Variables:
# - INFECT_SERVER_IP
# - INFECT_SSH_USER
# - INFECT_FLAKE_URI
# - INFECT_NIXOS_SSH_KEYS
# - INFECT_NIXOS_CHANNEL
# - INFECT_HOSTNAME_INIT
# - INFECT_TIMEZONE_INIT
# - INFECT_LOCALE_LANG_INIT
# - INFECT_STATE_VERSION_INIT
# - INFECT_INFISICAL_CLIENT_ID (optional)
# - INFECT_INFISICAL_CLIENT_SECRET (optional)
# - INFECT_INFISICAL_BOOTSTRAP_ADDRESS (optional)

# --- Parameter Validation ---
if [ -z "${INFECT_SERVER_IP}" ]; then
    echo "ERROR: INFECT_SERVER_IP environment variable is not set." >&2
    exit 1
fi
if [ -z "${INFECT_SSH_USER}" ]; then
    echo "ERROR: INFECT_SSH_USER environment variable is not set." >&2
    exit 1
fi
if [ -z "${INFECT_FLAKE_URI}" ]; then
    echo "ERROR: INFECT_FLAKE_URI environment variable is not set." >&2
    exit 1
fi
if [ -z "${INFECT_NIXOS_SSH_KEYS}" ]; then
    echo "ERROR: INFECT_NIXOS_SSH_KEYS environment variable is not set!" >&2
    exit 1
fi

# --- Script Configuration ---
NIXOS_EVERYWHERE_SCRIPT_URL="https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/refactor-v3/scripts/nixos_everywhere.sh"

# --- Construct Remote Command ---
REMOTE_COMMAND=$(cat <<EOF
export FLAKE_URI_INPUT='${INFECT_FLAKE_URI}'
export SSH_AUTHORIZED_KEYS_INPUT='${INFECT_NIXOS_SSH_KEYS}'
export NIXOS_CHANNEL_ENV='${INFECT_NIXOS_CHANNEL:-nixos-24.05}'
export HOSTNAME_INIT_ENV='${INFECT_HOSTNAME_INIT:-nixos-infected}'
export TIMEZONE_INIT_ENV='${INFECT_TIMEZONE_INIT:-Etc/UTC}'
export LOCALE_LANG_INIT_ENV='${INFECT_LOCALE_LANG_INIT_ENV:-en_US.UTF-8}'
export STATE_VERSION_INIT_ENV='${INFECT_STATE_VERSION_INIT:-24.05}'
export INFISICAL_CLIENT_ID_FOR_FLAKE='${INFECT_INFISICAL_CLIENT_ID:-}'
export INFISICAL_CLIENT_SECRET_FOR_FLAKE='${INFECT_INFISICAL_CLIENT_SECRET:-}'
export INFISICAL_ADDRESS_FOR_FLAKE='${INFECT_INFISICAL_BOOTSTRAP_ADDRESS:-https://app.infisical.com}'
curl -L "${NIXOS_EVERYWHERE_SCRIPT_URL}" | bash 2>&1 | tee /var/log/nixos-everywhere-manual-infect.log
EOF
)

# --- Execution ---
echo ">>> Preparing to infect Debian server: ${INFECT_SSH_USER}@${INFECT_SERVER_IP}"
echo "    Flake URI for NixOS: ${INFECT_FLAKE_URI}"
echo "    Target Hostname: ${INFECT_HOSTNAME_INIT:-nixos-infected}"
echo "    SSH User for infection: ${INFECT_SSH_USER}"
echo "    NixOS Channel: ${INFECT_NIXOS_CHANNEL:-nixos-24.05}"

echo ">>> Initiating infection on ${INFECT_SSH_USER}@${INFECT_SERVER_IP}."
echo "    Script URL: ${NIXOS_EVERYWHERE_SCRIPT_URL}"
# echo "    REMOTE COMMAND THAT WOULD RUN:" # Commented out for live run
# echo "${REMOTE_COMMAND}" # Commented out for live run

ssh -t "${INFECT_SSH_USER}@${INFECT_SERVER_IP}" "${REMOTE_COMMAND}"

echo ">>> Infection command sent to ${INFECT_SERVER_IP}."
echo "    Monitor /var/log/nixos-everywhere-manual-infect.log on the server for progress."
# echo ">>> DRY RUN: SSH command was NOT executed." # Commented out for live run
# echo ">>> Infection process command (would be) sent to ${INFECT_SERVER_IP}." # Adjusted for live run
# echo "    (Would) Monitor /var/log/nixos-everywhere-manual-infect.log on the server for progress." # Adjusted for live run
echo "    This process can take a significant amount of time."

exit 0
