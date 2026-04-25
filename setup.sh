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
        echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")\" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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
    # Set default values for Flokicoin and Neutrino if they are commented out
    sed -i 's/^[[:space:];]*flokicoin.mainnet=true/flokicoin.mainnet=true/' data/flnd/flnd.conf
    sed -i 's/^[[:space:];]*flokicoin.node=neutrino/flokicoin.node=neutrino/' data/flnd/flnd.conf
fi

# 5. Wallet Setup Flow
if [ ! -f "data/flnd/data/chain/flokicoin/main/wallet.db" ]; then
    if [ -f "./bin/just" ]; then
        ./bin/just setup-wallet
    else
        just setup-wallet
    fi
else
    echo "✅ Existing wallet detected."
fi

# Detect IPs for suggestion
PUBLIC_IP=$(curl -s --max-time 2 https://api.ipify.org || curl -s --max-time 2 https://icanhazip.com || curl -s --max-time 2 https://ifconfig.me || echo "")
LOCAL_IPS=$(hostname -I 2>/dev/null || echo "")

echo ""
echo "🎉 Setup finished successfully!"
echo "------------------------------------------------------------------------"
if [[ ":$PATH:" != *":$(pwd)/bin:"* ]] && [ -f "./bin/just" ]; then
    echo "👉 Use: ./bin/just set-public-node (to announce your node to the network)"
    echo "👉 Use: ./bin/just up              (to start services)"
    echo "👉 Use: ./bin/just unlock          (to unlock your wallet)"
else
    echo "👉 Use: just set-public-node       (to announce your node to the network)"
    echo "👉 Use: just up                    (to start services)"
    echo "👉 Use: just unlock                (to unlock your wallet)"
fi
echo ""
echo "🌍 Once started, visit Lokihub at:"
echo "   http://localhost:1610"
echo "   http://127.0.0.1:1610"
for ip in $LOCAL_IPS; do
    if [ "$ip" != "127.0.0.1" ]; then
        echo "   http://$ip:1610"
    fi
done
if [ ! -z "$PUBLIC_IP" ] && [[ ! " $LOCAL_IPS " =~ " $PUBLIC_IP " ]]; then
    echo "   http://$PUBLIC_IP:1610"
fi
echo ""
echo "⚡ FLND (Lightning Daemon) ports available:"
echo "   P2P: 5521"
echo "   RPC: 10005"
echo "   REST: 5050"
echo "------------------------------------------------------------------------"
