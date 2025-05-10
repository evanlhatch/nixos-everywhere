#!/usr/bin/env bash
set -euo pipefail

# ======= NIXOS INFECTION TOOL =======
# A comprehensive tool for converting Debian servers to NixOS and monitoring the process
# Usage: ./nixos_infect_tool.sh [command] [options]
#
# Commands:
#   run      - Run the infection process (default)
#   monitor  - Monitor an ongoing infection process
#   check    - Perform a single check of an ongoing infection process
#   log      - Show the recent log entries from an ongoing infection process
#   help     - Show this help message

# Default values
DEFAULT_SERVER_IP="5.161.197.57"
DEFAULT_SSH_USER="root"
DEFAULT_FLAKE_URI="github:evanlhatch/k3s-nixos-config#hetznerK3sControlTemplate"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ======= SAFETY GUARDRAILS =======
# This function checks if we're trying to infect the local machine
check_safety() {
  local target_ip="$1"
  local hostname=$(hostname)
  local local_ips=$(hostname -I 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || ifconfig | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  
  echo -e "${BLUE}🛡️ SAFETY CHECK: Ensuring we're not targeting the local machine${NC}"
  echo -e "   Target IP: $target_ip"
  echo -e "   Local hostname: $hostname"
  echo -e "   Local IPs: $local_ips"
  
  # Check if target IP is localhost or 127.0.0.1
  if [[ "$target_ip" == "localhost" || "$target_ip" == "127.0.0.1" || "$target_ip" == "::1" ]]; then
    echo -e "${RED}❌ CRITICAL SAFETY ERROR: Target IP is localhost!${NC}"
    echo -e "   This script is designed to convert REMOTE Debian servers to NixOS."
    echo -e "   Running it on your local machine could cause SEVERE SYSTEM DAMAGE."
    exit 1
  fi
  
  # Check if target IP matches any local IP
  for ip in $local_ips; do
    if [[ "$ip" == "$target_ip" ]]; then
      echo -e "${RED}❌ CRITICAL SAFETY ERROR: Target IP ($target_ip) matches a local IP address!${NC}"
      echo -e "   This script is designed to convert REMOTE Debian servers to NixOS."
      echo -e "   Running it on your local machine could cause SEVERE SYSTEM DAMAGE."
      exit 1
    fi
  done
  
  echo -e "${GREEN}✅ Safety check passed: Target appears to be a remote server${NC}"
  echo ""
  
  # Final confirmation
  echo -e "${YELLOW}⚠️ WARNING: This script will convert a Debian server to NixOS ⚠️${NC}"
  echo -e "   Target server: $INFECT_SSH_USER@$INFECT_SERVER_IP"
  echo -e "   Flake URI: $INFECT_FLAKE_URI"
  echo ""
  echo -e "   This is a DESTRUCTIVE operation that will REPLACE the operating system."
  echo -e "   The server will be REBOOTED during this process."
  echo ""
  read -p "Are you ABSOLUTELY SURE you want to continue? (type 'yes' to confirm): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Operation cancelled by user."
    exit 1
  fi
  
  echo -e "Proceeding with infection process..."
  echo ""
}

# ======= MONITORING FUNCTIONS =======
# Function to check if SSH is available
check_ssh() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Checking SSH connection...${NC}"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${ssh_user}@${server_ip}" exit &>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
    return 0
  else
    echo -e "${RED}✗ Cannot establish SSH connection${NC}"
    echo -e "  - Check if the server is reachable"
    echo -e "  - Verify SSH credentials"
    echo -e "  - Ensure no firewall is blocking port 22"
    return 1
  fi
}

# Function to check log file
check_log() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Checking infection log file...${NC}"
  if ssh "${ssh_user}@${server_ip}" "test -f /var/log/nixos-everywhere-manual-infect.log"; then
    echo -e "${GREEN}✓ Log file exists${NC}"
    
    # Get log file size
    LOG_SIZE=$(ssh "${ssh_user}@${server_ip}" "stat -c%s /var/log/nixos-everywhere-manual-infect.log")
    echo -e "  Log size: ${LOG_SIZE} bytes"
    
    # Check if log has recent activity
    LAST_MODIFIED=$(ssh "${ssh_user}@${server_ip}" "stat -c%Y /var/log/nixos-everywhere-manual-infect.log")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_MODIFIED))
    
    if [ $TIME_DIFF -lt 300 ]; then
      echo -e "${GREEN}  Log was modified recently (${TIME_DIFF} seconds ago)${NC}"
    else
      echo -e "${YELLOW}  Log hasn't been modified recently (${TIME_DIFF} seconds ago)${NC}"
    fi
    
    return 0
  else
    echo -e "${RED}✗ Log file not found${NC}"
    echo -e "  - The infection process may not have started"
    echo -e "  - Check if the script is running"
    return 1
  fi
}

# Function to check for common errors in the log
check_errors() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Checking for common errors...${NC}"
  
  # Get the last 100 lines of the log
  LOG_TAIL=$(ssh "${ssh_user}@${server_ip}" "tail -n 100 /var/log/nixos-everywhere-manual-infect.log 2>/dev/null" || echo "")
  
  if [[ -z "$LOG_TAIL" ]]; then
    echo -e "${YELLOW}  Could not retrieve log content${NC}"
    return 1
  fi
  
  # Check for common error patterns
  ERROR_COUNT=0
  
  if echo "$LOG_TAIL" | grep -q "Permission denied"; then
    echo -e "${RED}  ✗ Permission denied errors detected${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
  
  if echo "$LOG_TAIL" | grep -q "No space left on device"; then
    echo -e "${RED}  ✗ Disk space issues detected${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
  
  if echo "$LOG_TAIL" | grep -q "Could not resolve host"; then
    echo -e "${RED}  ✗ Network resolution issues detected${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
  
  if echo "$LOG_TAIL" | grep -q "error:"; then
    echo -e "${RED}  ✗ General errors detected${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
  
  if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}  ✓ No common errors detected in recent log entries${NC}"
  fi
  
  return 0
}

# Function to check NixOS installation progress
check_nixos_progress() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Checking NixOS installation progress...${NC}"
  
  # Check if /etc/nixos exists
  if ssh "${ssh_user}@${server_ip}" "test -d /etc/nixos" 2>/dev/null; then
    echo -e "${GREEN}  ✓ /etc/nixos directory exists${NC}"
    
    # Check if configuration.nix exists
    if ssh "${ssh_user}@${server_ip}" "test -f /etc/nixos/configuration.nix" 2>/dev/null; then
      echo -e "${GREEN}  ✓ configuration.nix exists${NC}"
    else
      echo -e "${YELLOW}  ✗ configuration.nix not found${NC}"
    fi
    
    # Check if flake.nix exists
    if ssh "${ssh_user}@${server_ip}" "test -f /etc/nixos/flake.nix" 2>/dev/null; then
      echo -e "${GREEN}  ✓ flake.nix exists${NC}"
    else
      echo -e "${YELLOW}  ✗ flake.nix not found${NC}"
    fi
  else
    echo -e "${YELLOW}  ✗ /etc/nixos directory not found${NC}"
    echo -e "    The NixOS configuration has not been set up yet"
  fi
  
  # Check if nix command is available
  if ssh "${ssh_user}@${server_ip}" "command -v nix" &>/dev/null; then
    echo -e "${GREEN}  ✓ Nix package manager is installed${NC}"
    
    # Get nix version
    NIX_VERSION=$(ssh "${ssh_user}@${server_ip}" "nix --version" 2>/dev/null || echo "Unknown")
    echo -e "    Nix version: ${NIX_VERSION}"
  else
    echo -e "${YELLOW}  ✗ Nix package manager not found${NC}"
    echo -e "    The Nix installation has not completed yet"
  fi
  
  # Check if nixos-rebuild is available
  if ssh "${ssh_user}@${server_ip}" "command -v nixos-rebuild" &>/dev/null; then
    echo -e "${GREEN}  ✓ nixos-rebuild is available${NC}"
    echo -e "    NixOS tools are installed"
  else
    echo -e "${YELLOW}  ✗ nixos-rebuild not found${NC}"
    echo -e "    NixOS tools are not fully installed yet"
  fi
}

# Function to display recent log entries
show_recent_log() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Recent log entries:${NC}"
  echo -e "${YELLOW}-----------------------------------${NC}"
  ssh "${ssh_user}@${server_ip}" "tail -n 20 /var/log/nixos-everywhere-manual-infect.log 2>/dev/null" || echo "Could not retrieve log"
  echo -e "${YELLOW}-----------------------------------${NC}"
}

# Function to check system status
check_system_status() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}Checking system status...${NC}"
  
  # Check uptime
  UPTIME=$(ssh "${ssh_user}@${server_ip}" "uptime -p" 2>/dev/null || echo "Unknown")
  echo -e "  System uptime: ${UPTIME}"
  
  # Check load average
  LOAD=$(ssh "${ssh_user}@${server_ip}" "uptime" 2>/dev/null | grep -oP "load average: \K.*" || echo "Unknown")
  echo -e "  Load average: ${LOAD}"
  
  # Check disk space
  echo -e "  Disk space:"
  ssh "${ssh_user}@${server_ip}" "df -h /" 2>/dev/null || echo "  Could not retrieve disk information"
  
  # Check memory usage
  echo -e "  Memory usage:"
  ssh "${ssh_user}@${server_ip}" "free -h" 2>/dev/null || echo "  Could not retrieve memory information"
}

# Main monitoring loop
monitor_infection() {
  local server_ip="$1"
  local ssh_user="$2"
  
  while true; do
    clear
    echo -e "${BLUE}=== NixOS Infection Monitoring Tool ===${NC}"
    echo -e "Monitoring server: ${ssh_user}@${server_ip}"
    echo -e "Time: $(date)"
    echo ""
    
    if check_ssh "$server_ip" "$ssh_user"; then
      echo ""
      check_log "$server_ip" "$ssh_user"
      echo ""
      check_errors "$server_ip" "$ssh_user"
      echo ""
      check_nixos_progress "$server_ip" "$ssh_user"
      echo ""
      check_system_status "$server_ip" "$ssh_user"
      echo ""
      show_recent_log "$server_ip" "$ssh_user"
    fi
    
    echo ""
    echo -e "${BLUE}Press Ctrl+C to exit monitoring${NC}"
    sleep 10
  done
}

# Function to perform a single check
perform_single_check() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}=== NixOS Infection Status Check ===${NC}"
  echo -e "Checking server: ${ssh_user}@${server_ip}"
  echo -e "Time: $(date)"
  echo ""
  
  if check_ssh "$server_ip" "$ssh_user"; then
    echo ""
    check_log "$server_ip" "$ssh_user"
    echo ""
    check_errors "$server_ip" "$ssh_user"
    echo ""
    check_nixos_progress "$server_ip" "$ssh_user"
    echo ""
    check_system_status "$server_ip" "$ssh_user"
  fi
}

# Function to show only the log
show_log_only() {
  local server_ip="$1"
  local ssh_user="$2"
  
  echo -e "${BLUE}=== NixOS Infection Log ===${NC}"
  echo -e "Server: ${ssh_user}@${server_ip}"
  echo -e "Time: $(date)"
  echo ""
  
  if check_ssh "$server_ip" "$ssh_user"; then
    echo ""
    show_recent_log "$server_ip" "$ssh_user"
  fi
}

# ======= INFECTION FUNCTIONS =======
# Function to run the infection process
run_infection() {
  # Set all required environment variables for infect_debian_server.sh
  export INFECT_SERVER_IP="${SERVER_IP}"
  export INFECT_SSH_USER="${SSH_USER}"
  export INFECT_FLAKE_URI="${FLAKE_URI}"
  
  # IMPORTANT: Replace this with your actual SSH public key if not already set in environment
  if [ -z "${NIXOS_SSH_AUTHORIZED_KEYS:-}" ]; then
    # Try to use a default key if available
    if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
      export INFECT_NIXOS_SSH_KEYS="$(cat $HOME/.ssh/id_rsa.pub)"
      echo -e "Using SSH key from $HOME/.ssh/id_rsa.pub"
    elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      export INFECT_NIXOS_SSH_KEYS="$(cat $HOME/.ssh/id_ed25519.pub)"
      echo -e "Using SSH key from $HOME/.ssh/id_ed25519.pub"
    else
      echo -e "${RED}ERROR: No SSH public key found. Please set INFECT_NIXOS_SSH_KEYS manually.${NC}"
      exit 1
    fi
  else
    export INFECT_NIXOS_SSH_KEYS="${NIXOS_SSH_AUTHORIZED_KEYS}"
  fi
  
  # Set other required variables with defaults
  export INFECT_NIXOS_CHANNEL="nixos-24.05"
  export INFECT_HOSTNAME_INIT="nixos-server"
  export INFECT_TIMEZONE_INIT="Etc/UTC"
  export INFECT_LOCALE_LANG_INIT_ENV="en_US.UTF-8"  # Note the _ENV suffix
  export INFECT_STATE_VERSION_INIT="24.05"
  
  # Optional Infisical variables - uncomment and set if needed
  # export INFECT_INFISICAL_CLIENT_ID="your-client-id"
  # export INFECT_INFISICAL_CLIENT_SECRET="your-client-secret"
  # export INFECT_INFISICAL_BOOTSTRAP_ADDRESS="https://app.infisical.com"
  
  # Print the environment variables for verification
  echo -e "${BLUE}=== Environment Variables Set ===${NC}"
  echo -e "INFECT_SERVER_IP: $INFECT_SERVER_IP"
  echo -e "INFECT_SSH_USER: $INFECT_SSH_USER"
  echo -e "INFECT_FLAKE_URI: $INFECT_FLAKE_URI"
  echo -e "INFECT_NIXOS_SSH_KEYS: ${INFECT_NIXOS_SSH_KEYS:0:30}... (truncated)"
  echo -e "INFECT_NIXOS_CHANNEL: $INFECT_NIXOS_CHANNEL"
  echo -e "INFECT_HOSTNAME_INIT: $INFECT_HOSTNAME_INIT"
  echo -e "INFECT_TIMEZONE_INIT: $INFECT_TIMEZONE_INIT"
  echo -e "INFECT_LOCALE_LANG_INIT_ENV: $INFECT_LOCALE_LANG_INIT_ENV"
  echo -e "INFECT_STATE_VERSION_INIT: $INFECT_STATE_VERSION_INIT"
  echo -e "${BLUE}=== End Environment Variables ===${NC}"
  echo ""
  
  # Run safety check
  check_safety "$INFECT_SERVER_IP"
  
  # Run the just command
  echo -e "Running: just infect-debian server_ip=\"$INFECT_SERVER_IP\" flake_uri=\"$INFECT_FLAKE_URI\""
  just infect-debian server_ip="$INFECT_SERVER_IP" flake_uri="$INFECT_FLAKE_URI"
}

# ======= HELP FUNCTION =======
show_help() {
  echo "NixOS Infection Tool"
  echo "Usage: $0 [command] [options]"
  echo ""
  echo "A comprehensive tool for converting Debian servers to NixOS and monitoring the process."
  echo ""
  echo "Commands:"
  echo "  run      - Run the infection process (default)"
  echo "  monitor  - Monitor an ongoing infection process"
  echo "  check    - Perform a single check of an ongoing infection process"
  echo "  log      - Show the recent log entries from an ongoing infection process"
  echo "  help     - Show this help message"
  echo ""
  echo "Options:"
  echo "  -s, --server IP   - Server IP address (default: $DEFAULT_SERVER_IP)"
  echo "  -u, --user USER   - SSH user (default: $DEFAULT_SSH_USER)"
  echo "  -f, --flake URI   - Flake URI (default: $DEFAULT_FLAKE_URI)"
  echo ""
  echo "Examples:"
  echo "  $0                                  # Run infection with default settings"
  echo "  $0 run -s 192.168.1.100            # Run infection on specific server"
  echo "  $0 monitor -s 192.168.1.100 -u root # Monitor infection on specific server"
  echo "  $0 check -s 192.168.1.100          # Check status once"
  echo "  $0 log -s 192.168.1.100            # Show log entries"
  echo ""
  echo "For more detailed help, see the DEBUGGING.md file."
}

# ======= MAIN SCRIPT =======
# Parse command line arguments
COMMAND="run"
SERVER_IP="$DEFAULT_SERVER_IP"
SSH_USER="$DEFAULT_SSH_USER"
FLAKE_URI="$DEFAULT_FLAKE_URI"

# If first argument doesn't start with a dash, it's a command
if [[ $# -gt 0 && ! "$1" == -* ]]; then
  COMMAND="$1"
  shift
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--server)
      SERVER_IP="$2"
      shift 2
      ;;
    -u|--user)
      SSH_USER="$2"
      shift 2
      ;;
    -f|--flake)
      FLAKE_URI="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Execute the appropriate command
case "$COMMAND" in
  run)
    run_infection
    ;;
  monitor)
    monitor_infection "$SERVER_IP" "$SSH_USER"
    ;;
  check)
    perform_single_check "$SERVER_IP" "$SSH_USER"
    ;;
  log)
    show_log_only "$SERVER_IP" "$SSH_USER"
    ;;
  help)
    show_help
    ;;
  *)
    echo "Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac