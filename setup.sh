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
    echo "❌ Error: Docker is not installed."
    exit 1
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

if [ ! -f data/flnd/lnd.conf ]; then
    echo "📄 Creating data/flnd/lnd.conf from sample..."
    cp data/flnd/lnd.conf.sample data/flnd/lnd.conf
fi

# Load variables
export $(grep -v '^#' .env | xargs)
IMAGE_NAME=${IMAGE_NAME:-ghcr.io/myfloki/flokicoin:latest}

# 5. Wallet Setup Flow
if [ -f "data/flnd/data/chain/flokicoin/mainnet/wallet.db" ]; then
    echo "✅ Existing wallet detected. Skipping creation."
else
    echo "🔐 Setting up FLND Wallet..."
    echo "Starting temporary container for wallet initialization..."

    # Run flnd in background
    docker run -d --name flnd-setup \
        -v $(pwd)/data/flnd:/root/.flnd \
        $IMAGE_NAME flnd --configfile=/root/.flnd/lnd.conf > /dev/null

    # Wait for flnd to generate TLS cert and start RPC
    echo "⏳ Waiting for FLND to initialize (this may take a moment)..."
    MAX_RETRIES=30
    COUNT=0
    until docker exec flnd-setup ls /root/.flnd/tls.cert &> /dev/null || [ $COUNT -eq $MAX_RETRIES ]; do
        sleep 1
        ((COUNT++))
    done

    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo "❌ Error: FLND failed to start in time. Check logs with 'docker logs flnd-setup'"
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
