# Debugging Guide for NixOS Infection Process

This guide helps troubleshoot common issues when converting a Debian server to NixOS using the `infect-debian` recipe.

## The NixOS Infection Tool

We've provided a comprehensive tool (`nixos_infect_tool.sh`) that handles both running the infection process and monitoring its progress:

### Using the NixOS Infection Tool

```bash
# Run the infection process with default settings
./nixos_infect_tool.sh run

# Run infection on a specific server
./nixos_infect_tool.sh run --server 192.168.1.100

# Monitor an ongoing infection process
./nixos_infect_tool.sh monitor --server 192.168.1.100 --user root

# Perform a single check instead of continuous monitoring
./nixos_infect_tool.sh check --server 192.168.1.100

# Just show the recent log entries
./nixos_infect_tool.sh log --server 192.168.1.100

# Show help information
./nixos_infect_tool.sh help
```

## Common Issues and Solutions

### 1. SSH Connection Failures

**Symptoms:**
- "Permission denied" errors
- Connection timeouts
- Host key verification failures

**Solutions:**
- Verify the server IP is correct
- Ensure SSH credentials are valid
- Check if the server is reachable (ping, telnet)
- Verify no firewall is blocking port 22
- If host key changed, remove the old key: `ssh-keygen -R <server_ip>`

### 2. Environment Variable Issues

**Symptoms:**
- Script fails with "ERROR: INFECT_XXX environment variable is not set"
- Infection process starts but fails with missing parameters

**Solutions:**
- Use the `run_infect_debian.sh` script which sets all required variables
- If setting variables manually, ensure all required variables are exported:
  ```bash
  export INFECT_SERVER_IP="5.161.197.57"
  export INFECT_SSH_USER="root"
  export INFECT_FLAKE_URI="github:evanlhatch/k3s-nixos-config#hetznerK3sControlTemplate"
  export INFECT_NIXOS_SSH_KEYS="your-ssh-public-key-here"
  export INFECT_NIXOS_CHANNEL="nixos-24.05"
  export INFECT_HOSTNAME_INIT="nixos-server"
  export INFECT_TIMEZONE_INIT="Etc/UTC"
  export INFECT_LOCALE_LANG_INIT_ENV="en_US.UTF-8"
  export INFECT_STATE_VERSION_INIT="24.05"
  ```

### 3. Disk Space Issues

**Symptoms:**
- "No space left on device" errors in logs
- Infection process stalls during package downloads

**Solutions:**
- Check disk space with `df -h`
- Clean up unnecessary files on the target server
- Consider using a larger server or adding more storage

### 4. Network/Download Issues

**Symptoms:**
- "Could not resolve host" errors
- Slow or failing downloads
- Timeouts during package fetching

**Solutions:**
- Verify the server has internet connectivity
- Check DNS resolution on the server
- Try using a different mirror or cache for Nix packages
- If behind a proxy, ensure proxy settings are correctly configured

### 5. Flake URI Issues

**Symptoms:**
- "Unable to download flake" errors
- Git repository access problems

**Solutions:**
- Verify the flake URI is correct
- Ensure the repository is accessible (public or with proper credentials)
- Check that the specified attribute exists in the flake
- For private repositories, set up proper authentication

### 6. SSH Key Issues

**Symptoms:**
- Successful installation but unable to SSH after reboot
- "Permission denied" after conversion

**Solutions:**
- Verify `INFECT_NIXOS_SSH_KEYS` contains valid public keys
- Ensure the keys match your local SSH private keys
- Check that the keys are properly formatted (no line breaks or extra spaces)

### 7. Reboot Issues

**Symptoms:**
- Server doesn't come back online after reboot
- Server boots but not into NixOS

**Solutions:**
- Check if the server is physically accessible or has a remote console
- Verify bootloader configuration was properly installed
- Consider using a provider that offers rescue mode if needed

## Checking Logs

The main log file for the infection process is:
```
/var/log/nixos-everywhere-manual-infect.log
```

You can view it with:
```bash
ssh root@5.161.197.57 "cat /var/log/nixos-everywhere-manual-infect.log"
```

Or monitor it in real-time:
```bash
ssh root@5.161.197.57 "tail -f /var/log/nixos-everywhere-manual-infect.log"
```

## Verifying Successful Installation

A successful NixOS installation should have:

1. The server reboots into NixOS
2. You can SSH into the server using your SSH key
3. The `nixos-version` command works and shows the correct version
4. The system is configured according to your flake

Check with:
```bash
ssh root@5.161.197.57 "nixos-version"
ssh root@5.161.197.57 "systemctl status"
```

## Recovery Options

If the infection process fails and leaves the server in an unusable state:

1. If using Hetzner, use the Hetzner Cloud Console to access the server's rescue system
2. For other providers, use their equivalent rescue or recovery options
3. In rescue mode, you can either:
   - Attempt to fix the NixOS installation
   - Restore the server to Debian using the provider's reinstall options

## Getting More Help

If you're still experiencing issues:

1. Gather the complete logs from the server
2. Note the exact error messages
3. Document the steps you've taken
4. Open an issue on the nixos-everywhere GitHub repository with this information