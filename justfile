# justfile
# Main orchestrator for NixOS on Hetzner deployments.

# --- Configuration Loading ---
# Attempt to load .env file if it exists. Variables in .env take precedence.
# Using a subshell to check for file existence and then source it.
# This ensures 'just' doesn't fail if .env is missing.
export $(shell test -f .env && cat .env | sed 's/#.*//g; /^\s*$$/d' | xargs)

# Load default configurations. .env variables can override these.
# The order matters: later files can override earlier ones if variables conflict.
# Common defaults first, then more specific ones.
include config/common.env
include config/nixos.env
include config/hetzner.env


# --- Aliases and Default Variables ---
# These can be overridden by environment variables or command-line arguments to just.

# Hetzner Server Defaults (from config/hetzner.env, can be overridden)
DEFAULT_HETZNER_SERVER_NAME          := "nixos-{{ random_suffix() }}" # Ensures unique names if not specified
DEFAULT_HETZNER_SERVER_TYPE          ?= HETZNER_DEFAULT_SERVER_TYPE
DEFAULT_HETZNER_BASE_IMAGE           ?= HETZNER_DEFAULT_BASE_IMAGE # For conversion method
DEFAULT_HETZNER_LOCATION             ?= HETZNER_DEFAULT_LOCATION
DEFAULT_HETZNER_SSH_KEY_NAME         ?= HETZNER_SSH_KEY_NAME_OR_FINGERPRINT # From .env or config/hetzner.env

# NixOS Configuration Defaults (from config/nixos.env)
DEFAULT_NIXOS_FLAKE_URI              ?= NIXOS_DEFAULT_FLAKE_URI
DEFAULT_NIXOS_TARGET_HOST_ATTR       ?= NIXOS_DEFAULT_TARGET_HOST_ATTR # Placeholder, user must provide full flake_uri usually
DEFAULT_NIXOS_CHANNEL_ENV            ?= NIXOS_DEFAULT_NIXOS_CHANNEL_ENV
DEFAULT_HOSTNAME_INIT_ENV            ?= NIXOS_DEFAULT_HOSTNAME_INIT_ENV
DEFAULT_TIMEZONE_INIT_ENV            ?= NIXOS_DEFAULT_TIMEZONE_INIT_ENV
DEFAULT_LOCALE_LANG_INIT_ENV         ?= NIXOS_DEFAULT_LOCALE_LANG_INIT_ENV
DEFAULT_STATE_VERSION_INIT_ENV       ?= NIXOS_DEFAULT_STATE_VERSION_INIT_ENV
DEFAULT_NIXOS_SSH_USER               ?= NIXOS_SSH_USER # From .env or config/nixos.env

# Infisical (from .env or config/common.env)
DEFAULT_INFISICAL_CLIENT_ID          ?= INFISICAL_CLIENT_ID
DEFAULT_INFISICAL_CLIENT_SECRET      ?= INFISICAL_CLIENT_SECRET
DEFAULT_INFISICAL_BOOTSTRAP_ADDRESS  ?= INFISICAL_BOOTSTRAP_ADDRESS

# Deployment Method
DEFAULT_DEPLOY_METHOD                := "convert" # 'convert' or 'direct'

# Scripts directory
SCRIPTS_DIR := "./scripts"

# --- Helper Functions ---
# Generates a random 5-character suffix.
random_suffix := $(shell head /dev/urandom | tr -dc a-z0-9 | head -c 5)

# --- Pre-flight Checks ---
# Ensure HCLOUD_TOKEN is set
_check_hcloud_token:
    @if [ -z "{{HCLOUD_TOKEN}}" ]; then \
        echo "Error: HCLOUD_TOKEN is not set. Please define it in your .env file or as an environment variable."; \
        exit 1; \
    fi
    @echo "HCLOUD_TOKEN found."

# Ensure SSH key name/fingerprint is configured for Hetzner
_check_hetzner_ssh_key:
    @if [ -z "{{DEFAULT_HETZNER_SSH_KEY_NAME}}" ]; then \
        echo "Error: HETZNER_SSH_KEY_NAME_OR_FINGERPRINT is not set. Please define it in .env or config/hetzner.env."; \
        echo "This should be the name or fingerprint of an SSH key already uploaded to your Hetzner Cloud project."; \
        exit 1; \
    fi
    @echo "Hetzner SSH key name/fingerprint configured: {{DEFAULT_HETZNER_SSH_KEY_NAME}}"


# --- Core Targets ---

# Check local dependencies
check-deps:
    @echo "Checking local dependencies..."
    @{{SCRIPTS_DIR}}/deps_check.sh

# Provision a new server on Hetzner
# Usage: just provision server_name="my-server" flake_uri="github:user/flake#host" [deploy_method="convert"] [server_type="cpx21"] ...
provision server_name flake_uri \
    deploy_method=DEFAULT_DEPLOY_METHOD \
    server_type=DEFAULT_HETZNER_SERVER_TYPE \
    base_image=DEFAULT_HETZNER_BASE_IMAGE \
    location=DEFAULT_HETZNER_LOCATION \
    ssh_key_name=DEFAULT_HETZNER_SSH_KEY_NAME \
    nixos_channel=DEFAULT_NIXOS_CHANNEL_ENV \
    target_hostname_init=DEFAULT_HOSTNAME_INIT_ENV \
    timezone_init=DEFAULT_TIMEZONE_INIT_ENV \
    locale_lang_init=DEFAULT_LOCALE_LANG_INIT_ENV \
    state_version_init=DEFAULT_STATE_VERSION_INIT_ENV \
    infisical_client_id=DEFAULT_INFISICAL_CLIENT_ID \
    infisical_client_secret=DEFAULT_INFISICAL_CLIENT_SECRET \
    infisical_bootstrap_address=DEFAULT_INFISICAL_BOOTSTRAP_ADDRESS: _check_hcloud_token _check_hetzner_ssh_key check-deps
    @echo "Attempting to provision server '{{server_name}}'..."
    @echo "  Flake URI: {{flake_uri}}"
    @echo "  Deployment Method: {{deploy_method}}"
    @echo "  Server Type: {{server_type}}"
    @echo "  Base Image (for conversion): {{base_image}}"
    @echo "  Location: {{location}}"
    @echo "  SSH Key Name (Hetzner): {{ssh_key_name}}"

    # Export variables for hetzner_provision.sh
    @export HCLOUD_TOKEN="{{HCLOUD_TOKEN}}"; \
    export HETZNER_SERVER_NAME="{{server_name}}"; \
    export HETZNER_SERVER_TYPE="{{server_type}}"; \
    export HETZNER_BASE_IMAGE="{{base_image}}"; \
    export HETZNER_LOCATION="{{location}}"; \
    export HETZNER_SSH_KEY_NAME="{{ssh_key_name}}"; \
    export NIXOS_FLAKE_URI="{{flake_uri}}"; \
    # NIXOS_FLAKE_HOST_ATTR is derived from flake_uri in the script
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
destroy server_name: _check_hcloud_token
    @echo "Attempting to destroy server '{{server_name}}'..."
    @HCLOUD_TOKEN="{{HCLOUD_TOKEN}}" hcloud server delete "{{server_name}}" \
        || echo "Failed to delete server '{{server_name}}'. It might not exist or an error occurred."

# SSH into a provisioned server
# Usage: just ssh server_name="my-server" [ssh_user="root"]
ssh server_name ssh_user=DEFAULT_NIXOS_SSH_USER: _check_hcloud_token
    @echo "Attempting to SSH into server '{{server_name}}' as user '{{ssh_user}}'..."
    @SERVER_IP=$$(HCLOUD_TOKEN="{{HCLOUD_TOKEN}}" hcloud server ip "{{server_name}}"); \
    if [ -z "$$SERVER_IP" ]; then \
        echo "Error: Could not retrieve IP address for server '{{server_name}}'."; \
        echo "Ensure the server exists and is running."; \
        exit 1; \
    fi; \
    echo "Connecting to $$SERVER_IP..."; \
    ssh {{ssh_user}}@$$SERVER_IP

# Fetch cloud-init logs from a server
# Usage: just logs server_name="my-server" [ssh_user="root"]
logs server_name ssh_user=DEFAULT_NIXOS_SSH_USER: _check_hcloud_token
    @echo "Fetching cloud-init logs from server '{{server_name}}'..."
    @SERVER_IP=$$(HCLOUD_TOKEN="{{HCLOUD_TOKEN}}" hcloud server ip "{{server_name}}"); \
    if [ -z "$$SERVER_IP" ]; then \
        echo "Error: Could not retrieve IP address for server '{{server_name}}'."; \
        exit 1; \
    fi; \
    echo "Connecting to $$SERVER_IP to fetch logs..."; \
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null {{ssh_user}}@$$SERVER_IP \
        "echo '--- /var/log/cloud-init-output.log ---'; sudo cat /var/log/cloud-init-output.log || echo 'Failed to cat /var/log/cloud-init-output.log'; \
         echo '\n--- /var/log/nixos-conversion-detailed.log (if convert method used) ---'; sudo cat /var/log/nixos-conversion-detailed.log || echo 'No nixos-conversion-detailed.log found.'; \
         echo '\n--- /var/log/nixos-everywhere.log (if conversion script created it) ---'; sudo cat /var/log/nixos-everywhere.log || echo 'No nixos-everywhere.log found.'; \
         echo '\n--- journalctl -u cloud-init ---'; sudo journalctl -u cloud-init --no-pager -n 50 || echo 'Failed to get cloud-init journal.'; \
         echo '\n--- journalctl -u cloud-final ---'; sudo journalctl -u cloud-final --no-pager -n 50 || echo 'Failed to get cloud-final journal.'"

# List active Hetzner servers
list-servers: _check_hcloud_token
    @echo "Listing Hetzner Cloud servers..."
    @HCLOUD_TOKEN="{{HCLOUD_TOKEN}}" hcloud server list

# Default target: List available recipes
default:
    @just --list
    @echo "\nCommon Workflows:"
    @echo "  1. Ensure .env is configured with HCLOUD_TOKEN and HETZNER_SSH_KEY_NAME_OR_FINGERPRINT."
    @echo "  2. Check dependencies: just check-deps"
    @echo "  3. Provision a server: just provision server_name=\"my-test\" flake_uri=\"github:your/flake#host\""
    @echo "  4. Monitor logs: just logs server_name=\"my-test\""
    @echo "  5. SSH into server: just ssh server_name=\"my-test\""
    @echo "  6. Destroy server: just destroy server_name=\"my-test\""
