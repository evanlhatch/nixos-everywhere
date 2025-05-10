#!/usr/bin/env bash
set -euo pipefail

# Script to deploy a server with IPv4 enabled
SERVER_NAME="${1:-nixos-ipv4-test}"
FLAKE_LOCATION="github:evanlhatch/k3s-nixos-config"
FLAKE_ATTRIBUTE="hetznerK3sControlTemplate"
SSH_KEY_NAME="blade-nixos SSH Key"
SERVER_TYPE="cpx21"
LOCATION="ash"

echo "Creating populated script..."
mkdir -p populated
cp ./nixos-everywhere.sh populated/nixos-everywhere-populated.sh
chmod +x populated/nixos-everywhere-populated.sh

# Add populated directory to .gitignore if not already there
if ! grep -q "^populated$" .gitignore 2>/dev/null; then
    echo "populated" >> .gitignore
    echo "Added 'populated' to .gitignore"
fi

# SSH key to use
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT"

# Replace environment variables with actual values
awk -v flake="${FLAKE_LOCATION}#${FLAKE_ATTRIBUTE}" '{gsub(/^FLAKE_URI_INPUT="\${FLAKE_URI:-}"$/, "FLAKE_URI_INPUT=\"" flake "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v channel="nixos-24.11" '{gsub(/^NIXOS_CHANNEL_ENV="\${NIXOS_CHANNEL:-nixos-24.11}"$/, "NIXOS_CHANNEL_ENV=\"" channel "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v hostname="${SERVER_NAME}" '{gsub(/^HOSTNAME_INIT_ENV="\${HOSTNAME_INIT:-\$\(hostname -s 2>\/dev\/null \|\| echo "nixos-node"\)}"$/, "HOSTNAME_INIT_ENV=\"" hostname "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v timezone="Etc/UTC" '{gsub(/^TIMEZONE_INIT_ENV="\${TIMEZONE_INIT:-Etc\/UTC}"$/, "TIMEZONE_INIT_ENV=\"" timezone "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v locale="en_US.UTF-8" '{gsub(/^LOCALE_LANG_INIT_ENV="\${LOCALE_LANG_INIT:-en_US.UTF-8}"$/, "LOCALE_LANG_INIT_ENV=\"" locale "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v version="24.11" '{gsub(/^STATE_VERSION_INIT_ENV="\${STATE_VERSION_INIT:-24.11}"$/, "STATE_VERSION_INIT_ENV=\"" version "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh
awk -v keys="${SSH_KEY}" '{gsub(/^SSH_AUTHORIZED_KEYS_INPUT="\${SSH_AUTHORIZED_KEYS:-}"$/, "SSH_AUTHORIZED_KEYS_INPUT=\"" keys "\""); print}' populated/nixos-everywhere-populated.sh > populated/temp.sh && mv populated/temp.sh populated/nixos-everywhere-populated.sh

echo "Created populated script at populated/nixos-everywhere-populated.sh"
echo "Variables populated:"
echo "  FLAKE_URI: ${FLAKE_LOCATION}#${FLAKE_ATTRIBUTE}"
echo "  NIXOS_CHANNEL: nixos-24.11"
echo "  HOSTNAME_INIT: ${SERVER_NAME}"
echo "  TIMEZONE_INIT: Etc/UTC"
echo "  LOCALE_LANG_INIT: en_US.UTF-8"
echo "  STATE_VERSION_INIT: 24.11"
echo "  SSH_AUTHORIZED_KEYS: (custom value provided)"

# Fetch Hetzner API token
echo "Fetching HCLOUD_TOKEN..."
HCLOUD_TOKEN=$(infisical secrets get HETZNER_API_TOKEN --plain)
if [[ -z "$HCLOUD_TOKEN" ]]; then
    echo "ERROR: HCLOUD_TOKEN could not be fetched. Aborting." >&2
    exit 1
fi
echo "HCLOUD_TOKEN fetched."

# Create user-data for cloud-init
USER_DATA=$(cat <<EOF
#cloud-config
runcmd:
  - |
    # This whole block is executed by cloud-init on the new server
    set -x # Log executed commands to /var/log/cloud-init-output.log for debugging

    # Environment variables for nixos-everywhere.sh
    export FLAKE_URI="${FLAKE_LOCATION}#${FLAKE_ATTRIBUTE}"
    
    # Create a temporary file for SSH keys
    cat > /tmp/authorized_keys_for_nixos <<'END_OF_SSH_KEYS'
${SSH_KEY}
END_OF_SSH_KEYS
    export SSH_AUTHORIZED_KEYS="\$(cat /tmp/authorized_keys_for_nixos)"
    rm -f /tmp/authorized_keys_for_nixos
    
    export NIXOS_CHANNEL="nixos-24.11"
    export HOSTNAME_INIT="${SERVER_NAME}"
    export TIMEZONE_INIT="Etc/UTC"
    export LOCALE_LANG_INIT="en_US.UTF-8"
    export STATE_VERSION_INIT="24.11"
    
    # Download and execute nixos-everywhere.sh
    echo 'INFO: Downloading nixos-everywhere.sh...'
    if curl_output=\$(curl --fail --silent --show-error --location "https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/main/nixos-everywhere.sh" -o /tmp/nixos-everywhere.sh 2>&1); then
      if [[ ! -s /tmp/nixos-everywhere.sh ]]; then echo "FATAL: Downloaded nixos-everywhere.sh is empty!" >&2; echo "Curl output: \$curl_output" >&2; exit 1; fi
      chmod +x /tmp/nixos-everywhere.sh || { echo 'FATAL: chmod on downloaded /tmp/nixos-everywhere.sh failed!' >&2; exit 1; }
      echo 'INFO: Executing downloaded nixos-everywhere.sh...'
      if /tmp/nixos-everywhere.sh; then
        echo 'INFO: nixos-everywhere.sh script execution finished successfully.'
      else
        script_exit_code=\$?
        echo "FATAL: nixos-everywhere.sh script execution FAILED with exit code \$script_exit_code." >&2; exit \$script_exit_code;
      fi
    else
      echo "FATAL: Failed to download nixos-everywhere.sh" >&2
      echo "Curl output: \$curl_output" >&2
      exit 1
    fi
EOF
)

# Deploy the server with IPv4 enabled
echo "Deploying server with IPv4 enabled..."
HCLOUD_TOKEN="$HCLOUD_TOKEN" hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --image "debian-12" \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_NAME" \
    --user-data-from-file <(echo "$USER_DATA")

echo "Server deployment initiated. Check Hetzner Cloud console for progress."