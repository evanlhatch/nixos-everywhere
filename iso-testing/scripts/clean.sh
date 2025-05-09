#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
VM_NAME="$2"

echo "Cleaning up generated files..."
rm -f "$VM_DIR/$VM_NAME.qcow2"
rm -f "$VM_DIR/debian-12-generic-amd64.qcow2"
rm -f "$VM_DIR/cloud-init-config.iso"
rm -f "$VM_DIR/nixos-everywhere.sh"
rm -f "$VM_DIR/nixos-everywhere-cloud-init.yaml"
rm -rf "$VM_DIR/cloud-init"
rm -f "$VM_DIR/vm_key" "$VM_DIR/vm_key.pub"

echo "Cleanup complete."