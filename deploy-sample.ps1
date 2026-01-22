<#
.SYNOPSIS
    Deploy the Cross-Subscription AMPLS sample environment.

.DESCRIPTION
    Creates all Azure resources for demonstrating Azure SRE Agent with 
    Azure Monitor Private Link Scope across subscriptions.

.PARAMETER ResourceGroup
    Name of the resource group to create.

.PARAMETER Location
    Azure region for deployment.

.PARAMETER OriginationsSubscriptionId
    Subscription ID for the Originations LAW (optional, uses current if not specified).

.PARAMETER WorkloadSubscriptionId
    Subscription ID for the workload resources (optional, uses current if not specified).

.EXAMPLE
    ./deploy-sample.ps1 -ResourceGroup "cross-sub-ampls-demo" -Location "eastus"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "cross-sub-ampls-demo",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$OriginationsSubscriptionId = "",

    [Parameter(Mandatory = $false)]
    [string]$WorkloadSubscriptionId = "",

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName = "ampls-demo"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Cross-Subscription AMPLS Sample Deployment                   ║" -ForegroundColor Cyan
Write-Host "║                                                               ║" -ForegroundColor Cyan
Write-Host "║  This sample demonstrates:                                    ║" -ForegroundColor Cyan
Write-Host "║  • Log Analytics with public query access DISABLED            ║" -ForegroundColor Cyan
Write-Host "║  • Azure Monitor Private Link Scope (AMPLS)                   ║" -ForegroundColor Cyan
Write-Host "║  • Private Endpoint from a different subscription/VNet        ║" -ForegroundColor Cyan
Write-Host "║  • Azure Functions as query proxy for Azure SRE Agent         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow

# Azure CLI
$azVersion = az version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Azure CLI is not installed. Please install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}
Write-Host "✅ Azure CLI installed" -ForegroundColor Green

# Check if logged in
$account = az account show 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "🔑 Please log in to Azure..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "✅ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "   Subscription: $($account.name)" -ForegroundColor Gray

# Use Azure Developer CLI if available
$useAzd = $false
$azdVersion = azd version 2>&1
if ($LASTEXITCODE -eq 0) {
    $useAzd = $true
    Write-Host "✅ Azure Developer CLI (azd) installed - using azd for deployment" -ForegroundColor Green
}
else {
    Write-Host "ℹ️  Azure Developer CLI not found - using Azure CLI for deployment" -ForegroundColor Yellow
}

if ($useAzd) {
    # Deploy with azd
    Write-Host ""
    Write-Host "🚀 Deploying with Azure Developer CLI..." -ForegroundColor Cyan
    
    # Initialize azd if needed
    if (-not (Test-Path ".azure")) {
        Write-Host "📁 Initializing azd environment: $EnvironmentName" -ForegroundColor Yellow
        azd env new $EnvironmentName
    }
    
    # Set environment variables
    azd env set AZURE_LOCATION $Location
    
    # Deploy
    Write-Host "📦 Running azd up (this may take 15-20 minutes)..." -ForegroundColor Yellow
    azd up
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Deployment complete!" -ForegroundColor Green
        
        # Get outputs
        $outputs = azd env get-values | ConvertFrom-StringData
        Write-Host ""
        Write-Host "📋 Deployment Outputs:" -ForegroundColor Cyan
        Write-Host "   Function App URL: $($outputs.FUNCTION_APP_URL)" -ForegroundColor White
        Write-Host "   Log Analytics Workspace: $($outputs.LOG_ANALYTICS_WORKSPACE_NAME)" -ForegroundColor White
    }
    else {
        Write-Error "❌ Deployment failed. Check the output above for details."
        exit 1
    }
}
else {
    # Deploy with Azure CLI (fallback)
    Write-Host ""
    Write-Host "🚀 Deploying with Azure CLI..." -ForegroundColor Cyan
    
    # Create resource groups
    Write-Host "📁 Creating resource groups..." -ForegroundColor Yellow
    $originationsRg = "rg-originations-$EnvironmentName"
    $workloadRg = "rg-workload-$EnvironmentName"
    
    az group create --name $originationsRg --location $Location --output none
    Write-Host "   ✅ Created: $originationsRg" -ForegroundColor Green
    
    az group create --name $workloadRg --location $Location --output none
    Write-Host "   ✅ Created: $workloadRg" -ForegroundColor Green
    
    # Deploy Bicep
    Write-Host ""
    Write-Host "📦 Deploying infrastructure (this may take 15-20 minutes)..." -ForegroundColor Yellow
    
    $deploymentName = "cross-sub-ampls-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file ./infra/main.bicep `
        --parameters environmentName=$EnvironmentName location=$Location `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Deployment complete!" -ForegroundColor Green
        
        # Get outputs
        $outputs = az deployment sub show --name $deploymentName --query properties.outputs | ConvertFrom-Json
        Write-Host ""
        Write-Host "📋 Deployment Outputs:" -ForegroundColor Cyan
        Write-Host "   Function App URL: $($outputs.FUNCTION_APP_URL.value)" -ForegroundColor White
        Write-Host "   Log Analytics Workspace: $($outputs.LOG_ANALYTICS_WORKSPACE_NAME.value)" -ForegroundColor White
    }
    else {
        Write-Error "❌ Deployment failed. Check the output above for details."
        exit 1
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                         Next Steps                            " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "1️⃣  Inject a failure to generate logs:" -ForegroundColor White
Write-Host "    ./inject-failure.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "2️⃣  Configure SRE Agent with the Function App HTTP tools" -ForegroundColor White
Write-Host ""
Write-Host "3️⃣  Ask SRE Agent to investigate:" -ForegroundColor White
Write-Host "    'Show me the tables in my private Log Analytics workspace'" -ForegroundColor Gray
Write-Host ""
Write-Host "4️⃣  Clean up when done:" -ForegroundColor White
Write-Host "    ./cleanup.ps1" -ForegroundColor Gray
Write-Host ""
