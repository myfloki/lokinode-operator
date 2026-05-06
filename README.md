# Lokinode Operator

Lokinode Operator provides `flnd` (Flokicoin Lightning Network Daemon) and `lokihub` services in a single package for easy deployment.

## Prerequisites

- **Docker**: Installed and running.
- **Curl**: Required for the setup script to install `just`.
- **Operating System**: Linux is recommended.

## 🚀 Onboarding Steps (Full User Experience)

Follow these steps to set up your operator from scratch:

### 1. Initial Setup
Run the `setup.sh` script. This script will:
- Check for and install the `just` command runner if it's missing.
- Create necessary data directories (`data/flnd`, `data/lokihub`).
- Generate `.env` and `data/flnd/flnd.conf` from sample files.
- Start a temporary container to initialize your wallet.

```bash
./setup.sh
```

### 2. Wallet Creation (Interactive)
During the setup script, you will be prompted by `flncli` to:
1.  **Enter a wallet password**: Choose a strong password. This password will be used to unlock the wallet.
2.  **Generate a seed (mnemonic)**: You will be given 24 words. **Write them down and store them safely!** This is the only way to recover your funds.
3.  **Confirm the seed**: You may be asked to re-enter specific words from your seed.

Once the wallet is created, the temporary container will be removed automatically.

### 3. Configuration (Optional)
Before starting the services, you can customize your installation:
- **`.env`**: Modify ports, node aliases, or the docker image version.
- **`data/flnd/flnd.conf`**: Adjust lightning network settings (e.g., node alias, color, etc.).

> [!CAUTION]
> **IMPORTANT**: Review your configuration files (e.g., .env, flnd.conf, lokid.conf) and replace any placeholder credentials (like YOUR_RPC_PASSWORD) with secure, custom passwords before starting the services.

### 4. Start the Operator
Now that everything is configured and your wallet is ready, start the services:

```bash
just up
```

## 🛠️ Service Management

The operator uses `just` for common tasks:

| Command         | Description                                     |
| --------------- | ----------------------------------------------- |
| `just setup`    | Re-run the onboarding/setup script.             |
| `just up`       | Start all services in the background.           |
| `just down`     | Stop and remove all service containers.         |
| `just restart`  | Restart the services.                           |
| `just logs`     | Follow logs for all services.                   |
| `just logs-flnd`| Follow logs specifically for `flnd`.            |
| `just status`   | Check the status of the containers.             |
| `just cli`      | Open a bash shell inside the `flnd` container.  |
| `just flncli`   | Run `flncli` commands (e.g., `just flncli getinfo`). |
| `just backup-channels` | Create a timestamped backup of your channels. |
| `just restore-channels <file>` | Restore channels from a backup file. |

## 💾 Backup & Recovery

### Static Channel Backups (SCB)
The `backup-channels` command creates a copy of your `channel.backup` file. This is critical for recovering funds if your node's data is lost or corrupted.

> [!IMPORTANT]
> **How Recovery Works**: Static Channel Backups do **not** restore active channels. Instead, they provide enough information for your node to ask its peers to force-close the channels and send the funds back to your on-chain wallet. Funds will typically be subject to a "lock-time" (CSV delay) before they become spendable in your wallet.

### 🔄 Restore Procedure
1. Ensure your node is running and the wallet is unlocked (`just up && just unlock`).
2. Run the restore command: `just restore-channels backups/channel.backup.YYYYMMDD_HHMMSS`.
3. Monitor the logs: `just logs-flnd` to see the recovery progress.

## 🔍 Troubleshooting

- **Logs**: If a service fails to start, check the logs first: `just logs`.
- **Wallet Locking**: On first startup, you may need to unlock your wallet if you didn't enable auto-unlock. Use: `docker exec -it flnd flncli unlock`.
- **Data Persistence**: All configuration and blockchain data are stored in the `./data` directory. Do not delete this directory unless you want to reset everything.

## 📦 Services Included

- **flnd**: The Lightning Network Daemon for Flokicoin.
- **lokihub**: A powerful web interface for managing your Flokicoin node and services.
