#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
DEBIAN_CLOUD_IMAGE="$2"
VM_DISK="$3"
DEBIAN_CLOUD_IMAGE_URL="$4"

echo "⚠️ SAFETY NOTICE: This script will create a VM in $VM_DIR"
echo "nixos-everywhere will ONLY run inside this VM, not on your host system."

# Download Debian cloud image if not already present
if [ ! -f "$DEBIAN_CLOUD_IMAGE" ]; then
    echo "Downloading Debian cloud image to $DEBIAN_CLOUD_IMAGE..."
    curl -L -o "$DEBIAN_CLOUD_IMAGE" "$DEBIAN_CLOUD_IMAGE_URL"
fi

# Create a copy of the cloud image for our VM
if [ ! -f "$VM_DISK" ]; then
    echo "Creating VM disk from cloud image..."
    cp "$DEBIAN_CLOUD_IMAGE" "$VM_DISK"
    qemu-img resize "$VM_DISK" 20G
fi

echo "VM setup complete."