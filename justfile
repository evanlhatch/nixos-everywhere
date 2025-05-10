# justfile
# Main orchestrator for NixOS on Hetzner deployments.

# --- Configuration Loading ---
# Load .env file if it exists
set dotenv-load := true

# --- Default Variables ---
# These can be overridden by environment variables or command-line arguments to just.

# Hetzner Server Defaults
DEFAULT_HETZNER_SERVER_NAME          := "nixos-test"
DEFAULT_HETZNER_SERVER_TYPE          := env_var_or_default('HETZNER_DEFAULT_SERVER_TYPE', 'cpx21')
DEFAULT_HETZNER_BASE_IMAGE           := env_var_or_default('HETZNER_DEFAULT_BASE_IMAGE', 'debian-12')
DEFAULT_HETZNER_LOCATION             := env_var_or_default('HETZNER_DEFAULT_LOCATION', 'ash')
DEFAULT_HETZNER_SSH_KEY_NAME         := env_var_or_default('HETZNER_SSH_KEY_NAME_OR_FINGERPRINT', 'blade-nixos SSH Key')
DEFAULT_HETZNER_NETWORK              := env_var_or_default('HETZNER_DEFAULT_NETWORK', 'k3s-net')
DEFAULT_HETZNER_VOLUME               := env_var_or_default('HETZNER_DEFAULT_VOLUME', 'volume-ash-1')
DEFAULT_HETZNER_FIREWALL             := env_var_or_default('HETZNER_DEFAULT_FIREWALL', 'k3s-fw')
DEFAULT_HETZNER_PLACEMENT_GROUP      := env_var_or_default('HETZNER_DEFAULT_PLACEMENT_GROUP', 'k3s-placement-group')
DEFAULT_HETZNER_LABELS               := env_var_or_default('HETZNER_DEFAULT_LABELS', 'deploy=nixos-everywhere;project=homelab')
DEFAULT_HETZNER_ENABLE_IPV4          := env_var_or_default('HETZNER_DEFAULT_ENABLE_IPV4', 'true')

# NixOS Configuration Defaults
DEFAULT_NIXOS_FLAKE_URI              := env_var_or_default('NIXOS_DEFAULT_FLAKE_URI', 'github:evanlhatch/k3s-nixos-config')
DEFAULT_NIXOS_TARGET_HOST_ATTR       := env_var_or_default('NIXOS_DEFAULT_TARGET_HOST_ATTR', 'hetznerK3sControlTemplate')
DEFAULT_NIXOS_CHANNEL_ENV            := env_var_or_default('NIXOS_DEFAULT_NIXOS_CHANNEL_ENV', 'nixos-24.05')
DEFAULT_HOSTNAME_INIT_ENV            := env_var_or_default('NIXOS_DEFAULT_HOSTNAME_INIT_ENV', 'nixos-server')
DEFAULT_TIMEZONE_INIT_ENV            := env_var_or_default('NIXOS_DEFAULT_TIMEZONE_INIT_ENV', 'Etc/UTC')
DEFAULT_LOCALE_LANG_INIT_ENV         := env_var_or_default('NIXOS_DEFAULT_LOCALE_LANG_INIT_ENV', 'en_US.UTF-8')
DEFAULT_STATE_VERSION_INIT_ENV       := env_var_or_default('NIXOS_DEFAULT_STATE_VERSION_INIT_ENV', '24.05')
DEFAULT_NIXOS_SSH_USER               := env_var_or_default('NIXOS_SSH_USER', 'root')
DEFAULT_NIXOS_SSH_AUTHORIZED_KEYS    := env_var_or_default('NIXOS_SSH_AUTHORIZED_KEYS', '') # For infect-debian; ensure this env var is set with your public keys

# Infisical
DEFAULT_INFISICAL_CLIENT_ID          := env_var_or_default('INFISICAL_CLIENT_ID', '')
DEFAULT_INFISICAL_CLIENT_SECRET      := env_var_or_default('INFISICAL_CLIENT_SECRET', '')
DEFAULT_INFISICAL_BOOTSTRAP_ADDRESS  := env_var_or_default('INFISICAL_BOOTSTRAP_ADDRESS', 'https://app.infisical.com')

# Deployment Method
DEFAULT_DEPLOY_METHOD                := "convert" # 'convert' or 'direct'

# Scripts directory
SCRIPTS_DIR := "./scripts"

# --- Helper Functions ---
# Generates a random 5-character suffix.
random_suffix := "test"

# --- Core Targets ---

# Check local dependencies
check-deps:
    @echo "Checking local dependencies..."
    @{{SCRIPTS_DIR}}/deps_check.sh

# Show help information
help:
    @{{SCRIPTS_DIR}}/show_help.sh

# Provision a new server on Hetzner
# Usage: just provision server_name="my-server" flake_uri="github:user/flake#host" [deploy_method="convert"] [server_type="cpx21"] ...
provision server_name flake_uri \
    deploy_method=DEFAULT_DEPLOY_METHOD \
    server_type=DEFAULT_HETZNER_SERVER_TYPE \
    base_image=DEFAULT_HETZNER_BASE_IMAGE \
    location=DEFAULT_HETZNER_LOCATION \
    ssh_key_name=DEFAULT_HETZNER_SSH_KEY_NAME \
    network=DEFAULT_HETZNER_NETWORK \
    volume=DEFAULT_HETZNER_VOLUME \
    firewall=DEFAULT_HETZNER_FIREWALL \
    placement_group=DEFAULT_HETZNER_PLACEMENT_GROUP \
    labels=DEFAULT_HETZNER_LABELS \
    enable_ipv4=DEFAULT_HETZNER_ENABLE_IPV4 \
    nixos_channel=DEFAULT_NIXOS_CHANNEL_ENV \
    target_hostname_init=DEFAULT_HOSTNAME_INIT_ENV \
    timezone_init=DEFAULT_TIMEZONE_INIT_ENV \
    locale_lang_init=DEFAULT_LOCALE_LANG_INIT_ENV \
    state_version_init=DEFAULT_STATE_VERSION_INIT_ENV \
    infisical_client_id=DEFAULT_INFISICAL_CLIENT_ID \
    infisical_client_secret=DEFAULT_INFISICAL_CLIENT_SECRET \
    infisical_bootstrap_address=DEFAULT_INFISICAL_BOOTSTRAP_ADDRESS:
    @echo "Attempting to provision server '{{server_name}}'..."
    @echo "  Flake URI: {{flake_uri}}"
    @echo "  Deployment Method: {{deploy_method}}"
    @echo "  Server Type: {{server_type}}"
    @echo "  Base Image (for conversion): {{base_image}}"
    @echo "  Location: {{location}}"
    @echo "  SSH Key Name (Hetzner): {{ssh_key_name}}"
    @echo "  Network: {{network}}"
    @echo "  Volume: {{volume}}"
    @echo "  Firewall: {{firewall}}"
    @echo "  Placement Group: {{placement_group}}"
    @echo "  Labels: {{labels}}"
    @echo "  Enable IPv4: {{enable_ipv4}}"

    # Export variables for hetzner_provision.sh
    @export HCLOUD_TOKEN="${HCLOUD_TOKEN}"; \
    export HETZNER_SERVER_NAME="{{server_name}}"; \
    export HETZNER_SERVER_TYPE="{{server_type}}"; \
    export HETZNER_BASE_IMAGE="{{base_image}}"; \
    export HETZNER_LOCATION="{{location}}"; \
    export HETZNER_SSH_KEY_NAME="{{ssh_key_name}}"; \
    export HETZNER_NETWORK="{{network}}"; \
    export HETZNER_VOLUME="{{volume}}"; \
    export HETZNER_FIREWALL="{{firewall}}"; \
    export HETZNER_PLACEMENT_GROUP="{{placement_group}}"; \
    export HETZNER_LABELS="{{labels}}"; \
    export HETZNER_ENABLE_IPV4="{{enable_ipv4}}"; \
    export NIXOS_FLAKE_URI="{{flake_uri}}"; \
    export DEPLOY_METHOD="{{deploy_method}}"; \
    export NIXOS_CHANNEL_ENV="{{nixos_channel}}"; \
    export HOSTNAME_INIT_ENV="{{target_hostname_init}}"; \
    export TIMEZONE_INIT_ENV="{{timezone_init}}"; \
    export LOCALE_LANG_INIT_ENV="{{locale_lang_init}}"; \
    export STATE_VERSION_INIT_ENV="{{state_version_init}}"; \
    export INFISICAL_CLIENT_ID="{{infisical_client_id}}"; \
    export INFISICAL_CLIENT_SECRET="{{infisical_client_secret}}"; \
    export INFISICAL_BOOTSTRAP_ADDRESS="{{infisical_bootstrap_address}}"; \
    {{SCRIPTS_DIR}}/hetzner_provision.sh

# Destroy a server on Hetzner
# Usage: just destroy server_name="my-server"
destroy server_name:
    @echo "Attempting to destroy server '{{server_name}}'..."
    @hcloud server delete "{{server_name}}" \
        || echo "Failed to delete server '{{server_name}}'. It might not exist or an error occurred."

# SSH into a provisioned server
# Usage: just ssh server_name="my-server" [ssh_user="root"] [use_ipv4="true"]
ssh server_name ssh_user=DEFAULT_NIXOS_SSH_USER use_ipv4=DEFAULT_HETZNER_ENABLE_IPV4:
    @echo "Attempting to SSH into server '{{server_name}}' as user '{{ssh_user}}'..."
    @if [ "{{use_ipv4}}" = "true" ]; then \
        IPV4=$(hcloud server ip "{{server_name}}"); \
        echo "Using IPv4 address: $$IPV4"; \
        ssh {{ssh_user}}@$$IPV4; \
    else \
        IPV6=$(hcloud server describe "{{server_name}}" -o json | jq -r '.public_net.ipv6.ip' | sed 's/::\/64/::1/g'); \
        echo "Using IPv6 address: [$$IPV6]"; \
        ssh {{ssh_user}}@[$$IPV6]; \
    fi

# Fetch cloud-init logs from a server
# Usage: just logs server_name="my-server" [ssh_user="root"] [use_ipv4="true"]
logs server_name ssh_user=DEFAULT_NIXOS_SSH_USER use_ipv4=DEFAULT_HETZNER_ENABLE_IPV4:
    @echo "Fetching cloud-init logs from server '{{server_name}}'..."
    @export HCLOUD_TOKEN="${HCLOUD_TOKEN}"; \
    {{SCRIPTS_DIR}}/fetch_logs.sh "{{server_name}}" "{{ssh_user}}" "{{use_ipv4}}"

# List active Hetzner servers
list-servers:
    @echo "Listing Hetzner Cloud servers..."
    @hcloud server list || echo "Failed to list servers. Make sure HCLOUD_TOKEN is set."

# Infect an existing Debian server with NixOS
# Usage: just infect-debian server_ip="1.2.3.4" flake_uri="github:user/flake#host" [ssh_user="root"] [nixos_ssh_keys="<key_content>"] [...]
# Ensure NIXOS_SSH_AUTHORIZED_KEYS environment variable is set if not passing nixos_ssh_keys directly.
infect-debian server_ip flake_uri \
    ssh_user=DEFAULT_NIXOS_SSH_USER \
    nixos_ssh_keys=DEFAULT_NIXOS_SSH_AUTHORIZED_KEYS \
    nixos_channel=DEFAULT_NIXOS_CHANNEL_ENV \
    target_hostname_init=DEFAULT_HOSTNAME_INIT_ENV \
    timezone_init=DEFAULT_TIMEZONE_INIT_ENV \
    locale_lang_init=DEFAULT_LOCALE_LANG_INIT_ENV \
    state_version_init=DEFAULT_STATE_VERSION_INIT_ENV \
    infisical_client_id=DEFAULT_INFISICAL_CLIENT_ID \
    infisical_client_secret=DEFAULT_INFISICAL_CLIENT_SECRET \
    infisical_bootstrap_address=DEFAULT_INFISICAL_BOOTSTRAP_ADDRESS:

    @echo ">>> Preparing to infect Debian server: {{ssh_user}}@{{server_ip}}"
    @echo "    Flake URI for NixOS: {{flake_uri}}"
    @echo "    Target Hostname: {{target_hostname_init}}"
    @echo "    SSH User for infection: {{ssh_user}}"

    @if [ -z "{{nixos_ssh_keys}}" ]; then \
        echo "ERROR: SSH authorized keys are not set!"; \
        echo "       Ensure the NIXOS_SSH_AUTHORIZED_KEYS environment variable is set, or pass nixos_ssh_keys parameter directly."; \
        exit 1; \
    fi

    _NIXOS_EVERYWHERE_SCRIPT_URL := "https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/refactor-v3/scripts/nixos_everywhere.sh"

    # Construct the command to be run on the remote server.
    # Single quotes around substituted variables are important for the remote shell.
    _REMOTE_COMMAND := format(" \
        export FLAKE_URI_INPUT='{}'; \
        export SSH_AUTHORIZED_KEYS_INPUT='{}'; \
        export NIXOS_CHANNEL_ENV='{}'; \
        export HOSTNAME_INIT_ENV='{}'; \
        export TIMEZONE_INIT_ENV='{}'; \
        export LOCALE_LANG_INIT_ENV='{}'; \
        export STATE_VERSION_INIT_ENV='{}'; \
        export INFISICAL_CLIENT_ID_FOR_FLAKE='{}'; \
        export INFISICAL_CLIENT_SECRET_FOR_FLAKE='{}'; \
        export INFISICAL_ADDRESS_FOR_FLAKE='{}'; \
        curl -L {} | bash 2>&1 | tee /var/log/nixos-everywhere-manual-infect.log \
    ", flake_uri, nixos_ssh_keys, nixos_channel, target_hostname_init, timezone_init, locale_lang_init, state_version_init, infisical_client_id, infisical_client_secret, infisical_bootstrap_address, _NIXOS_EVERYWHERE_SCRIPT_URL)

    @echo ">>> Initiating infection on {{ssh_user}}@{{server_ip}}."
    @echo "    Script URL: {{_NIXOS_EVERYWHERE_SCRIPT_URL}}"
    
    @ssh -t {{ssh_user}}@{{server_ip}} {{_REMOTE_COMMAND}}

    @echo ">>> Infection process command sent to {{server_ip}}."
    @echo "    Monitor /var/log/nixos-everywhere-manual-infect.log on the server for progress."
    @echo "    This process can take a significant amount of time."

# Default target: Run check-deps and show help
default:
    @just check-deps
    @echo ""
    @just help
