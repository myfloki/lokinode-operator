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

# Unlock the FLND wallet
unlock:
    docker exec -it flnd flncli --network=mainnet unlock

# Lock the FLND wallet
lock:
    docker exec -it flnd flncli --network=mainnet lock

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
