# NixOS on Hetzner: Refactored Deployment

This project provides a streamlined and robust framework for provisioning NixOS servers on Hetzner Cloud. It uses `hcloud` for interacting with the Hetzner API, `cloud-init` for initial server bootstrapping, and a custom NixOS "infection" script (`nixos-everywhere.sh`) or a direct NixOS installation method. The entire workflow is orchestrated by a `justfile`.

## Features

- **Configuration-Driven:** Uses environment variables and dedicated configuration files.
- **Flexible Deployment:** Supports:
    - Converting an existing Debian/Ubuntu server to NixOS using `nixos-everywhere.sh`.
    - (Future) Direct NixOS installation.
- **Secrets Management:** Integrates with `.env` files for sensitive credentials (e.g., `HCLOUD_TOKEN`, Infisical tokens).
- **Orchestration:** Clear and powerful `justfile` for all common operations.
- **Modular Design:** Scripts with well-defined responsibilities.
- **Improved Debuggability:** Enhanced logging throughout the process.

## Prerequisites

- **Just:** A command runner. Install from [https://just.systems/](https://just.systems/).
- **Hetzner Cloud CLI (`hcloud`):** Install and configure according to [Hetzner Cloud documentation](https://github.com/hetznercloud/cli).
- **SSH Client:** For accessing servers.
- **`jq`:** For JSON processing (used by some scripts).
- **`curl`:** For downloading scripts/files.
- **`base64`:** For encoding/decoding scripts for cloud-init.

You can check for most of these dependencies by running:
`just check-deps`

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
│   ├── nixos_convert_on_debian.sh # Wrapper script run by cloud-init for conversion
│   ├── nixos_everywhere.sh      # Core NixOS conversion script
│   └── nixos_install_direct.sh  # (Optional) For direct NixOS install
├── templates/
│   └── cloud_init_base.yaml     # Base template for cloud-init
└── local_test/                  # For local testing of nixos_everywhere.sh
    └── ...
```

## Setup

1.  **Clone the repository.**
2.  **Copy `.env.example` to `.env`:**
    ```bash
    cp .env.example .env
    ```
3.  **Edit `.env`:** Fill in your `HCLOUD_TOKEN` and any other required secrets (e.g., `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`).
4.  **Review Configuration:** Check `config/*.env` files and adjust defaults if necessary.
5.  **Install Dependencies:** Ensure all prerequisites listed above are installed. Run `just check-deps`.

## Usage

All commands are run via `just`. See `just --list` for all available commands.

**Common Commands:**

-   **Check Dependencies:**
    ```bash
    just check-deps
    ```

-   **Provision a new server (using 'convert' method by default):**
    ```bash
    just provision server_name="my-nixos-server" flake_uri="github:yourusername/yourflake#yourNixosHost"
    ```
    * `server_name`: A unique name for your Hetzner server.
    * `flake_uri`: The full Nix Flake URI including the host attribute (e.g., `github:owner/repo#hostname`).
    * You can override other defaults (like server type, location) as arguments to `just`.

-   **Provision using direct NixOS install (if implemented):**
    ```bash
    just provision server_name="my-direct-nixos" flake_uri="github:yourusername/yourflake#yourNixosHost" deploy_method="direct"
    ```

-   **List Servers:**
    ```bash
    just list-servers
    ```

-   **SSH into a Server:**
    ```bash
    just ssh server_name="my-nixos-server"
    ```
    (You might need to wait a few minutes for the server to be provisioned and NixOS installed).

-   **Get Cloud-Init Logs:**
    ```bash
    just logs server_name="my-nixos-server"
    ```

-   **Destroy a Server:**
    ```bash
    just destroy server_name="my-nixos-server"
    ```

### Example Workflow

1.  Set up your `.env` file.
2.  Run `just check-deps`.
3.  Provision a server:
    `just provision server_name="test-01" flake_uri="github:NixOS/nixpkgs#nixosConfigurations.nixosTest"`
4.  Wait for provisioning and NixOS installation (monitor with `just logs server_name="test-01"`).
5.  SSH into the server: `just ssh server_name="test-01"`.
6.  When done, destroy the server: `just destroy server_name="test-01"`.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.