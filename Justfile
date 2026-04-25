set shell := ["bash", "-c"]

DOCKER_COMPOSE := "docker compose"

# Onboard a new operator (create data folders, initialize configs)
setup:
    ./setup.sh

# Initialize the FLND wallet (run after configuring flnd.conf)
setup-wallet:
    @if [ -f "data/flnd/data/chain/flokicoin/mainnet/wallet.db" ]; then \
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
