<#
.SYNOPSIS
    Inject a failure scenario into the workload VMs.

.DESCRIPTION
    Simulates application issues on the VMs that will be logged to the
    Log Analytics Workspace, demonstrating the cross-subscription AMPLS pattern.

.PARAMETER ResourceGroup
    Resource group containing the workload VMs.

.EXAMPLE
    ./inject-failure.ps1 -ResourceGroup "rg-workload-ampls-demo"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-workload-ampls-demo"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Injecting Failure Scenario                                   ║" -ForegroundColor Yellow
Write-Host "║                                                               ║" -ForegroundColor Yellow
Write-Host "║  This will simulate:                                          ║" -ForegroundColor Yellow
Write-Host "║  • Database connection failures on db-vm                      ║" -ForegroundColor Yellow
Write-Host "║  • Application errors on app-vm                               ║" -ForegroundColor Yellow
Write-Host "║  • HTTP 502 errors on web-vm                                  ║" -ForegroundColor Yellow
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

# Check if resource group exists
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Error "❌ Resource group '$ResourceGroup' does not exist. Run deploy-sample.ps1 first."
    exit 1
}

# Get VM names
$vms = @("app-vm", "db-vm", "web-vm")

Write-Host "🔧 Injecting failures into VMs..." -ForegroundColor Yellow

# Inject database failure (high disk I/O, connection errors)
Write-Host ""
Write-Host "📊 Injecting database failure on db-vm..." -ForegroundColor Cyan

$dbScript = @'
#!/bin/bash
# Simulate database connection issues
for i in {1..20}; do
    logger -p user.err "MySQL Error: Too many connections"
    logger -p user.err "MySQL Error: Lock wait timeout exceeded"
    logger -p user.warning "MySQL Warning: Disk I/O spike detected - 450 MB/s writes"
    sleep 2
done

# Simulate high disk I/O
dd if=/dev/zero of=/tmp/disktest bs=1M count=500 2>/dev/null &
'@

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name "db-vm" `
    --command-id RunShellScript `
    --scripts $dbScript `
    --output none 2>$null

Write-Host "   ✅ Database failure injected" -ForegroundColor Green

# Inject application failure (connection timeouts, memory issues)
Write-Host ""
Write-Host "📊 Injecting application failure on app-vm..." -ForegroundColor Cyan

$appScript = @'
#!/bin/bash
# Simulate application connection failures
for i in {1..20}; do
    logger -p user.err "Application Error: Connection to database timed out after 30000ms"
    logger -p user.err "Application Error: Failed to process transaction: Connection refused"
    logger -p user.err "Application Error: Circuit breaker OPEN for database connection pool"
    logger -p user.crit "Application Critical: OutOfMemoryError in transaction handler thread"
    sleep 2
done

# Simulate memory pressure
stress --vm 2 --vm-bytes 256M --timeout 120 &
'@

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name "app-vm" `
    --command-id RunShellScript `
    --scripts $appScript `
    --output none 2>$null

Write-Host "   ✅ Application failure injected" -ForegroundColor Green

# Inject web server failure (upstream timeouts, 502 errors)
Write-Host ""
Write-Host "📊 Injecting web server failure on web-vm..." -ForegroundColor Cyan

$webScript = @'
#!/bin/bash
# Simulate web server errors
for i in {1..20}; do
    logger -p user.err "nginx: upstream timed out (110: Connection timed out)"
    logger -p user.err "nginx: 502 Bad Gateway - upstream prematurely closed connection"
    logger -p user.warning "nginx: connection reset by peer while reading upstream"
    sleep 2
done
'@

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name "web-vm" `
    --command-id RunShellScript `
    --scripts $webScript `
    --output none 2>$null

Write-Host "   ✅ Web server failure injected" -ForegroundColor Green

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Failure injection complete!                               " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Logs will appear in Log Analytics within 2-5 minutes." -ForegroundColor White
Write-Host ""
Write-Host "🤖 Now ask Azure SRE Agent:" -ForegroundColor Cyan
Write-Host '   "I got an alert about errors on my workload VMs.' -ForegroundColor Gray
Write-Host '    Can you investigate app-vm, db-vm, and web-vm?"' -ForegroundColor Gray
Write-Host ""
Write-Host "💡 SRE Agent will use the Azure Function HTTP tools to query the" -ForegroundColor Yellow
Write-Host "   private Log Analytics workspace and correlate the errors." -ForegroundColor Yellow
Write-Host ""
