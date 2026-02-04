<#
.SYNOPSIS
    Apply the fix for the injected failure scenario.

.DESCRIPTION
    Resolves the simulated issues on the VMs by stopping the stress processes
    and clearing the error conditions.

.PARAMETER ResourceGroup
    Resource group containing the workload VMs.

.EXAMPLE
    ./fix-issue.ps1 -ResourceGroup "rg-workload-ampls-demo"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-workload-ampls-demo"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Applying Fix for Failure Scenario                            ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# Check if resource group exists
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Error "❌ Resource group '$ResourceGroup' does not exist."
    exit 1
}

$vms = @("app-vm", "db-vm", "web-vm")

Write-Host "🔧 Applying fixes to VMs..." -ForegroundColor Yellow

foreach ($vm in $vms) {
    Write-Host ""
    Write-Host "📊 Fixing $vm..." -ForegroundColor Cyan
    
    $fixScript = @'
#!/bin/bash
# Kill any stress processes
pkill stress 2>/dev/null || true
pkill dd 2>/dev/null || true

# Clean up temp files
rm -f /tmp/disktest 2>/dev/null || true

# Log the fix
logger -p user.info "RESOLUTION: Issue resolved - processes cleaned up"
logger -p user.info "RESOLUTION: System returning to normal operation"
'@

    az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $vm `
        --command-id RunShellScript `
        --scripts $fixScript `
        --output none 2>$null
    
    Write-Host "   ✅ $vm fixed" -ForegroundColor Green
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ All issues resolved!                                      " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Resolution logs will appear in Log Analytics within 2-5 minutes." -ForegroundColor White
Write-Host ""
