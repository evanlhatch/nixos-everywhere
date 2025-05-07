# Justfile for Hetzner + nixos-everywhere provisioning

# --- Default Configuration ---
# These can be overridden when calling a recipe, e.g., just create-server server_type="cpx31"

# Hetzner Server Defaults
DEFAULT_SERVER_TYPE         := "cpx21"
DEFAULT_SERVER_IMAGE        := "debian-12"  # Initial OS for infection by nixos-everywhere.sh
DEFAULT_SERVER_LOCATION     := "ash"        # Ashburn, VA
DEFAULT_SSH_KEY_NAME        := "blade-nixos SSH Key" # Name of your SSH key already in Hetzner Cloud
DEFAULT_PRIVATE_NETWORK     := "k3s-net"
DEFAULT_VOLUME_NAME         := "volume-ash-1"
DEFAULT_FIREWALL_NAME       := "k3s-fw"
DEFAULT_PLACEMENT_GROUP     := "k3s-placement-group"
DEFAULT_LABELS              := "deploy=nixos-everywhere;project=homelab" # Semicolon-separated labels

# nixos-everywhere.sh Sourcing:
# The provision_hetzner_node.sh script (called by create-server) will use these
# to decide whether to embed a local nixos-everywhere.sh or download it.
NIXOS_EVERYWHERE_LOCAL_PATH := "./nixos-everywhere.sh"  # Default local path to your installer script
NIXOS_EVERYWHERE_REMOTE_URL := "https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/main/nixos-everywhere.sh" # Fallback/default URL

# Flake Source:
# These define the default Flake to be deployed.
DEFAULT_FLAKE_LOCATION      := "github:evanlhatch/k3s-nixos-config" # Default is your specified remote GitHub Flake URL
DEFAULT_FLAKE_ATTRIBUTE     := "hetznerK3sControlTemplate" # Default Flake attribute to deploy

# Defaults for environment variables passed to nixos-everywhere.sh via cloud-init
# These are used by the provision_hetzner_node.sh script when constructing the cloud-init payload.
DEFAULT_TARGET_NIXOS_CHANNEL  := "nixos-24.11"
DEFAULT_TARGET_HOSTNAME_BASE  := "nixos" # Used by provision_hetzner_node.sh if server_name/target_hostname empty
DEFAULT_TARGET_TIMEZONE       := "Etc/UTC"
DEFAULT_TARGET_LOCALE         := "en_US.UTF-8"
DEFAULT_TARGET_STATE_VERSION  := "24.11"

# Infisical Bootstrap Credentials (expected to be in .env via direnv, or passed to just)
# These are passed to provision_hetzner_node.sh, then to cloud-init for nixos-everywhere.sh
INFISICAL_BOOTSTRAP_CLIENT_ID_ENV     := env_var_or_default('INFISICAL_BOOTSTRAP_CLIENT_ID', '')
INFISICAL_BOOTSTRAP_CLIENT_SECRET_ENV := env_var_or_default('INFISICAL_BOOTSTRAP_CLIENT_SECRET', '')
INFISICAL_BOOTSTRAP_ADDRESS_ENV       := env_var_or_default('INFISICAL_BOOTSTRAP_ADDRESS', 'https://app.infisical.com')


# --- Hidden Helper Recipe ---
_fetch_hcloud_token:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v infisical &> /dev/null; then
        echo "ERROR: infisical CLI not found. Please install and configure it." >&2; exit 1;
    fi
    # Ensure HETZNER_API_TOKEN is the correct secret name in Infisical
    TOKEN=$(infisical secrets get HETZNER_API_TOKEN --plain)
    if [[ -z "$TOKEN" ]]; then
        echo "ERROR: Failed to retrieve HETZNER_API_TOKEN from Infisical. Is it set and accessible?" >&2; exit 1;
    fi
    echo -n "$TOKEN"

# --- Main Recipes ---

# Creates a new Hetzner server by calling the provision_hetzner_node.sh helper script.
# This helper script contains the main logic for fetching keys, constructing cloud-init,
# and calling 'hcloud server create'.
#
# MANDATORY ARGUMENTS:
#   server_name     - Unique name for the new server.
#
# OPTIONAL ARGUMENTS (see defaults above):
#   flake_location  - URL for the Flake (default is your GitHub repo).
#   flake_attribute - NixOS configuration attribute in the Flake (default: "hetznerK3sControlTemplate").
#                     Can be set to "AUTO_HOSTNAME" for the helper script to use server_name.
#   infisical_client_id, infisical_client_secret, infisical_address - For Infisical Agent bootstrap.
#   ... (other server parameters like server_type, image, location, etc.) ...
#
# EXAMPLE USAGE:
#   just create-server server_name="my-k3s-control-01"
#   just create-server server_name="worker-bee" flake_attribute="hetznerK3sWorkerTemplate"
#   just create-server server_name="dev-node" flake_location="github:myfork/myflake" flake_attribute="devConfig" server_type="cpx11"
create-server server_name flake_location=DEFAULT_FLAKE_LOCATION flake_attribute=DEFAULT_FLAKE_ATTRIBUTE server_type=DEFAULT_SERVER_TYPE image=DEFAULT_SERVER_IMAGE location=DEFAULT_SERVER_LOCATION ssh_key_name=DEFAULT_SSH_KEY_NAME network=DEFAULT_PRIVATE_NETWORK volume=DEFAULT_VOLUME_NAME firewall=DEFAULT_FIREWALL_NAME placement_group=DEFAULT_PLACEMENT_GROUP labels=DEFAULT_LABELS nixos_channel=DEFAULT_TARGET_NIXOS_CHANNEL target_hostname="" infisical_client_id=INFISICAL_BOOTSTRAP_CLIENT_ID_ENV infisical_client_secret=INFISICAL_BOOTSTRAP_CLIENT_SECRET_ENV infisical_address=INFISICAL_BOOTSTRAP_ADDRESS_ENV:
    #!/usr/bin/env bash
    set -euo pipefail

    # Fetch HCLOUD_TOKEN and export it so the helper script and its hcloud commands can use it
    echo "Fetching HCLOUD_TOKEN..."
    export HCLOUD_TOKEN=$(just _fetch_hcloud_token)
    if [[ -z "$HCLOUD_TOKEN" ]]; then
        echo "ERROR: HCLOUD_TOKEN could not be fetched. Aborting." >&2
        exit 1
    fi
    echo "HCLOUD_TOKEN fetched and exported for helper script."

    # Ensure the helper script exists and is executable
    HELPER_SCRIPT_PATH="./provision_hetzner_node.sh" # Assuming it's in the same directory as Justfile
    if [[ ! -f "$HELPER_SCRIPT_PATH" ]]; then
        echo "ERROR: Helper script '$HELPER_SCRIPT_PATH' not found." >&2
        exit 1
    fi
    if [[ ! -x "$HELPER_SCRIPT_PATH" ]]; then
        echo "ERROR: Helper script '$HELPER_SCRIPT_PATH' is not executable. Please chmod +x it." >&2
        exit 1
    fi

    # Call the external helper script, passing all parameters
    # The helper script will handle default logic for optional cloud-init env vars
    echo "Calling helper script: $HELPER_SCRIPT_PATH with Infisical bootstrap parameters"
    "$HELPER_SCRIPT_PATH" \
        "{{server_name}}" \
        "{{flake_location}}" \
        "{{flake_attribute}}" \
        "{{server_type}}" \
        "{{image}}" \
        "{{location}}" \
        "{{ssh_key_name}}" \
        "{{network}}" \
        "{{volume}}" \
        "{{firewall}}" \
        "{{placement_group}}" \
        "{{labels}}" \
        "{{nixos_channel}}" \
        "{{target_hostname}}" \
        "{{NIXOS_EVERYWHERE_LOCAL_PATH}}" \
        "{{NIXOS_EVERYWHERE_REMOTE_URL}}" \
        "{{DEFAULT_TARGET_HOSTNAME_BASE}}" \
        "{{DEFAULT_TARGET_TIMEZONE}}" \
        "{{DEFAULT_TARGET_LOCALE}}" \
        "{{DEFAULT_TARGET_STATE_VERSION}}" \
        "{{infisical_client_id}}" \
        "{{infisical_client_secret}}" \
        "{{infisical_address}}"
    # The exit code of the helper script will be the exit code of this recipe

list-servers: _fetch_hcloud_token
    #!/usr/bin/env bash
    set -euo pipefail
    # Fetch token and set it for the hcloud command
    HETZNER_API_TOKEN_VAL=$(just _fetch_hcloud_token)
    HCLOUD_TOKEN="$HETZNER_API_TOKEN_VAL" hcloud server list -o noheader -o columns=id,name,status,ipv4,ipv6,location,server_type

default:
    @just -l
