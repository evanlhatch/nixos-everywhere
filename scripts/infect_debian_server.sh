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
# Use the correct GitHub URL for the script
NIXOS_EVERYWHERE_SCRIPT_URL="https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/refactor-v3/scripts/nixos_everywhere.sh"

# --- Construct Remote Command ---
REMOTE_COMMAND=$(cat <<EOF
#!/usr/bin/env bash
set -e
echo ">>> REMOTE COMMAND SCRIPT STARTED ON SERVER <<<"

echo ">>> Phase 1: Attempting to stop Nix services (if they exist)..."
if command -v systemctl &>/dev/null; then
    echo "DEBUG: About to stop nix-daemon.socket"
    systemctl stop nix-daemon.socket || echo " (DEBUG: nix-daemon.socket not active or failed to stop)"
    echo "DEBUG: About to stop nix-daemon.service"
    systemctl stop nix-daemon.service || echo " (DEBUG: nix-daemon.service not active or failed to stop)"
    echo "DEBUG: About to disable nix-daemon.socket"
    systemctl disable nix-daemon.socket || echo " (DEBUG: Failed to disable nix-daemon.socket)"
    echo "DEBUG: About to disable nix-daemon.service"
    systemctl disable nix-daemon.service || echo " (DEBUG: Failed to disable nix-daemon.service)"
    echo "DEBUG: About to sleep 2 seconds..."
    sleep 2
    echo "DEBUG: Sleep complete."
else
    echo "systemctl not found, skipping service stops."
fi
echo ">>> Phase 1 complete."

echo ">>> Phase 2: Attempting to kill lingering Nix processes (if any)..."
# Temporarily commenting out pkill to see if this is the cause of disconnect
# echo "Executing: pkill -f '/nix/store/.*/bin/nix'"
# pkill -f '/nix/store/.*/bin/nix' || echo " (No running Nix processes found by pkill or pkill failed)"
# echo "Executing: pkill -f 'nix-daemon'"
# pkill -f 'nix-daemon' || echo " (No running nix-daemon processes found by pkill or pkill failed)"
echo "SKIPPED pkill commands for this debug run."
sleep 1
echo ">>> Phase 2 complete."

echo ">>> Phase 3: Cleaning up stale Nix profile/backup files..."
echo "Removing /etc/bashrc.backup-before-nix..."
rm -f /etc/bashrc.backup-before-nix
echo "Removing /etc/bash.bashrc.backup-before-nix..."
rm -f /etc/bash.bashrc.backup-before-nix
echo "Removing /etc/zshrc.backup-before-nix..."
rm -f /etc/zshrc.backup-before-nix
echo "Removing /etc/profile.backup-before-nix..."
rm -f /etc/profile.backup-before-nix
echo "Removing /etc/profile.d/nix.sh.backup-before-nix..."
rm -f /etc/profile.d/nix.sh.backup-before-nix
echo "Removing /etc/profile.d/nix.sh..."
rm -f /etc/profile.d/nix.sh
echo "Removing /root/.bashrc.backup-before-nix..."
rm -f /root/.bashrc.backup-before-nix
echo "Removing /root/.zshrc.backup-before-nix..."
rm -f /root/.zshrc.backup-before-nix
echo "Removing /root/.profile.backup-before-nix..."
rm -f /root/.profile.backup-before-nix
echo "Removing Nix systemd unit files..."
rm -f /etc/systemd/system/nix-daemon.service /etc/systemd/system/nix-daemon.socket
echo "Removing Nix tmpfiles.d config..."
rm -f /etc/tmpfiles.d/nix-daemon.conf
echo "Removing Nix user profiles from /root..."
rm -rf /root/.nix-profile /root/.nix-defexpr /root/.nix-channels
echo ">>> Phase 3 complete."

echo ">>> Phase 4: Checking /nix mountpoint (no action taken for now)..."
# Temporarily commenting out umount
# if mountpoint -q /nix; then
#     echo "Attempting to unmount /nix..."
#     umount -l /nix || echo "/nix was a mountpoint but unmount failed. Proceeding cautiously."
# else
#     echo "/nix is not a mountpoint."
# fi
echo "SKIPPED /nix umount check for this debug run."
echo ">>> Phase 4 complete."

echo ">>> Stale Nix file and process cleanup attempt (debug version) complete on remote server."
echo ">>> Proceeding to export variables and run nixos-everywhere.sh..."

# Original commands continue below
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

# Execute the remote command
ssh -t "${INFECT_SSH_USER}@${INFECT_SERVER_IP}" "${REMOTE_COMMAND}"

echo ">>> Infection command sent to ${INFECT_SERVER_IP}."
echo "    Monitor /var/log/nixos-everywhere-manual-infect.log on the server for progress."
# echo ">>> DRY RUN: SSH command was NOT executed." # Commented out for live run
# echo ">>> Infection process command (would be) sent to ${INFECT_SERVER_IP}." # Adjusted for live run
# echo "    (Would) Monitor /var/log/nixos-everywhere-manual-infect.log on the server for progress." # Adjusted for live run
echo "    This process can take a significant amount of time."

exit 0
