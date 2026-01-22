<#
.SYNOPSIS
    Clean up all resources created by the sample.

.DESCRIPTION
    Deletes all Azure resources created by the cross-subscription AMPLS sample.

.PARAMETER EnvironmentName
    The environment name used during deployment.

.PARAMETER UseAzd
    If true, use azd down. Otherwise, delete resource groups directly.

.EXAMPLE
    ./cleanup.ps1 -EnvironmentName "ampls-demo"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName = "ampls-demo",

    [Parameter(Mandatory = $false)]
    [switch]$UseAzd = $false
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  Cleaning Up Cross-Subscription AMPLS Sample                  ║" -ForegroundColor Red
Write-Host "║                                                               ║" -ForegroundColor Red
Write-Host "║  ⚠️  This will DELETE all resources!                          ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

$confirmation = Read-Host "Are you sure you want to delete all resources? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "❌ Cleanup cancelled." -ForegroundColor Yellow
    exit 0
}

if ($UseAzd -or (Test-Path ".azure")) {
    Write-Host ""
    Write-Host "🗑️  Running azd down..." -ForegroundColor Yellow
    
    azd down --force --purge
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ All resources deleted successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  azd down completed with warnings. Cleaning up manually..." -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "🗑️  Deleting resource groups..." -ForegroundColor Yellow
    
    $originationsRg = "rg-originations-$EnvironmentName"
    $workloadRg = "rg-workload-$EnvironmentName"
    
    # Delete workload RG first (has dependencies on originations)
    Write-Host "   Deleting $workloadRg..." -ForegroundColor Gray
    az group delete --name $workloadRg --yes --no-wait 2>$null
    
    Write-Host "   Deleting $originationsRg..." -ForegroundColor Gray
    az group delete --name $originationsRg --yes --no-wait 2>$null
    
    Write-Host ""
    Write-Host "✅ Resource group deletion initiated!" -ForegroundColor Green
    Write-Host "   (Deletion runs in the background and may take 5-10 minutes)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Cleanup complete!                                            " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
