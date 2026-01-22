<#
.SYNOPSIS
    Post-provision hook - runs after infrastructure is deployed.
#>

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Post-Provision: Configuring resources" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Get outputs from azd
$envValues = azd env get-values | ConvertFrom-StringData
$workloadRg = $envValues.WORKLOAD_RESOURCE_GROUP
$functionUrl = $envValues.FUNCTION_APP_URL

Write-Host "📋 Workload Resource Group: $workloadRg" -ForegroundColor White
Write-Host "📋 Function App URL: $functionUrl" -ForegroundColor White

# Wait for VMs to be ready
Write-Host ""
Write-Host "⏳ Waiting for VMs to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Install stress utility on VMs for failure injection
$vms = @("app-vm", "db-vm", "web-vm")

foreach ($vm in $vms) {
    Write-Host "📦 Installing stress utility on $vm..." -ForegroundColor Cyan
    
    az vm run-command invoke `
        --resource-group $workloadRg `
        --name $vm `
        --command-id RunShellScript `
        --scripts "apt-get update && apt-get install -y stress" `
        --output none 2>$null
}

Write-Host ""
Write-Host "✅ Post-provision configuration complete!" -ForegroundColor Green
Write-Host ""
