<#
.SYNOPSIS
    Post-deploy hook - runs after application is deployed.
#>

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Post-Deploy: Verifying Azure Function" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Get Function App URL
$envValues = azd env get-values | ConvertFrom-StringData
$functionUrl = $envValues.FUNCTION_APP_URL

Write-Host "📋 Function App URL: $functionUrl" -ForegroundColor White
Write-Host ""

# Wait for the Function App to be ready
Write-Host "⏳ Waiting for Function App to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Test the Function App by listing tables
Write-Host "🔍 Testing Function App connectivity..." -ForegroundColor Cyan

try {
    $apiKey = $envValues.FUNCTION_API_KEY
    $headers = @{
        "x-functions-key" = $apiKey
    }
    $testUrl = "$functionUrl/api/list_tables"
    $response = Invoke-WebRequest -Uri $testUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Function App is ready and can query Log Analytics!" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠️  Function App test failed. The function may still be warming up." -ForegroundColor Yellow
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. Run ./inject-failure.ps1 to simulate issues" -ForegroundColor Gray
Write-Host "2. Configure SRE Agent with the Function App URL as HTTP tools" -ForegroundColor Gray
Write-Host "3. Ask SRE Agent to investigate the errors" -ForegroundColor Gray
Write-Host ""
