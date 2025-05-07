#!/usr/bin/env bash
#
# nixos-everywhere.sh (formerly nixos-flake-infect.sh)
#
# Version: 1.2.0
#
# This script "infects" a running Linux system (typically a cloud server's
# initial OS like Debian/Ubuntu) and replaces it with NixOS, configured
# by a user-provided Nix Flake.
#
# WARNING: THIS SCRIPT WILL OVERWRITE THE EXISTING OS CONFIGURATION AND BOOTLOADER.
# IT IS DESIGNED TO INSTALL NIXOS ON THE EXISTING ROOT FILESYSTEM.
# IT DOES NOT REPARTITION THE DISK (NO DISKO/KEXEC).
# USE WITH EXTREME CAUTION AND TEST THOROUGHLY.
#
# --- HOW TO USE WITH CLOUD-INIT ---
# 1. Host this script at a reachable URL (e.g., your GitHub raw link) OR
#    ensure it's correctly embedded by your Justfile if using the local option.
# 2. Cloud-init should set these MANDATORY environment variables:
#    export FLAKE_URI="github:yourusername/yourflake#yourMachineName"
#    export SSH_AUTHORIZED_KEYS="ssh-rsa AAA... key1\nssh-ed25519 AAA... key2"
# 3. Cloud-init can optionally set:
#    NIXOS_CHANNEL, HOSTNAME_INIT, TIMEZONE_INIT, LOCALE_LANG_INIT, STATE_VERSION_INIT, LOG_FILE_PATH
#
# --- SCRIPT CORE ---

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# --- CONFIGURABLE VARIABLES (Expected to be set via Environment/Cloud-Init) ---
FLAKE_URI_INPUT="${FLAKE_URI:-}"
SSH_AUTHORIZED_KEYS_INPUT="${SSH_AUTHORIZED_KEYS:-}"
NIXOS_CHANNEL_ENV="${NIXOS_CHANNEL:-nixos-24.11}"
HOSTNAME_INIT_ENV="${HOSTNAME_INIT:-$(hostname -s 2>/dev/null || echo "nixos-node")}"
TIMEZONE_INIT_ENV="${TIMEZONE_INIT:-Etc/UTC}"
LOCALE_LANG_INIT_ENV="${LOCALE_LANG_INIT:-en_US.UTF-8}"
STATE_VERSION_INIT_ENV="${STATE_VERSION_INIT:-24.11}"
NIX_INSTALL_SCRIPT_URL_ENV="${NIX_INSTALL_SCRIPT_URL:-https://nixos.org/nix/install}"
LOG_FILE_ENV="${LOG_FILE_PATH:-/var/log/nixos-everywhere.log}"
# --- END CONFIGURABLE VARIABLES ---

mkdir -p "$(dirname "$LOG_FILE_ENV")"
exec > >(tee -a "$LOG_FILE_ENV") 2>&1

log() {
    local level="$1"; local message="$2";
    echo "$(date --iso-8601=seconds) - ${level^^} - ${message}";
}
error_handler() {
    local exit_status="$1"; local line_number="$2";
    log "FATAL" "Error on line ${line_number} of $(basename "$0"): CMD exited with status ${exit_status}.";
    log "FATAL" "Log file: ${LOG_FILE_ENV}"; exit "${exit_status}";
}
trap 'error_handler $? $LINENO' ERR INT TERM

ensure_command() {
    local cmd="$1"; local pkg="${2:-$cmd}";
    if ! command -v "$cmd" &>/dev/null; then
        log "INFO" "$cmd not found. Installing $pkg...";
        if command -v apt-get &>/dev/null; then
            export DEBIAN_FRONTEND=noninteractive; apt-get update -yq || log "WARN" "apt update failed: $?";
            if ! apt-get install -yq --no-install-recommends "$pkg"; then log "ERROR" "apt install $pkg failed."; return 1; fi
        elif command -v dnf &>/dev/null; then
            if ! dnf install -y "$pkg"; then log "ERROR" "dnf install $pkg failed."; return 1; fi
        elif command -v yum &>/dev/null; then
            if ! yum install -y "$pkg"; then log "ERROR" "yum install $pkg failed."; return 1; fi
        elif command -v zypper &>/dev/null; then
            if ! zypper --non-interactive install "$pkg"; then log "ERROR" "zypper install $pkg failed."; return 1; fi
        else log "ERROR" "Unsupported package manager for $pkg."; return 1; fi
        log "INFO" "$pkg installed."; else log "INFO" "$cmd found."; fi
}

parse_flake_uri_to_env() {
    local uri="$1"; local flake_url_part; local flake_attr_name;
    if [[ "$uri" =~ ^([^#]+)\#([a-zA-Z0-9_.-]+)$ ]]; then
        flake_url_part="${BASH_REMATCH[1]}"; flake_attr_name="${BASH_REMATCH[2]}";
    elif [[ -n "$uri" && ! "$uri" == *"#"* ]]; then
        flake_url_part="$uri"; flake_attr_name="defaultNixosConfig"; # Default if no #attr
        log "WARN" "No Flake attribute in URI '$uri'. Assuming '${flake_attr_name}'. Ensure Flake provides it.";
    else log "FATAL" "Invalid FLAKE_URI format: '$uri'"; fi
    if [[ -z "$flake_url_part" ]]; then log "FATAL" "Empty Flake URL from: $uri"; fi
    if [[ -z "$flake_attr_name" ]]; then log "FATAL" "Empty Flake attribute from: $uri"; fi
    export ENV_FLAKE_URL="$flake_url_part"; export ENV_FLAKE_ATTR_NAME="$flake_attr_name";
    log "INFO" "Parsed Flake URL for Nix: ${ENV_FLAKE_URL}";
    log "INFO" "Parsed Flake Attribute for Nix: ${ENV_FLAKE_ATTR_NAME}";
}

main() {
    log "INFO" "Starting nixos-everywhere.sh v1.2.0";
    if [[ -z "$FLAKE_URI_INPUT" ]]; then log "FATAL" "FLAKE_URI env var not set."; fi
    if [[ -z "$SSH_AUTHORIZED_KEYS_INPUT" ]]; then log "FATAL" "SSH_AUTHORIZED_KEYS env var not set."; fi
    export SSH_AUTHORIZED_KEYS_FOR_NIX="${SSH_AUTHORIZED_KEYS_INPUT}";
    if [[ "$(id -u)" -ne 0 ]]; then log "FATAL" "Must run as root."; fi
    if [[ -f /etc/NIXOS || -f /run/current-system/nixos-version ]]; then log "INFO" "Already NixOS. Exiting."; exit 0; fi

    log "INFO" "--- Using Configuration ---";
    log "INFO" "FLAKE_URI: ${FLAKE_URI_INPUT}";
    log "INFO" "NIXOS_CHANNEL (bootstrap): ${NIXOS_CHANNEL_ENV}";
    log "INFO" "Effective HOSTNAME_INIT: ${HOSTNAME_INIT_ENV}";
    log "INFO" "SSH Keys: Provided ($(echo "${SSH_AUTHORIZED_KEYS_INPUT}" | wc -l | xargs) lines)";

    parse_flake_uri_to_env "$FLAKE_URI_INPUT";

    log "INFO" "--- Installing Prerequisites ---";
    ensure_command "curl"; ensure_command "git"; ensure_command "sudo";
    ensure_command "ip" "iproute2"; ensure_command "lsblk" "util-linux";
    ensure_command "df" "coreutils"; ensure_command "awk" "gawk";
    ensure_command "sed"; ensure_command "grep";
    ensure_command "findmnt" "util-linux"; ensure_command "mount" "util-linux";
    log "INFO" "Prerequisites check/install complete.";

    log "INFO" "--- Installing Nix ---";
    if ! command -v nix &>/dev/null; then
        log "INFO" "Nix not found. Installing Nix from ${NIX_INSTALL_SCRIPT_URL_ENV}...";
        NIX_INSTALLER_PATH="/tmp/nix_install.sh"
        curl -sSL -f -o "$NIX_INSTALLER_PATH" "$NIX_INSTALL_SCRIPT_URL_ENV" || log "FATAL" "Failed to download Nix installer."
        sh "$NIX_INSTALLER_PATH" --daemon --no-channel-add --no-modify-profile; rm -f "$NIX_INSTALLER_PATH";
        log "INFO" "Nix installation script finished.";
    fi
    if [[ -f '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'; log "INFO" "Sourced Nix daemon profile.";
    else log "WARN" "Nix daemon profile not found to source."; fi

    local nix_conf_file="/etc/nix/nix.conf"; mkdir -p "$(dirname "$nix_conf_file")";
    if ! grep -q "experimental-features.*=.*nix-command.*flakes" "$nix_conf_file" 2>/dev/null; then
        log "INFO" "Enabling Nix Flakes support in $nix_conf_file...";
        echo "experimental-features = nix-command flakes" >> "$nix_conf_file";
        echo "accept-flake-config = true" >> "$nix_conf_file";
        if command -v systemctl &>/dev/null && systemctl is-active --quiet nix-daemon.service; then
            log "INFO" "Restarting nix-daemon service..."; systemctl restart nix-daemon.service || log "WARN" "Failed to restart nix-daemon."; sleep 3;
        fi
    else log "INFO" "Nix Flake support already configured."; fi
    if ! command -v nix &>/dev/null; then log "FATAL" "Nix command not available."; fi
    log "INFO" "Nix version: $(nix --version || echo 'Nix command failed')";

    log "INFO" "--- Preparing /etc/nixos directory ---";
    mkdir -p /etc/nixos; chown root:root /etc/nixos; chmod 0755 /etc/nixos;

    log "INFO" "--- Generating hardware-configuration.nix ---";
    ROOT_FS_DEVICE=$(df --output=source / | awk 'NR==2'); ROOT_FS_TYPE=$(df --output=fstype -T / | awk 'NR==2');
    EFI_SYSTEM_PARTITION=""; GRUB_DEVICE_AUTO="";
    if [[ -d /sys/firmware/efi/efivars ]]; then log "INFO" "EFI system detected.";
        ESP_MOUNT_POINT=$(findmnt -uno TARGET -n /boot/efi || findmnt -uno TARGET -n /boot || echo "");
        if [[ -n "$ESP_MOUNT_POINT" ]]; then EFI_SYSTEM_PARTITION=$(df "$ESP_MOUNT_POINT" --output=source | awk 'NR==2'); log "INFO" "ESP at $ESP_MOUNT_POINT: ${EFI_SYSTEM_PARTITION}";
        else log "WARN" "ESP not reliably detected via /boot/efi or /boot."; fi
    else log "INFO" "BIOS system detected.";
        ROOT_DISK_NAME_RAW=$(lsblk -no pkname "$ROOT_FS_DEVICE" 2>/dev/null || echo "");
        if [[ -n "$ROOT_DISK_NAME_RAW" ]]; then GRUB_DEVICE_AUTO="/dev/$ROOT_DISK_NAME_RAW";
        else GRUB_DEVICE_AUTO="/dev/$(lsblk -ndo KNAME,TYPE | awk '$2=="disk" {print $1; exit}' || echo "vda")"; fi
        log "INFO" "Tentative GRUB device (BIOS): ${GRUB_DEVICE_AUTO}";
    fi
    cat > /etc/nixos/hardware-configuration.nix << EOFHWCONF
{ config, lib, pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_blk" "xhci_pci" "ahci" "sd_mod" "sr_mod" "nvme" ];
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];
  fileSystems."/" = { device = "${ROOT_FS_DEVICE}"; fsType = "${ROOT_FS_TYPE}"; };
$(if [[ -n "$EFI_SYSTEM_PARTITION" ]]; then
  printf '  fileSystems."/boot" = {\n    device = "%s";\n    fsType = "vfat";\n  };\n' "$EFI_SYSTEM_PARTITION"
  printf '  boot.loader.systemd-boot.enable = lib.mkForce true;\n  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;\n  boot.loader.grub.enable = lib.mkForce false;\n'
else
  printf '  boot.loader.grub.enable = lib.mkForce true;\n  boot.loader.grub.device = "%s";\n  boot.loader.systemd-boot.enable = lib.mkForce false;\n' "$GRUB_DEVICE_AUTO"
fi)
}
EOFHWCONF
    log "INFO" "Generated /etc/nixos/hardware-configuration.nix";

    log "INFO" "--- Generating networking.nix (Hetzner-like static IP attempt) ---";
    PRIMARY_INTERFACE_NAME=$(ip -o route get to 8.8.8.8 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p');
    if [[ -n "$PRIMARY_INTERFACE_NAME" ]]; then
        IPV4_ADDR_CIDR=$(ip -o -4 addr show dev "$PRIMARY_INTERFACE_NAME" 2>/dev/null | awk '{print $4}' | head -n1);
        IPV4_GATEWAY=$(ip -o -4 route show default dev "$PRIMARY_INTERFACE_NAME" 2>/dev/null | awk '{print $3}' | head -n1);
        DNS_SERVERS_DETECTED=(); while IFS= read -r line; do DNS_SERVERS_DETECTED+=("\"$line\""); done < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | grep -Ev '^(127\.|::1)');
        DNS_SERVERS_STRING=$(IFS=" "; echo "${DNS_SERVERS_DETECTED[*]}"); if [[ -z "$DNS_SERVERS_STRING" ]]; then DNS_SERVERS_STRING='"1.1.1.1" "8.8.8.8"'; fi
        if [[ -n "$IPV4_ADDR_CIDR" && -n "$IPV4_GATEWAY" ]]; then
            cat > /etc/nixos/networking.nix << EOFNETWORK
{ lib, ... }: {
  networking.useDHCP = lib.mkForce false;
  networking.interfaces."${PRIMARY_INTERFACE_NAME}" = { useDHCP = false; ipv4.addresses = [{ address = "${IPV4_ADDR_CIDR%/*}"; prefixLength = ${IPV4_ADDR_CIDR#*/}; }]; };
  networking.defaultGateway = "${IPV4_GATEWAY}"; networking.nameservers = [ ${DNS_SERVERS_STRING} ];
}
EOFNETWORK
            log "INFO" "Generated /etc/nixos/networking.nix for ${PRIMARY_INTERFACE_NAME}.";
        else log "WARN" "Incomplete IPv4 params for static config. networking.nix not generated."; fi
    else log "WARN" "Primary network interface not detected. networking.nix not generated."; fi

    log "INFO" "--- Generating bridging /etc/nixos/configuration.nix ---";
    export HOSTNAME_FOR_NIX="${HOSTNAME_INIT_ENV}"; export TIMEZONE_FOR_NIX="${TIMEZONE_INIT_ENV}";
    export LOCALE_LANG_FOR_NIX="${LOCALE_LANG_INIT_ENV}"; export STATE_VERSION_FOR_NIX="${STATE_VERSION_INIT_ENV}";
    # ENV_FLAKE_URL, ENV_FLAKE_ATTR_NAME, SSH_AUTHORIZED_KEYS_FOR_NIX are already exported by parent functions

    cat > /etc/nixos/configuration.nix << EOFBRIDGE
{ config, pkgs, lib, ... }:
let
  flakeUrl = builtins.getEnv "ENV_FLAKE_URL";
  flakeAttrName = builtins.getEnv "ENV_FLAKE_ATTR_NAME";
  userFlake = builtins.getFlake flakeUrl; # This will fetch the Flake
  userNixosConfiguration =
    if builtins.hasAttr flakeAttrName userFlake.nixosConfigurations then
      userFlake.nixosConfigurations."\${flakeAttrName}"
    else
      abort "Flake '\${flakeUrl}' does not have 'nixosConfigurations.\${flakeAttrName}'. Check FLAKE_URI.";
  getEnvOrDefault = name: default: let val = builtins.getEnv name; in if val == null || val == "" then default else val;
  sshKeysFromEnv = builtins.getEnv "SSH_AUTHORIZED_KEYS_FOR_NIX";
  parsedSshKeys = lib.filter (key: key != "") (lib.splitString "\\n" sshKeysFromEnv);
in {
  imports = [ ./hardware-configuration.nix ]
    ++ (lib.optional (builtins.pathExists ./networking.nix) ./networking.nix)
    ++ [ userNixosConfiguration ];
  services.openssh.enable = lib.mkDefault true;
  users.users.root.openssh.authorizedKeys.keys = lib.mkForce parsedSshKeys;
  networking.hostName = lib.mkDefault (getEnvOrDefault "HOSTNAME_FOR_NIX" "nixos");
  time.timeZone = lib.mkOptionDefault (getEnvOrDefault "TIMEZONE_FOR_NIX" null);
  i18n.defaultLocale = lib.mkOptionDefault (getEnvOrDefault "LOCALE_LANG_FOR_NIX" "en_US.UTF-8");
  i18n.supportedLocales = lib.mkOptionDefault [((getEnvOrDefault "LOCALE_LANG_FOR_NIX" "en_US.UTF-8") + "/UTF-8")];
  system.stateVersion = lib.mkDefault (getEnvOrDefault "STATE_VERSION_FOR_NIX" "${STATE_VERSION_INIT_ENV}");
  console.enable = lib.mkDefault true;
}
EOFBRIDGE
    log "INFO" "Bridging /etc/nixos/configuration.nix generated.";

    log "INFO" "--- Pre-flight evaluation of NixOS configuration ---";
    local eval_check_log="/tmp/nixos_eval_check.log";
    if nix eval --impure --raw --expr "(import <nixpkgs/nixos> { configuration = /etc/nixos/configuration.nix; }).system.outPath" &> "$eval_check_log"; then
        log "INFO" "NixOS configuration evaluation check successful.";
    else
        log "ERROR" "NixOS configuration evaluation check FAILED. Details in $eval_check_log and main log ($LOG_FILE_ENV).";
        cat "$eval_check_log"; exit 1;
    fi

    log "INFO" "--- Installing NixOS System ---";
    log "INFO" "Setting up Nix channel: ${NIXOS_CHANNEL_ENV}";
    nix-channel --remove nixos || true;
    nix-channel --add "https://nixos.org/channels/${NIXOS_CHANNEL_ENV}" nixos;
    if ! nix-channel --update; then log "FATAL" "nix-channel --update failed."; fi;
    log "INFO" "Nix channels updated.";

    log "INFO" "Building and installing NixOS system profile (this may take a while)...";
    local nixos_channel_path;
    nixos_channel_path=$(nix-build "<${NIXOS_CHANNEL_ENV}>" -A path --no-out-link);
    if [[ -z "$nixos_channel_path" ]]; then log "FATAL" "Could not get path for NixOS channel ${NIXOS_CHANNEL_ENV}."; fi
    log "INFO" "Using NixOS channel path for bootstrap: $nixos_channel_path";

    if ! nix-env --set \
        -I nixos="${nixos_channel_path}/nixos" \
        -f '<nixos>' \
        -p /nix/var/nix/profiles/system \
        -A system; then
        log "FATAL" "nix-env --set -A system failed. NixOS build or system profile creation failed.";
    fi
    log "INFO" "NixOS system profile created.";

    rm -f /nix/var/nix/profiles/default*;
    /nix/var/nix/profiles/system/sw/bin/nix-collect-garbage -d || log "WARN" "nix-collect-garbage -d failed.";

    log "INFO" "Configuring bootloader and switching to new NixOS configuration...";
    if ! NIX_PATH="nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/system/etc/nixos" \
         /nix/var/nix/profiles/system/bin/switch-to-configuration boot; then
        log "FATAL" "switch-to-configuration boot failed.";
    fi
    log "INFO" "Bootloader configured. NixOS installation effectively complete.";

    touch /etc/NIXOS_INSTALLED_VIA_FLAKE_INFECT; log "INFO" "Syncing filesystems...";
    sync; sync; sync;

    log "INFO" "NixOS Flake infection process complete. System will now reboot into NixOS.";
    log "INFO" "SSH as root with keys from SSH_AUTHORIZED_KEYS. Check ${LOG_FILE_ENV} on new system if issues.";

    if [[ -t 0 && -t 1 && "${FORCE_REBOOT:-no}" != "yes" ]]; then
        read -r -p "Reboot now? (y/N): " confirm_reboot
        if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then log "INFO" "Rebooting now..."; reboot;
        else log "INFO" "Reboot skipped. Please reboot manually."; fi
    else log "INFO" "Rebooting system automatically..."; reboot; fi
}

# --- Run Main Function ---
main "$@"

exit 0
