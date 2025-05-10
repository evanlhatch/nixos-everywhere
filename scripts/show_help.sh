#!/usr/bin/env bash
# scripts/show_help.sh
# Displays help information for the NixOS on Hetzner project.

cat << EOF
NixOS on Hetzner: Refactored Deployment
=======================================

This project provides a streamlined framework for provisioning NixOS servers on Hetzner Cloud.

Common Commands:
---------------

  just check-deps
    Check for required dependencies.

  just provision server_name="my-nixos-server" flake_uri="github:yourusername/yourflake#yourNixosHost"
    Provision a new server with the specified name and Flake URI.
    Optional parameters:
      deploy_method="convert"    # Method to use (convert or direct)
      server_type="cpx21"        # Hetzner server type
      base_image="debian-12"     # Base image for conversion
      location="ash"             # Server location (default: Ashburn, VA)
      ssh_key_name="your-key"    # SSH key name in Hetzner
      network="k3s-net"          # Private network to join
      volume="volume-ash-1"      # Volume to attach
      firewall="k3s-fw"          # Firewall to apply
      placement_group="k3s-pg"   # Placement group to use
      labels="key=value;..."     # Labels to apply (semicolon-separated)
      enable_ipv4="false"        # Set to false for IPv6 only (default)

  just list-servers
    List all servers in your Hetzner Cloud project.

  just ssh server_name="my-nixos-server" [ssh_user="root"]
    SSH into a provisioned server.

  just logs server_name="my-nixos-server" [ssh_user="root"]
    Fetch cloud-init and conversion logs from a server.

  just destroy server_name="my-nixos-server"
    Destroy a server.

Important Notes:
--------------
- The nixos-everywhere.sh script must be hosted at a publicly accessible URL.
- The URL is configured in config/nixos.env as NIXOS_EVERYWHERE_SCRIPT_URL.
- Keep the remote repository up to date with any changes to the script.

For more information, see the README.md file.
EOF