#!/usr/bin/env bash
# scripts/fetch_logs.sh
# Helper script to fetch logs from a server via SSH

# Source the core library for logging and error handling
LIB_CORE_PATH="$(dirname "$0")/lib_core.sh"
if [[ ! -f "$LIB_CORE_PATH" ]]; then
    echo "Critical Error: Core library script (lib_core.sh) not found at $LIB_CORE_PATH" >&2
    exit 1
fi
source "$LIB_CORE_PATH"
enable_robust_error_handling

# Check arguments
if [[ $# -lt 2 ]]; then
    log_error "Usage: $0 <server_name> <ssh_user> [ipv4=false]"
    exit 1
fi

SERVER_NAME="$1"
SSH_USER="$2"
USE_IPV4="${3:-false}"

log_info "Fetching cloud-init logs from server '$SERVER_NAME' as user '$SSH_USER'..."

if [[ "$USE_IPV4" == "false" ]]; then
    # Get IPv6 address
    IPV6=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv6.ip' | sed 's/::\/64/:1/g')
    if [[ -z "$IPV6" ]]; then
        log_error "Could not retrieve IPv6 address for server '$SERVER_NAME'"
        exit 1
    fi
    log_info "Using IPv6 address: [$IPV6]"
    
    # SSH to the server and fetch logs
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@[$IPV6]" \
        "echo '--- /var/log/cloud-init-output.log ---'; \
         sudo cat /var/log/cloud-init-output.log || echo 'Failed to cat /var/log/cloud-init-output.log'; \
         echo '--- /var/log/nixos-conversion-detailed.log ---'; \
         sudo cat /var/log/nixos-conversion-detailed.log || echo 'No nixos-conversion-detailed.log found.'; \
         echo '--- /var/log/nixos-everywhere.log ---'; \
         sudo cat /var/log/nixos-everywhere.log || echo 'No nixos-everywhere.log found.'; \
         echo '--- journalctl -u cloud-init ---'; \
         sudo journalctl -u cloud-init --no-pager -n 50 || echo 'Failed to get cloud-init journal.'; \
         echo '--- journalctl -u cloud-final ---'; \
         sudo journalctl -u cloud-final --no-pager -n 50 || echo 'Failed to get cloud-final journal.'"
else
    # Get IPv4 address
    IPV4=$(hcloud server ip "$SERVER_NAME")
    if [[ -z "$IPV4" ]]; then
        log_error "Could not retrieve IPv4 address for server '$SERVER_NAME'"
        exit 1
    fi
    log_info "Using IPv4 address: $IPV4"
    
    # SSH to the server and fetch logs
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$IPV4" \
        "echo '--- /var/log/cloud-init-output.log ---'; \
         sudo cat /var/log/cloud-init-output.log || echo 'Failed to cat /var/log/cloud-init-output.log'; \
         echo '--- /var/log/nixos-conversion-detailed.log ---'; \
         sudo cat /var/log/nixos-conversion-detailed.log || echo 'No nixos-conversion-detailed.log found.'; \
         echo '--- /var/log/nixos-everywhere.log ---'; \
         sudo cat /var/log/nixos-everywhere.log || echo 'No nixos-everywhere.log found.'; \
         echo '--- journalctl -u cloud-init ---'; \
         sudo journalctl -u cloud-init --no-pager -n 50 || echo 'Failed to get cloud-init journal.'; \
         echo '--- journalctl -u cloud-final ---'; \
         sudo journalctl -u cloud-final --no-pager -n 50 || echo 'Failed to get cloud-final journal.'"
fi