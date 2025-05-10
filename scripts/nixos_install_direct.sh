#!/usr/bin/env bash
# scripts/nixos_install_direct.sh
# This script is run by cloud-init on the target server for a direct NixOS installation.
# WARNING: This script is destructive and will re-partition/format disks.

exec > >(tee -a "/var/log/nixos-direct-install-detailed.log") 2>&1
set -ex # Log executed commands and exit on error

echo "--- nixos_install_direct.sh started at $(date) ---"

log_direct_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DIRECT_INSTALL INFO] $1"
}
log_direct_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DIRECT_INSTALL ERROR] $1" >&2
}

# Environment variables from cloud-init
# NIXOS_FLAKE_URI, NIXOS_FLAKE_HOST_ATTR, SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT, etc.

log_direct_info "Starting direct NixOS installation."
log_direct_info "Target Flake: ${NIXOS_FLAKE_URI}#${NIXOS_FLAKE_HOST_ATTR}"
# Do not log SSH keys or secrets.

# --- 0. Install Prerequisites for Installation ---
log_direct_info "Installing prerequisites (parted, gptfdisk, dosfstools if not present)..."
apt-get update -yq || log_direct_error "apt update failed"
apt-get install -yq --no-install-recommends parted gdisk dosfstools util-linux coreutils curl \
    || log_direct_error "Failed to install prerequisites"

# --- 1. Identify Target Disk ---
# This is a critical step and needs to be robust.
# For Hetzner VMs, it's usually /dev/sda or /dev/vda.
TARGET_DISK=""
if [[ -b /dev/sda ]]; then
    TARGET_DISK="/dev/sda"
elif [[ -b /dev/vda ]]; then
    TARGET_DISK="/dev/vda"
else
    log_direct_error "Could not identify target disk (/dev/sda or /dev/vda not found)."
    lsblk
    exit 1
fi
log_direct_info "Target disk identified as: ${TARGET_DISK}"

# --- 2. Partition Disk (Example: GPT with EFI and Root) ---
log_direct_info "Wiping and partitioning disk: ${TARGET_DISK}"
sgdisk --zap-all "${TARGET_DISK}" # Zap existing partition table

# Create EFI System Partition (ESP)
sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI System Partition" "${TARGET_DISK}"
# Create Root Partition (using remaining space)
sgdisk --new=2:0:0    --typecode=2:8300 --change-name=2:"NixOS Root" "${TARGET_DISK}"

# Inform kernel of partition changes
partprobe "${TARGET_DISK}" || (sleep 3 && partprobe "${TARGET_DISK}") || log_direct_error "partprobe failed"
sleep 2 # Give kernel time to recognize new partitions

# Identify partition device names (these can vary, e.g., sda1, sda2 or vda1, vda2)
EFI_PART="${TARGET_DISK}1" # Assuming common suffix
ROOT_PART="${TARGET_DISK}2" # Assuming common suffix

# Double check if these partitions exist
if [[ ! -b "${EFI_PART}" || ! -b "${ROOT_PART}" ]]; then
    log_direct_error "EFI (${EFI_PART}) or Root (${ROOT_PART}) partition not found after partitioning. Check lsblk output."
    lsblk "${TARGET_DISK}"
    exit 1
fi
log_direct_info "Disk partitioned: ESP=${EFI_PART}, Root=${ROOT_PART}"


# --- 3. Format Partitions ---
log_direct_info "Formatting partitions..."
mkfs.fat -F32 -n EFI "${EFI_PART}" || log_direct_error "Failed to format EFI partition"
mkfs.ext4 -F -L nixos "${ROOT_PART}" || log_direct_error "Failed to format root partition"
log_direct_info "Partitions formatted."

# --- 4. Mount Filesystems ---
log_direct_info "Mounting filesystems..."
mount -t ext4 "${ROOT_PART}" /mnt || log_direct_error "Failed to mount root partition to /mnt"
mkdir -p /mnt/boot || log_direct_error "Failed to create /mnt/boot"
mount -t vfat "${EFI_PART}" /mnt/boot || log_direct_error "Failed to mount EFI partition to /mnt/boot"
log_direct_info "Filesystems mounted."

# --- 5. Install Nix (Minimal for nixos-generate-config and nixos-install) ---
log_direct_info "Installing minimal Nix for bootstrap..."
# Using the determinate systems installer for a potentially more reliable minimal install
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm --init none
# Source the Nix profile to make `nix` command available
# shellcheck source=/dev/null
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
log_direct_info "Nix installed. Version: $(nix --version || echo 'Nix not found after install attempt')"

# Enable flakes for nixos-install
mkdir -p /mnt/etc/nix # nixos-install might expect nix.conf here or in its own temp env
echo "experimental-features = nix-command flakes" > /mnt/etc/nix/nix.conf
echo "accept-flake-config = true" >> /mnt/etc/nix/nix.conf


# --- 6. Generate NixOS Configuration ---
log_direct_info "Generating NixOS configuration skeleton..."
# nixos-generate-config will create hardware-configuration.nix and a basic configuration.nix
nixos-generate-config --root /mnt || log_direct_error "nixos-generate-config failed"
log_direct_info "NixOS configuration skeleton generated in /mnt/etc/nixos/"

# --- 7. Customize configuration.nix to use the Flake ---
log_direct_info "Customizing /mnt/etc/nixos/configuration.nix to use Flake: ${NIXOS_FLAKE_URI}#${NIXOS_FLAKE_HOST_ATTR}"
# This is a very basic configuration.nix. Your Flake should provide the bulk of the config.
# Ensure the Flake's nixosConfiguration output is a complete module.
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Import the Flake's NixOS configuration directly
    # This assumes (builtins.getFlake "flake_url").nixosConfigurations."hostAttr" is a valid NixOS module.
    ((builtins.getFlake "${NIXOS_FLAKE_URI}").nixosConfigurations."${NIXOS_FLAKE_HOST_ATTR}")
  ];

  # Ensure SSH is enabled and root can login with the provided key
  services.openssh.enable = lib.mkForce true;
  users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
    "${SSH_AUTHORIZED_KEYS_CONTENT_FOR_SCRIPT}"
  ];

  # Set system state version (important for NixOS)
  system.stateVersion = "${STATE_VERSION_INIT_ENV:-24.05}";

  # Ensure Nix command and flakes are enabled in the final system
  nix.settings.experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
  nix.settings.accept-flake-config = lib.mkDefault true;

  # Bootloader settings are usually in hardware-configuration.nix or the Flake.
  # Example:
  # boot.loader.systemd-boot.enable = lib.mkDefault true;
  # boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
}
EOF
log_direct_info "Custom configuration.nix written."

# --- 8. Install NixOS ---
log_direct_info "Starting NixOS installation (nixos-install)... This will take a while."
# --no-root-passwd: Disables root password, relying on SSH keys.
# The flake URI must be correctly formatted.
# NIX_PATH might need to be set if nixos-install has trouble finding <nixpkgs> for its own operations,
# though --flake should make it self-contained.
# Adding --show-trace for more verbose errors.
if nixos-install --root /mnt --no-root-passwd --flake "${NIXOS_FLAKE_URI}#${NIXOS_FLAKE_HOST_ATTR}" --show-trace; then
    log_direct_info "NixOS installation (nixos-install) completed successfully."
else
    INSTALL_STATUS=$?
    log_direct_error "NixOS installation (nixos-install) FAILED with status ${INSTALL_STATUS}."
    # Try to cat nixos-install log if it exists
    if [[ -f /mnt/var/log/nixos-install.log ]]; then
        log_direct_error "--- nixos-install.log ---"
        cat /mnt/var/log/nixos-install.log || echo "Failed to cat nixos-install.log"
        log_direct_error "--- end of nixos-install.log ---"
    fi
    exit $INSTALL_STATUS
fi

# --- 9. Finish ---
log_direct_info "Unmounting filesystems (optional, system will reboot)..."
# umount -R /mnt || log_direct_warn "Failed to unmount /mnt, proceeding with reboot."

log_direct_info "Direct NixOS installation process complete. System will now reboot."
echo "--- nixos_install_direct.sh finished at $(date) ---"
# Cloud-init or the system itself should handle the reboot.
# Forcing reboot here:
reboot
exit 0