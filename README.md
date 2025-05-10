# NixOS on Hetzner: Refactored Deployment

This project provides a streamlined and robust framework for provisioning NixOS servers on Hetzner Cloud. It uses `hcloud` for interacting with the Hetzner API, `cloud-init` for initial server bootstrapping, and a custom NixOS "infection" script (`nixos-everywhere.sh`) that transforms a standard Linux distribution into NixOS. The entire workflow is orchestrated by a `justfile`.

## Features

- **Configuration-Driven:** Uses environment variables and dedicated configuration files.
- **Flexible Deployment:** Supports converting an existing Debian/Ubuntu server to NixOS using `nixos-everywhere.sh`.
- **Secrets Management:** Integrates with `.env` files for sensitive credentials (e.g., `HCLOUD_TOKEN`, Infisical tokens).
- **Orchestration:** Clear and powerful `justfile` for all common operations.
- **Modular Design:** Scripts with well-defined responsibilities.
- **Improved Debuggability:** Enhanced logging throughout the process.
- **Hetzner-Specific Features:** Support for private networks, volumes, firewalls, placement groups, and IPv6-only configuration.

## Prerequisites

- **Just:** A command runner. Install from [https://just.systems/](https://just.systems/).
- **Hetzner Cloud CLI (`hcloud`):** Install and configure according to [Hetzner Cloud documentation](https://github.com/hetznercloud/cli).
- **SSH Client:** For accessing servers.
- **`jq`:** For JSON processing (used by some scripts).
- **`curl`:** For downloading scripts/files.

You can check for most of these dependencies by running:
```bash
just check-deps
```

## Project Structure

```
.
├── justfile                     # Main orchestrator
├── README.md                    # This file
├── .env.example                 # Template for environment variables (secrets)
├── config/
│   ├── common.env               # Common configuration (default user, regions)
│   ├── hetzner.env              # Hetzner specific defaults (server type, image for conversion)
│   └── nixos.env                # NixOS specific defaults (default flake URI, channel)
├── scripts/
│   ├── lib_core.sh              # Common shell functions
│   ├── deps_check.sh            # Checks for local dependencies
│   ├── hetzner_provision.sh     # Creates Hetzner server
│   ├── cloud_init_generator.sh  # Dynamically creates cloud-init YAML
│   ├── nixos_everywhere.sh      # Core NixOS conversion script
│   ├── nixos_install_direct.sh  # (Optional) For direct NixOS install
│   └── show_help.sh             # Displays help information
└── templates/
    └── cloud_init_base.yaml     # Base template for cloud-init
```

## Important Note on Remote Repository

This project relies on the `nixos-everywhere.sh` script being accessible via a URL. The cloud-init configuration downloads and executes this script directly from the specified URL. Therefore, it's crucial to:

1. Host the `nixos-everywhere.sh` script in a publicly accessible repository
2. Keep the remote repository up to date with any changes to the script
3. Ensure the URL specified in your configuration points to the correct version of the script

If you make changes to the `nixos-everywhere.sh` script locally, make sure to push those changes to the remote repository before provisioning new servers.

## Setup

1. **Clone the repository.**
2. **Copy `.env.example` to `.env`:**
   ```bash
   cp .env.example .env
   ```
3. **Edit `.env`:** Fill in your `HCLOUD_TOKEN` and any other required secrets (e.g., `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`).
4. **Review Configuration:** Check `config/*.env` files and adjust defaults if necessary.
5. **Install Dependencies:** Ensure all prerequisites listed above are installed. Run `just check-deps`.
6. **Configure Script URL:** Ensure the `NIXOS_EVERYWHERE_SCRIPT_URL` in `config/nixos.env` points to a valid, publicly accessible URL for the `nixos-everywhere.sh` script.

## Usage

All commands are run via `just`. See `just --list` for all available commands.

**Common Commands:**

- **Check Dependencies:**
  ```bash
  just check-deps
  ```

- **Provision a new server:**
  ```bash
  just provision server_name="my-nixos-server" flake_uri="github:yourusername/yourflake#yourNixosHost"
  ```
  * `server_name`: A unique name for your Hetzner server.
  * `flake_uri`: The full Nix Flake URI including the host attribute (e.g., `github:owner/repo#hostname`).
  * You can override other defaults (like server type, location) as arguments to `just`.

- **Advanced Provisioning with Custom Settings:**
  ```bash
  just provision server_name="k3s-control-01" \
    flake_uri="github:yourusername/yourflake#yourNixosHost" \
    server_type="cpx21" \
    location="ash" \
    network="k3s-net" \
    volume="volume-ash-1" \
    firewall="k3s-fw" \
    placement_group="k3s-placement-group" \
    enable_ipv4="false"
  ```

- **List Servers:**
  ```bash
  just list-servers
  ```

- **SSH into a Server:**
  ```bash
  just ssh server_name="my-nixos-server"
  ```
  (You might need to wait a few minutes for the server to be provisioned and NixOS installed).

- **Get Cloud-Init Logs:**
  ```bash
  just logs server_name="my-nixos-server"
  ```

- **Destroy a Server:**
  ```bash
  just destroy server_name="my-nixos-server"
  ```

### Example Workflow

1. Set up your `.env` file.
2. Run `just check-deps`.
3. Provision a server:
   `just provision server_name="k3s-control-01" flake_uri="github:your/flake#host"`
4. Wait for provisioning and NixOS installation (monitor with `just logs server_name="k3s-control-01"`).
5. SSH into the server: `just ssh server_name="k3s-control-01"`.
6. When done, destroy the server: `just destroy server_name="k3s-control-01"`.

## How It Works

1. The `just provision` command calls `hetzner_provision.sh` with the specified parameters.
2. `hetzner_provision.sh` generates a cloud-init configuration using `cloud_init_generator.sh`.
3. The cloud-init configuration downloads and executes the `nixos-everywhere.sh` script from the specified URL.
4. The `nixos-everywhere.sh` script "infects" the base OS (Debian/Ubuntu) and transforms it into NixOS.
5. The NixOS system is configured using the specified Nix Flake.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.