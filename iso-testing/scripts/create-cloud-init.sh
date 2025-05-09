#!/usr/bin/env bash
set -euo pipefail

VM_DIR="$1"
CLOUD_INIT_ISO="$2"

# Create cloud-init configuration directory
mkdir -p "$VM_DIR/cloud-init"

# Create meta-data file
echo "instance-id: nixos-everywhere-test" > "$VM_DIR/cloud-init/meta-data"
echo "local-hostname: debian-test" >> "$VM_DIR/cloud-init/meta-data"

# Generate a password hash for the default user
PASSWORD_HASH=$(python3 -c 'import crypt; print(crypt.crypt("debian", crypt.mksalt(crypt.METHOD_SHA512)))')

# Find SSH public key
SSH_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "")
if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "No SSH public key found. Creating one for VM access..."
    ssh-keygen -t ed25519 -f "$VM_DIR/vm_key" -N ""
    SSH_PUBLIC_KEY=$(cat "$VM_DIR/vm_key.pub")
    echo "Created new SSH key at $VM_DIR/vm_key"
fi

# Create user-data file
cat > "$VM_DIR/cloud-init/user-data" << EOF
#cloud-config
users:
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $PASSWORD_HASH
    ssh_authorized_keys:
      - $SSH_PUBLIC_KEY

# Enable SSH password authentication
ssh_pwauth: true

# Update and install packages
package_update: true
package_upgrade: true
packages:
  - openssh-server
  - curl
  - wget
  - git
  - vim
  - cloud-init

# Run commands after first boot
runcmd:
  - echo "Cloud-init setup complete"
EOF

# Create cloud-init ISO
echo "Creating cloud-init ISO..."
xorriso -as genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$VM_DIR/cloud-init/user-data" "$VM_DIR/cloud-init/meta-data"

echo "Cloud-init ISO created at $CLOUD_INIT_ISO"