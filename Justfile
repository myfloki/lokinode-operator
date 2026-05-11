set shell := ["bash", "-c"]

DOCKER_COMPOSE := "docker compose"

# List available recipes
default:
	@just --list

# Onboard a new operator (create data folders, initialize configs)
setup:
	./setup.sh

# Initialize the FLND wallet (run after configuring flnd.conf)
setup-wallet:
	@if [ -f "data/flnd/data/chain/flokicoin/main/wallet.db" ]; then \
		echo "✅ Existing wallet detected. Skipping creation."; \
	else \
		echo "🔐 Setting up FLND Wallet..."; \
		if [ -f "data/flnd/flnd.conf" ]; then \
			sed -i 's/^[[:space:];]*flokicoin.mainnet=true/flokicoin.mainnet=true/' data/flnd/flnd.conf; \
			sed -i 's/^[[:space:];]*flokicoin.node=neutrino/flokicoin.node=neutrino/' data/flnd/flnd.conf; \
		fi; \
		ABS_DATA_DIR=$(pwd)/data/flnd; \
		IMAGE_NAME=$(grep "^IMAGE_NAME=" .env | cut -d '=' -f 2 || echo "ghcr.io/myfloki/flokicoin:latest"); \
		docker rm -f flnd-setup &> /dev/null || true; \
		echo "Starting temporary container..."; \
		docker run -d --name flnd-setup \
			-v "$ABS_DATA_DIR:/root/.flnd" \
			$IMAGE_NAME flnd --configfile=/root/.flnd/flnd.conf; \
		echo "⏳ Waiting for FLND to initialize..."; \
		MAX_RETRIES=30; COUNT=0; \
		until docker exec flnd-setup ls /root/.flnd/tls.cert &> /dev/null || [ $COUNT -eq $MAX_RETRIES ]; do \
			if [ "$(docker inspect -f '{{ "{{" }}.State.Running{{ "}}" }}' flnd-setup 2>/dev/null)" != "true" ]; then \
				echo "❌ Error: FLND container stopped unexpectedly!"; \
				docker logs flnd-setup; \
				docker rm flnd-setup > /dev/null; \
				exit 1; \
			fi; \
			sleep 1; ((COUNT++)); \
		done; \
		if [ $COUNT -eq $MAX_RETRIES ]; then \
			echo "❌ Error: Timeout waiting for FLND."; \
			docker stop flnd-setup > /dev/null && docker rm flnd-setup > /dev/null; \
			exit 1; \
		fi; \
		docker exec -it flnd-setup flncli --network=mainnet create; \
		echo "✅ Wallet initialized. Cleaning up..."; \
		docker stop flnd-setup > /dev/null && docker rm flnd-setup > /dev/null; \
	fi

# Ensure the FLND wallet is unlocked (sets up auto-unlock if needed)
unlock:
	@if [ "$(docker inspect -f '{{ "{{" }}.State.Running{{ "}}" }}' flnd 2>/dev/null)" != "true" ]; then \
		echo "❌ Error: flnd container is not running. Try 'just up' first."; \
		exit 1; \
	fi; \
	echo "🔍 Detecting wallet state..."; \
	if docker exec flnd flncli --network=mainnet getinfo &> /dev/null; then \
		echo "✅ Wallet is already unlocked."; \
		exit 0; \
	fi; \
	RAW_STATE=$(docker exec flnd flncli --network=mainnet state 2>&1 || echo "OFFLINE"); \
	if echo "$$RAW_STATE" | grep -iqE "ACTIVE|UNLOCKED"; then \
		echo "✅ Wallet is already unlocked."; \
		exit 0; \
	fi; \
	if [ ! -f "data/flnd/wallet-password.txt" ]; then \
		echo "🔐 Auto-unlock is not configured."; \
		python3 -c 'import getpass, os; p = getpass.getpass("Enter wallet password: "); f = open("data/flnd/wallet-password.txt", "w"); f.write(p); f.close(); os.chmod("data/flnd/wallet-password.txt", 0o600)' 2>/dev/null; \
		if [ ! -f "data/flnd/wallet-password.txt" ] || [ ! -s "data/flnd/wallet-password.txt" ]; then echo "❌ Password entry failed or was empty."; rm -f data/flnd/wallet-password.txt; exit 1; fi; \
		if [ -f "data/flnd/flnd.conf" ]; then \
			if grep -q "wallet-unlock-password-file" data/flnd/flnd.conf; then \
				sed -i "s|^[[:space:];]*wallet-unlock-password-file=.*|wallet-unlock-password-file=/root/.flnd/wallet-password.txt|" data/flnd/flnd.conf; \
			else \
				echo "wallet-unlock-password-file=/root/.flnd/wallet-password.txt" >> data/flnd/flnd.conf; \
			fi; \
			echo "✅ Password saved and flnd.conf updated. Restarting flnd to apply..."; \
			{{DOCKER_COMPOSE}} restart flnd; \
		else \
			echo "⚠️  data/flnd/flnd.conf not found. Manual intervention required."; \
		fi; \
	else \
		if grep -qE "^[[:space:]]*wallet-unlock-password-file=/root/.flnd/wallet-password.txt" data/flnd/flnd.conf 2>/dev/null; then \
			echo "🔐 Auto-unlock is configured but wallet is still locked."; \
			echo "💡 This usually means the password in data/flnd/wallet-password.txt is incorrect."; \
			echo "💡 You can delete the file and try again: rm data/flnd/wallet-password.txt && just unlock"; \
		else \
			echo "🔄 Auto-unlock file exists but config is missing. Updating flnd.conf and restarting..."; \
			if grep -q "wallet-unlock-password-file" data/flnd/flnd.conf; then \
				sed -i "s|^[[:space:];]*wallet-unlock-password-file=.*|wallet-unlock-password-file=/root/.flnd/wallet-password.txt|" data/flnd/flnd.conf; \
			else \
				echo "wallet-unlock-password-file=/root/.flnd/wallet-password.txt" >> data/flnd/flnd.conf; \
			fi; \
			{{DOCKER_COMPOSE}} restart flnd; \
		fi; \
	fi

# Open a bash shell in the flnd container
cli:
	docker exec -it flnd bash

# Run flncli commands (e.g., just flncli getinfo)
flncli *args:
	docker exec -it flnd flncli --network=mainnet {{args}}

# Backup the Static Channel Backup (SCB) file
# This file is automatically updated by flnd, but we create a timestamped copy for safety.
backup-channels:
	@mkdir -p backups
	@TIMESTAMP=$(date +%Y%m%d_%H%M%S); \
	SCB_FILE="data/flnd/data/chain/flokicoin/main/channel.backup"; \
	if [ -f "$SCB_FILE" ]; then \
		cp "$SCB_FILE" "backups/channel.backup.$TIMESTAMP"; \
		echo "✅ Host-side backup created: backups/channel.backup.$TIMESTAMP"; \
	else \
		echo "⚠️  Static Channel Backup file not found at $SCB_FILE"; \
		echo "💡 Note: flnd only creates this file after your first channel is opened."; \
	fi; \
	if [ "$(docker inspect -f '{{ "{{" }}.State.Running{{ "}}" }}' flnd 2>/dev/null)" = "true" ]; then \
		echo "📦 Requesting backup via flncli..."; \
		docker exec flnd flncli --network=mainnet exportchanbackup --all --output_file /root/.flnd/data/chain/flokicoin/main/channel.backup.cli; \
		cp "data/flnd/data/chain/flokicoin/main/channel.backup.cli" "backups/channel.backup.cli.$TIMESTAMP"; \
		rm "data/flnd/data/chain/flokicoin/main/channel.backup.cli"; \
		echo "✅ CLI-exported backup created: backups/channel.backup.cli.$TIMESTAMP"; \
	fi

# Restore the Static Channel Backup (SCB)
# DANGER: Only use this if you have lost your channel data.
# This command triggers 'Data Loss Protection' which asks peers to force-close channels.
restore-channels backup_file:
	@if [ ! -f "{{backup_file}}" ]; then \
		echo "❌ Error: Backup file '{{backup_file}}' not found."; \
		exit 1; \
	fi; \
	if [ "$(docker inspect -f '{{ "{{" }}.State.Running{{ "}}" }}' flnd 2>/dev/null)" != "true" ]; then \
		echo "❌ Error: flnd service must be running and unlocked to restore via CLI."; \
		echo "💡 Try: just up && just unlock"; \
		exit 1; \
	fi; \
	ABS_BACKUP=$(realpath {{backup_file}}); \
	FILE_NAME=$(basename $ABS_BACKUP); \
	cp "$ABS_BACKUP" "data/flnd/$FILE_NAME"; \
	echo "🔄 Restoring channels via flncli..."; \
	docker exec flnd flncli --network=mainnet restorechanbackup --multi_file "/root/.flnd/$FILE_NAME"; \
	rm "data/flnd/$FILE_NAME"; \
	echo "✅ Restore command sent to flnd."; \
	echo "📜 Check logs (just logs-flnd) to see the progress of channel closures and fund recovery."

# Configure the node for public announcement (detects IP and prompts for alias)
set-public-node:
	@echo "🔍 Detecting public IP..." ; \
	DETECTED_IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me) ; \
	if [ -z "$DETECTED_IP" ]; then echo "❌ Error: Could not detect public IP."; exit 1; fi; \
	read -p "Detected Public IP: $DETECTED_IP. Use this IP? (y/n): " confirm ; \
	if [ "$confirm" = "y" ]; then \
		SELECTED_IP=$DETECTED_IP; \
	else \
		read -p "Enter your public IP manually: " SELECTED_IP ; \
	fi ; \
	if [ ! -z "$SELECTED_IP" ]; then \
		sed -i "s/^[[:space:];]*externalip=.*/externalip=$SELECTED_IP/" data/flnd/flnd.conf ; \
		sed -i "s/^[[:space:];]*listen=.*/listen=0.0.0.0:5521/" data/flnd/flnd.conf ; \
		echo "✅ Public IP updated in flnd.conf to $SELECTED_IP" ; \
	fi ; \
	read -p "Enter an alias for your node (current: lokinode-operator): " alias ; \
	if [ ! -z "$alias" ]; then \
		sed -i "s/^[[:space:];]*alias=.*/alias=$alias/" data/flnd/flnd.conf ; \
		echo "✅ Alias updated in flnd.conf" ; \
	fi ; \
	echo "🚀 Configuration updated. Remember to restart flnd for changes to take effect."


# Revert the node to private mode (removes public announcement)
set-private-node:
	@sed -i "s/^externalip=/; externalip=/" data/flnd/flnd.conf ; \
	sed -i "s/^listen=0.0.0.0:5521/; listen=0.0.0.0:5521/" data/flnd/flnd.conf ; \
	echo "✅ Node reverted to private mode in flnd.conf. Remember to restart flnd."

# Start the operator services
up:
	{{DOCKER_COMPOSE}} up -d

# Stop the operator services
down:
	{{DOCKER_COMPOSE}} down

# Restart the operator services
restart:
	{{DOCKER_COMPOSE}} restart

# Pull the latest images and restart the operator services
upgrade:
	{{DOCKER_COMPOSE}} pull
	{{DOCKER_COMPOSE}} up -d
	@just unlock

# View logs for all services
logs:
	{{DOCKER_COMPOSE}} logs -f

# View logs for flnd
logs-flnd:
	{{DOCKER_COMPOSE}} logs -f flnd

# View logs for lokihub
logs-lokihub:
	{{DOCKER_COMPOSE}} logs -f lokihub

# Show status of services
status:
	{{DOCKER_COMPOSE}} ps
