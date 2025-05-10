#!/usr/bin/env bash
# scripts/show_help.sh
# Shows help information for the NixOS on Hetzner deployment system.

echo "NixOS on Hetzner: Refactored Deployment"
echo ""
echo "Available commands:"
just --list
echo ""
echo "Common Workflows:"
echo "  1. Ensure .env is configured with HCLOUD_TOKEN and HETZNER_SSH_KEY_NAME_OR_FINGERPRINT."
echo "  2. Check dependencies: just check-deps"
echo "  3. Provision a server: just provision server_name=\"my-test\" flake_uri=\"github:your/flake#host\""
echo "  4. Monitor logs: just logs server_name=\"my-test\""
echo "  5. SSH into server: just ssh server_name=\"my-test\""
echo "  6. Destroy server: just destroy server_name=\"my-test\""