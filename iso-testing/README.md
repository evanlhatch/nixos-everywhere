# nixos-everywhere VM Testing Environment

This directory contains tools for safely testing the nixos-everywhere script in a VM environment without affecting your host system.

## Prerequisites

You'll need the following dependencies:

```bash
nix-shell -p qemu xorriso curl python3
```

## Usage

All commands are managed through the justfile. Use `just --list` to see available commands.

### Basic Workflow

1. **Setup the environment**:
   ```bash
   just setup
   ```

2. **Create cloud-init configuration**:
   ```bash
   just create-cloud-init
   ```

3. **Prepare the nixos-everywhere test**:
   ```bash
   just prepare-test
   ```

4. **Start the VM**:
   ```bash
   just start-vm
   ```

5. **In another terminal, run the test**:
   ```bash
   just run-test
   ```
   
   Or to reset the VM environment first (recommended for repeated tests):
   ```bash
   just run-test-reset
   ```

### Quick Start

To set up everything at once:

```bash
just full-test
```

This will prepare everything and give you instructions for the final steps.

### Complete Test Cycle

To run a complete test cycle (reset, prepare, run) in one command:

```bash
just test-cycle
```

### Debugging Tools

The testing environment includes several debugging tools:

1. **View logs**:
   ```bash
   just view-log           # View main output log
   just view-debug-log     # View detailed debug log
   just view-nixos-config  # View generated NixOS configuration
   ```

2. **Check VM status**:
   ```bash
   just vm-status          # Check VM status, Nix installation, disk usage, etc.
   ```

3. **Collect debug information**:
   ```bash
   just debug-vm           # Collect comprehensive debug information
   ```

4. **SSH into the VM**:
   ```bash
   just ssh-vm             # SSH into the VM for manual inspection
   ```

### Resetting Without Rebuilding

If you encounter issues with residual installation artifacts, you can reset the VM without rebuilding it:

```bash
just reset-vm
```

This will clean up backup files, stop nix-daemon, and remove any previous nixos-everywhere files.

### Cleaning Up

To remove all generated files:

```bash
just clean
```

## Enhanced Debugging Features

The testing environment now includes several enhancements for better debugging:

1. **Wrapper Script**: Instead of modifying nixos-everywhere.sh directly, we use a wrapper script that adds debugging capabilities while preserving the original script.

2. **Comprehensive Logging**: All operations are logged to multiple files for easier troubleshooting:
   - Main output log: Shows the overall execution
   - Debug log: Contains detailed debugging information
   - System information: Collected before and after execution

3. **Error Recovery**: The wrapper script includes error recovery mechanisms to handle common issues:
   - Fixes the `df` command issue that causes "options -T and --output are mutually exclusive" errors
   - Creates basic NixOS configuration files if the script fails to generate them
   - Collects system information when errors occur

4. **Centralized Directory Structure**:
   - All logs are stored in the `logs` directory
   - Debug information is stored in the `logs/debug` directory
   - NixOS configuration is copied to `logs/nixos-config` for inspection

## Safety Features

- All operations are contained within a VM
- Multiple safety checks prevent accidental execution on the host
- Clear separation of steps requiring manual intervention
- All files are stored in this directory

## How It Works

1. Creates a Debian cloud VM with cloud-init pre-installed
2. Sets up SSH access to the VM
3. Executes nixos-everywhere through a wrapper script that adds debugging capabilities
4. Collects logs and debug information for analysis
5. Provides tools for inspecting the results

## Troubleshooting

- If the VM fails to start, ensure KVM is available on your system
- If SSH connection fails, ensure the VM has fully booted
- Use `just vm-status` to check the VM status
- Use `just debug-vm` to collect comprehensive debug information
- If you encounter errors, try `just test-cycle` to run a complete test cycle