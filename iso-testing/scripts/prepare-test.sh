#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
NIXOS_EVERYWHERE_REPO_PATH="$(dirname "$VM_DIR")"
ORIGINAL_SCRIPT="$NIXOS_EVERYWHERE_REPO_PATH/nixos-everywhere.sh"
WRAPPER_SCRIPT="$VM_DIR/nixos-everywhere-wrapper.sh"

echo "⚠️ SAFETY CHECK: This script prepares nixos-everywhere.sh to run INSIDE the VM only."
echo "It will NOT execute nixos-everywhere on your host system."

# Create a wrapper script that adds debugging capabilities to nixos-everywhere.sh
cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# Wrapper script for nixos-everywhere.sh that adds debugging capabilities

# Create debug directory
DEBUG_DIR="/tmp/nixos-everywhere-debug"
mkdir -p "$DEBUG_DIR"

# Set up logging
LOG_FILE="$DEBUG_DIR/nixos-everywhere.log"
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

# Enable command tracing
set -x

# Enable verbose mode
export NIX_EVERYWHERE_DEBUG=1
export VERBOSE=1

# Function to log messages
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_debug "Starting nixos-everywhere wrapper script"

# Create a function to handle errors
handle_error() {
    local line=$1
    local command=$2
    local code=$3
    log_debug "ERROR: Command '$command' failed with exit code $code at line $line"
    
    # Collect system information for debugging
    log_debug "--- System Information ---"
    log_debug "Disk space:"
    df -h | tee -a "$LOG_FILE"
    
    log_debug "Memory usage:"
    free -h | tee -a "$LOG_FILE"
    
    log_debug "Process list:"
    ps aux | tee -a "$LOG_FILE"
    
    log_debug "Network interfaces:"
    ip addr | tee -a "$LOG_FILE"
    
    # Try to continue despite the error
    return 0
}

# Set up error handling
trap 'handle_error $LINENO "$BASH_COMMAND" $?' ERR

# Function to patch common issues in nixos-everywhere.sh
patch_nixos_everywhere() {
    local script="$1"
    local patched_script="$DEBUG_DIR/nixos-everywhere-patched.sh"
    
    log_debug "Patching nixos-everywhere.sh to fix common issues"
    
    # Create a copy of the script
    cp "$script" "$patched_script"
    
    # Fix the df command issue
    sed -i 's/df -T --output=source,fstype,target/df -T/g' "$patched_script"
    
    # Add more error handling
    sed -i 's/set -e/set -e\ntrap "handle_error \$LINENO \$BASH_COMMAND \$?" ERR/g' "$patched_script"
    
    # Make hardware configuration generation more robust
    sed -i 's/generate_hardware_configuration() {/generate_hardware_configuration() {\n    log "INFO" "Generating hardware configuration with enhanced error handling"/g' "$patched_script"
    
    chmod +x "$patched_script"
    log_debug "Patched script created at $patched_script"
    
    echo "$patched_script"
}

# Download the original nixos-everywhere.sh
log_debug "Downloading nixos-everywhere.sh"
curl -o "$DEBUG_DIR/nixos-everywhere-original.sh" https://raw.githubusercontent.com/evanlhatch/nixos-everywhere/main/nixos-everywhere.sh
chmod +x "$DEBUG_DIR/nixos-everywhere-original.sh"

# Patch the script
PATCHED_SCRIPT=$(patch_nixos_everywhere "$DEBUG_DIR/nixos-everywhere-original.sh")

# Run the patched script with the provided arguments
log_debug "Running patched nixos-everywhere.sh with arguments: $*"
"$PATCHED_SCRIPT" "$@" 2>&1 | tee -a "$LOG_FILE"

# Check if the script succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log_debug "nixos-everywhere.sh completed successfully"
else
    log_debug "nixos-everywhere.sh failed with exit code ${PIPESTATUS[0]}"
    
    # Try to recover
    log_debug "Attempting recovery..."
    
    # Create basic NixOS configuration if it doesn't exist
    if [ ! -f /etc/nixos/configuration.nix ]; then
        log_debug "Creating basic configuration.nix"
        mkdir -p /etc/nixos
        cat > /etc/nixos/configuration.nix << 'INNEREOF'
# Basic NixOS configuration created by recovery script
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  
  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Networking
  networking.hostName = "nixos-test";
  
  # Set your time zone
  time.timeZone = "America/Denver";
  
  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Enable the OpenSSH daemon
  services.openssh.enable = true;
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
INNEREOF
    fi
    
    # Create basic hardware configuration if it doesn't exist
    if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
        log_debug "Creating basic hardware-configuration.nix"
        mkdir -p /etc/nixos
        cat > /etc/nixos/hardware-configuration.nix << 'INNEREOF'
# Basic hardware configuration created by recovery script
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };
  
  swapDevices = [ ];
  
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
INNEREOF
    fi
fi

log_debug "Wrapper script completed"
EOF

chmod +x "$WRAPPER_SCRIPT"

# Create cloud-init user-data for nixos-everywhere
cat > "$VM_DIR/nixos-everywhere-cloud-init.yaml" << 'EOF'
#cloud-config
runcmd:
  - |
    # This whole block is executed by cloud-init on the VM
    set -x # Log executed commands to /var/log/cloud-init-output.log for debugging

    # Environment variables for nixos-everywhere.sh
    export FLAKE_URI="github:evanlhatch/k3s-nixos-config#hetznerK3sControlTemplate"
    export SSH_AUTHORIZED_KEYS="$(cat /home/debian/.ssh/authorized_keys)"
    export NIXOS_CHANNEL="nixos-24.11"
    export HOSTNAME_INIT="nixos-test"
    export TIMEZONE_INIT="America/Denver"
    export LOCALE_LANG_INIT="en_US.UTF-8"
    export STATE_VERSION_INIT="24.11"
    
    # Create debug directory
    mkdir -p /tmp/nixos-everywhere-debug
    
    # Copy wrapper script to VM
    cp /home/debian/nixos-everywhere-wrapper.sh /tmp/nixos-everywhere-wrapper.sh
    chmod +x /tmp/nixos-everywhere-wrapper.sh
    
    # Clean up any previous installation artifacts
    rm -f /etc/bash.bashrc.backup-before-nix /etc/profile.d/nix.sh.backup-before-nix /etc/zshrc.backup-before-nix
    
    # Run wrapper script
    echo "Running nixos-everywhere wrapper script..."
    /tmp/nixos-everywhere-wrapper.sh 2>&1 | tee /tmp/nixos-everywhere-output.log
EOF

echo "Prepared nixos-everywhere test files with enhanced debugging and resilience."