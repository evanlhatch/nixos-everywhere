#!/usr/bin/env bash
set -euo pipefail

DEPS_MISSING=0

# Check for QEMU
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "Required dependency 'qemu-system-x86_64' not found."
    echo "Please install it with: nix-shell -p qemu"
    DEPS_MISSING=1
fi

# Check for xorriso (required for cloud-init ISO creation)
if ! command -v xorriso &> /dev/null; then
    echo "Required dependency 'xorriso' not found."
    echo "Please install it with: nix-shell -p xorriso"
    DEPS_MISSING=1
fi

# Check for curl
if ! command -v curl &> /dev/null; then
    echo "Required dependency 'curl' not found."
    echo "Please install it with: nix-shell -p curl"
    DEPS_MISSING=1
fi

# Check for Python (needed for password hash generation)
if ! command -v python3 &> /dev/null; then
    echo "Required dependency 'python3' not found."
    echo "Please install it with: nix-shell -p python3"
    DEPS_MISSING=1
fi

# Exit if any dependencies are missing
if [ "$DEPS_MISSING" -eq 1 ]; then
    echo ""
    echo "Missing dependencies detected. Please install them and try again."
    echo "For NixOS, you can create a shell with all dependencies:"
    echo "nix-shell -p qemu xorriso curl python3"
    exit 1
fi

echo "All dependencies are installed."