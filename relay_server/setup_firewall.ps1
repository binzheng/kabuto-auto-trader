# Kabuto Relay Server - Firewall Setup Script
# Run as Administrator: Right-click PowerShell -> "Run as administrator"

param(
    [int]$Port = 5000,
    [string]$RuleName = "Kabuto Relay Server"
)

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Setting up firewall rules for $RuleName on port $Port..." -ForegroundColor Cyan

# Remove existing rules with same name (if any)
$existingRules = Get-NetFirewallRule -DisplayName "$RuleName*" -ErrorAction SilentlyContinue
if ($existingRules) {
    Write-Host "Removing existing rules..." -ForegroundColor Yellow
    $existingRules | Remove-NetFirewallRule
}

# Add inbound rule
try {
    New-NetFirewallRule `
        -DisplayName "$RuleName (Inbound)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Any `
        -Description "Allow inbound connections to Kabuto Relay Server" | Out-Null

    Write-Host "OK: Inbound rule created" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create inbound rule - $_" -ForegroundColor Red
}

# Add outbound rule
try {
    New-NetFirewallRule `
        -DisplayName "$RuleName (Outbound)" `
        -Direction Outbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Any `
        -Description "Allow outbound connections from Kabuto Relay Server" | Out-Null

    Write-Host "OK: Outbound rule created" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create outbound rule - $_" -ForegroundColor Red
}

# Verify rules
Write-Host "`nVerifying firewall rules:" -ForegroundColor Cyan
Get-NetFirewallRule -DisplayName "$RuleName*" | Format-Table DisplayName, Direction, Action, Enabled -AutoSize

Write-Host "`nFirewall setup complete!" -ForegroundColor Green
Write-Host "Port $Port is now open for external access." -ForegroundColor Cyan
