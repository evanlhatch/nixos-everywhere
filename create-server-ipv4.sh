#!/usr/bin/env bash
set -euo pipefail

# Script to create a Hetzner Cloud server with IPv4 enabled and proper SSH key setup
SERVER_NAME="${1:-k3s-control-01}"
SERVER_TYPE="${2:-cpx21}"
IMAGE="${3:-debian-12}"
LOCATION="${4:-ash}"
SSH_KEY_NAME="blade-nixos SSH Key"  # Use the exact name from hcloud ssh-key list

# Fetch Hetzner API token
echo "Fetching HCLOUD_TOKEN..."
HCLOUD_TOKEN=$(infisical secrets get HETZNER_API_TOKEN --plain)
if [[ -z "$HCLOUD_TOKEN" ]]; then
    echo "ERROR: HCLOUD_TOKEN could not be fetched. Aborting." >&2
    exit 1
fi
echo "HCLOUD_TOKEN fetched."

# Get SSH key content
echo "Fetching SSH key content..."
SSH_KEY_CONTENT=$(HCLOUD_TOKEN="$HCLOUD_TOKEN" hcloud ssh-key describe "$SSH_KEY_NAME" -o json | jq -r .public_key)
if [[ -z "$SSH_KEY_CONTENT" || "$SSH_KEY_CONTENT" == "null" ]]; then
    echo "ERROR: Failed to fetch SSH key content for '$SSH_KEY_NAME'." >&2
    exit 1
fi
echo "SSH key content fetched."

# Create cloud-init user data
USER_DATA=$(cat <<EOF
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - ${SSH_KEY_CONTENT}
EOF
)

# Create the server with IPv4 enabled and cloud-init data
echo "Creating server $SERVER_NAME with IPv4 enabled..."
HCLOUD_TOKEN="$HCLOUD_TOKEN" hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --image "$IMAGE" \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_NAME" \
    --user-data-from-file <(echo "$USER_DATA")

echo "Server $SERVER_NAME created successfully with IPv4 enabled."
echo "You can check the server status with: HCLOUD_TOKEN=\$HCLOUD_TOKEN hcloud server list"
echo "You can connect to the server with: ssh root@\$(HCLOUD_TOKEN=\"$HCLOUD_TOKEN\" hcloud server ip $SERVER_NAME)"