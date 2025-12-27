#!/bin/bash
# Kabuto Relay Server - Startup Script

echo "============================================"
echo "Kabuto Relay Server - Starting..."
echo "============================================"

# Check if Redis is running
if ! redis-cli ping > /dev/null 2>&1; then
    echo "ERROR: Redis is not running"
    echo "Please start Redis with: redis-server"
    exit 1
fi

# Check if data directory exists
if [ ! -d "data/logs" ]; then
    echo "Creating data directories..."
    mkdir -p data/logs
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install/update dependencies
echo "Installing dependencies..."
pip install -q -r requirements.txt

# Run server
echo "Starting Kabuto Relay Server..."
python -m app.main
