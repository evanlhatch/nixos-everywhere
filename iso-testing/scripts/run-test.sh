#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
SSH_PORT="$2"
RESET_MODE="${3:-no}"

CLOUD_INIT_FILE="$VM_DIR/nixos-everywhere-cloud-init.yaml"
LOG_DIR="$VM_DIR/logs"
LOG_FILE="$LOG_DIR/nixos-everywhere-vm.log"
DEBUG_DIR="$LOG_DIR/debug"

# Create log directories
mkdir -p "$LOG_DIR" "$DEBUG_DIR"

echo "⚠️ SAFETY CHECK: This script runs nixos-everywhere INSIDE the VM only."
echo "It will NOT execute nixos-everywhere on your host system."
echo "Connecting to VM to run nixos-everywhere..."

# Check if VM is running by attempting to connect
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=no debian@localhost echo "VM is running" &>/dev/null; then
    echo "Error: Cannot connect to VM. Please make sure the VM is running with 'just start-vm'."
    exit 1
fi

# If reset mode is enabled, clean up any previous installation artifacts
if [ "$RESET_MODE" = "yes" ]; then
    echo "Resetting VM environment to clean state..."
    ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost "sudo bash -c '
        # Remove backup files that might cause conflicts
        rm -f /etc/bash.bashrc.backup-before-nix /etc/profile.d/nix.sh.backup-before-nix /etc/zshrc.backup-before-nix
        
        # Remove any previous nixos-everywhere files
        rm -f /tmp/nixos-everywhere*.sh /tmp/nixos-everywhere*.log
        rm -rf /tmp/nixos-everywhere-debug
        
        # Clean up /etc/nixos if it exists
        rm -rf /etc/nixos/*
        
        # Stop nix-daemon if running
        systemctl stop nix-daemon.socket nix-daemon.service || true
        
        echo \"VM environment reset complete\"
    '"
fi

# Copy wrapper script to VM
echo "Copying wrapper script to VM..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$VM_DIR/nixos-everywhere-wrapper.sh" debian@localhost:/home/debian/

# Copy cloud-init file to VM
echo "Copying cloud-init configuration to VM..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$CLOUD_INIT_FILE" debian@localhost:/tmp/cloud-init.yaml

# Execute cloud-init inside VM with verbose logging
echo "Running nixos-everywhere with enhanced debugging..."
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost "sudo bash -c '
    # Set environment variables for verbose output
    export NIX_EVERYWHERE_DEBUG=1
    export VERBOSE=1
    
    # Run cloud-init with logging
    cloud-init single --name cc_runcmd --frequency always /tmp/cloud-init.yaml 2>&1 | tee /tmp/nixos-everywhere-output.log
'"

# Wait for the script to complete or timeout
echo "Waiting for nixos-everywhere to complete (this may take several minutes)..."
timeout=600  # 10 minutes
elapsed=0
while [ $elapsed -lt $timeout ]; do
    # Check if the debug directory exists and has logs
    if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost "test -d /tmp/nixos-everywhere-debug && test -f /tmp/nixos-everywhere-debug/nixos-everywhere.log"; then
        echo "Debug logs found, copying to host..."
        break
    fi
    
    # Sleep for 10 seconds before checking again
    sleep 10
    elapsed=$((elapsed + 10))
    echo -n "."
done
echo ""

# Create a directory for debug logs
mkdir -p "$DEBUG_DIR"

# Copy all logs back to host
echo "Copying logs from VM to host..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost:/tmp/nixos-everywhere-output.log "$LOG_FILE" || echo "Warning: Could not copy output log from VM"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no -r debian@localhost:/tmp/nixos-everywhere-debug/* "$DEBUG_DIR/" || echo "Warning: Could not copy debug logs from VM"

# Check NixOS configuration
echo "Checking if NixOS configuration was created..."
if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost "sudo test -f /etc/nixos/configuration.nix"; then
    echo "✅ NixOS configuration created successfully!"
    mkdir -p "$LOG_DIR/nixos-config"
    scp -P "$SSH_PORT" -o StrictHostKeyChecking=no debian@localhost:"/etc/nixos/*" "$LOG_DIR/nixos-config/" || echo "Warning: Could not copy NixOS configuration from VM"
else
    echo "❌ NixOS configuration not found."
fi

echo "nixos-everywhere execution completed."
echo "Log files saved to: $LOG_DIR"
echo "Debug information saved to: $DEBUG_DIR"
echo "Run 'just view-log' to see the output log."