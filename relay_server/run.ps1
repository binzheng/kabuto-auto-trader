# Kabuto Relay Server - Startup Script

Write-Host "============================================"
Write-Host "Kabuto Relay Server - Starting..."
Write-Host "============================================"

# Check if MarketSpeed2 is running
try {
    $marketSpeed = Get-Process -Name "MarketSpeed2" -ErrorAction Stop
    Write-Host "MarketSpeed2 is running: OK" -ForegroundColor Green
} catch {
    Write-Host "ERROR: MarketSpeed2 is not running" -ForegroundColor Red
    Write-Host "Please start MarketSpeed2 before running the relay server"
    exit 1
}

# Check if Redis is running (Podman container)
try {
    $redisCheck = podman exec redis redis-cli ping 2>$null
    if ($LASTEXITCODE -ne 0 -or $redisCheck -ne "PONG") {
        throw
    }
    Write-Host "Redis connection: OK" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Redis is not running" -ForegroundColor Red
    Write-Host "Please start Redis with: podman start redis"
    Write-Host "Or check if Podman container 'redis' exists"
    exit 1
}

# Check if data directory exists
if (-not (Test-Path "data\logs")) {
    Write-Host "Creating data directories..."
    New-Item -ItemType Directory -Path "data\logs" -Force | Out-Null
}

# Check if virtual environment exists
if (-not (Test-Path "venv")) {
    Write-Host "Creating virtual environment..."
    python -m venv venv
}

# Activate virtual environment
Write-Host "Activating virtual environment..."
& ".\venv\Scripts\Activate.ps1"

# Install/update dependencies
Write-Host "Installing dependencies..."
pip install -q -r requirements.txt

# Run server
Write-Host "Starting Kabuto Relay Server..."
python -m app.main
