#!/bin/bash
set -e

# Function to check if flnd is unlocked
check_unlock_status() {
    # We use getinfo to check status. If it's locked, it usually returns an error 
    # or specific info about being locked.
    if flncli --network=mainnet getinfo > /dev/null 2>&1; then
        return 0 # Unlocked
    else
        return 1 # Locked or not ready
    fi
}

echo "🚀 Starting FLND..."
# Start flnd in the background
flnd --configfile=/root/.flnd/flnd.conf &

# Wait for flnd to start and the RPC server to be available
echo "⏳ Waiting for FLND RPC server to start..."
until flncli --network=mainnet getinfo > /dev/null 2>&1 || [[ $? -ne 255 ]]; do
    # 255 usually means connection refused (still starting)
    # If it's locked, it might return a different error code but at least it's responding.
    sleep 2
done

echo "🔍 Checking wallet lock status..."
while ! check_unlock_status; do
    echo "🔓 Wallet is LOCKED. Please unlock it using: just unlock"
    sleep 10
done

echo "✅ Wallet is UNLOCKED and ready!"

# Wait for the background process
wait
