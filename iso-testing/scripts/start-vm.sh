#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
VM_DISK="$2"
CLOUD_INIT_ISO="$3"
VM_MEMORY="$4"
VM_CPUS="$5"
SSH_PORT="$6"

if [ ! -f "$VM_DISK" ]; then
    echo "VM disk not found. Please run 'just setup' first."
    exit 1
fi

if [ ! -f "$CLOUD_INIT_ISO" ]; then
    echo "Cloud-init ISO not found. Please run 'just create-cloud-init' first."
    exit 1
fi

echo "Starting VM with cloud-init configuration..."
qemu-system-x86_64 \
    -m "$VM_MEMORY" \
    -smp "$VM_CPUS" \
    -enable-kvm \
    -drive file="$VM_DISK",format=qcow2 \
    -drive file="$CLOUD_INIT_ISO",format=raw \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::"$SSH_PORT"-:22