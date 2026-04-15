#!/bin/bash
set -e

echo "🚀 Starting Lokinode Operator Setup..."

# Function to install just
install_just() {
    if ! command -v just &> /dev/null; then
        echo "📦 'just' command not found. Installing..."
        if command -v curl &> /dev/null; then
            if [ -w "/usr/local/bin" ]; then
                curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
            else
                echo "⚠️  /usr/local/bin is not writable. Installing to ./bin..."
                mkdir -p ./bin
                curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ./bin
                export PATH="$PATH:$(pwd)/bin"
                echo "💡 Added ./bin to PATH for this session."
            fi
        else
            echo "❌ Error: 'curl' is required to install 'just'. Please install curl first."
            exit 1
        fi
    else
        echo "✅ 'just' is already installed."
    fi
}

# 1. Install Dependencies
install_just

# 2. Check for Docker & Compose
if ! command -v docker &> /dev/null; then
    echo "🐳 Docker not found. Attempting to install docker-ce-cli..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update && apt-get install -y docker-ce-cli
    else
        echo "❌ Error: Docker is not installed and couldn't be automatically installed."
        exit 1
    fi
fi

if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Error: Docker Compose plugin or docker-compose is not installed."
    exit 1
fi

# 3. Create data directories
mkdir -p data/flnd data/lokihub

# 4. Initialize Configs
if [ ! -f .env ]; then
    echo "📄 Creating .env from .env.sample..."
    cp .env.sample .env
fi

if [ ! -f data/flnd/flnd.conf ]; then
    echo "📄 Creating data/flnd/flnd.conf from sample..."
    cp data/flnd/flnd.conf.sample data/flnd/flnd.conf
fi

# Load variables
export $(grep -v '^#' .env | xargs)
IMAGE_NAME=${IMAGE_NAME:-ghcr.io/myfloki/flokicoin:latest}

# 5. Wallet Setup Flow
# Note: flnd stores data in /root/.flnd/data/chain/flokicoin/mainnet/
if [ -f "$(pwd)/data/flnd/data/chain/flokicoin/mainnet/wallet.db" ]; then
    echo "✅ Existing wallet detected. Skipping creation."
else
    echo "🔐 Setting up FLND Wallet..."
    echo "Starting temporary container for wallet initialization..."

    # Ensure no old container is blocking us
    docker rm -f flnd-setup &> /dev/null || true

    # Use absolute path for mounting to be safe (especially in nested/socket environments)
    ABS_DATA_DIR="$(pwd)/data/flnd"

    # Run flnd in background
    docker run -d --name flnd-setup \
        -v "$ABS_DATA_DIR:/root/.flnd" \
        $IMAGE_NAME flnd --configfile=/root/.flnd/flnd.conf \
        --flokicoin.active --flokicoin.mainnet --flokicoin.node=bitcoind \
        --bitcoind.rpchost=1.2.3.4 --bitcoind.rpcuser=user --bitcoind.rpcpass=pass \
        --bitcoind.zmqpubrawblock=tcp://1.2.3.4:28332 --bitcoind.zmqpubrawtx=tcp://1.2.3.4:28333 > /dev/null

    # Wait for flnd to generate TLS cert and start RPC
    echo "⏳ Waiting for FLND to initialize (this may take a moment)..."
    MAX_RETRIES=30
    COUNT=0
    until docker exec flnd-setup ls /root/.flnd/tls.cert &> /dev/null || [ $COUNT -eq $MAX_RETRIES ]; do
        # Check if the container is still running
        if [ "$(docker inspect -f '{{.State.Running}}' flnd-setup 2>/dev/null)" != "true" ]; then
            echo "❌ Error: FLND container stopped unexpectedly!"
            echo "--- FLND LOGS ---"
            docker logs flnd-setup
            echo "----------------"
            docker rm flnd-setup > /dev/null
            exit 1
        fi
        sleep 1
        ((COUNT++))
    done

    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo "❌ Error: FLND failed to start in time (Timeout)."
        echo "--- FLND LOGS ---"
        docker logs flnd-setup
        echo "----------------"
        docker stop flnd-setup > /dev/null && docker rm flnd-setup > /dev/null
        exit 1
    fi

    # Interactively create wallet
    echo "------------------------------------------------------------------------"
    echo "INSTRUCTIONS:"
    echo "1. Choose a password for your wallet."
    echo "2. Select 'y' to generate a new seed phrase."
    echo "3. WRITE DOWN THE 24 WORDS CAREFULLY."
    echo "------------------------------------------------------------------------"
    docker exec -it flnd-setup flncli --network=mainnet create

    # Cleanup
    echo "------------------------------------------------------------------------"
    echo "✅ Wallet initialized. Cleaning up setup container..."
    docker stop flnd-setup > /dev/null
    docker rm flnd-setup > /dev/null
fi

echo ""
echo "🎉 Setup finished successfully!"
echo "------------------------------------------------------------------------"
if [[ ":$PATH:" != *":$(pwd)/bin:"* ]] && [ -f "./bin/just" ]; then
    echo "👉 Use: ./bin/just up    (to start services)"
else
    echo "👉 Use: just up          (to start services)"
fi
echo "------------------------------------------------------------------------"
