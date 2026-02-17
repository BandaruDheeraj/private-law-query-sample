# Connecting an Azure Function to an Existing AMPLS

This guide explains how to configure an Azure Function App to query a Log Analytics Workspace through an existing Azure Monitor Private Link Scope (AMPLS).

## Architecture Overview

```
┌─────────────────┐     HTTPS (Public)      ┌─────────────────────────────────────┐
│  Azure SRE      │ ◄───────────────────────│  Azure Function                     │
│  Agent          │                         │  (Public endpoint + Function Key)   │
└─────────────────┘                         └──────────────┬──────────────────────┘
                                                           │
                                                           │ VNet Integration
                                                           ▼
                                            ┌─────────────────────────────────────┐
                                            │  Virtual Network                    │
                                            │  ┌─────────────────────────────────┐│
                                            │  │ Private Endpoint → AMPLS → LAW ││
                                            │  └─────────────────────────────────┘│
                                            └─────────────────────────────────────┘
```

**Key points:**
- The Function App uses **VNet Integration** to route traffic through the VNet
- A **Private Endpoint** in the VNet connects to your existing AMPLS
- **Private DNS Zones** ensure the Function resolves LAW endpoints to private IPs
- The Function authenticates to LAW using **Managed Identity**

---

## Prerequisites

- Existing AMPLS with your Log Analytics Workspace linked
- A VNet (new or existing) where you'll integrate the Function App
- Two subnets:
  - One for Function App VNet integration (delegated to `Microsoft.Web/serverFarms`)
  - One for Private Endpoints

---

## Step 1: Create Private Endpoint to AMPLS

If your VNet doesn't already have a Private Endpoint to the AMPLS:

```powershell
# Variables - update these
$amplsResourceId = "/subscriptions/<subscription-id>/resourceGroups/<ampls-rg>/providers/Microsoft.Insights/privateLinkScopes/<ampls-name>"
$resourceGroup = "<function-app-rg>"
$vnetName = "<your-vnet>"
$subnetName = "<subnet-for-endpoints>"

# Create Private Endpoint
az network private-endpoint create `
  --name "pe-to-ampls" `
  --resource-group $resourceGroup `
  --vnet-name $vnetName `
  --subnet $subnetName `
  --private-connection-resource-id $amplsResourceId `
  --group-id "azuremonitor" `
  --connection-name "ampls-connection"
```

---

## Step 2: Configure Private DNS Zones

The Private Endpoint requires these DNS zones linked to your VNet:

| DNS Zone | Purpose |
|----------|---------|
| `privatelink.monitor.azure.com` | Azure Monitor APIs |
| `privatelink.oms.opinsights.azure.com` | Log Analytics query API |
| `privatelink.ods.opinsights.azure.com` | Log Analytics data ingestion |
| `privatelink.agentsvc.azure-automation.net` | Agent service |
| `privatelink.blob.core.windows.net` | Blob storage (for some scenarios) |

```powershell
# Variables
$resourceGroup = "<function-app-rg>"
$vnetName = "<your-vnet>"
$privateEndpointName = "pe-to-ampls"

# DNS zones required for AMPLS
$dnsZones = @(
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
  "privatelink.blob.core.windows.net"
)

# Create DNS zones and link to VNet
foreach ($zone in $dnsZones) {
  # Create zone (skip if exists)
  az network private-dns zone create `
    --resource-group $resourceGroup `
    --name $zone `
    --only-show-errors 2>$null

  # Link zone to VNet
  $linkName = "link-$($zone -replace '\.', '-')"
  az network private-dns zone vnet-link create `
    --resource-group $resourceGroup `
    --zone-name $zone `
    --name $linkName `
    --virtual-network $vnetName `
    --registration-enabled false `
    --only-show-errors 2>$null
}

# Create DNS zone group on the Private Endpoint (auto-registers DNS records)
az network private-endpoint dns-zone-group create `
  --resource-group $resourceGroup `
  --endpoint-name $privateEndpointName `
  --name "ampls-dns-zones" `
  --private-dns-zone "privatelink.monitor.azure.com" `
  --zone-name "monitor"
```

> **Note:** If your organization uses centralized Private DNS Zones, link those existing zones to your VNet instead of creating new ones.

---

## Step 3: Configure Function App VNet Integration

```powershell
# Variables
$functionAppName = "<function-app-name>"
$resourceGroup = "<function-app-rg>"
$vnetName = "<your-vnet>"
$integrationSubnet = "<subnet-for-function-integration>"

# Add VNet integration
az functionapp vnet-integration add `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --vnet $vnetName `
  --subnet $integrationSubnet

# CRITICAL: Route ALL traffic through VNet
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --settings "WEBSITE_VNET_ROUTE_ALL=1"
```

> **Important:** The `WEBSITE_VNET_ROUTE_ALL=1` setting is critical. Without it, the Function App will use public routes for Azure services and bypass the Private Endpoint.

---

## Step 4: Grant Function App Access to Log Analytics

```powershell
# Variables
$functionAppName = "<function-app-name>"
$functionAppRg = "<function-app-rg>"
$lawResourceId = "/subscriptions/<subscription-id>/resourceGroups/<law-rg>/providers/Microsoft.OperationalInsights/workspaces/<law-name>"

# Enable Managed Identity (if not already enabled)
az functionapp identity assign `
  --name $functionAppName `
  --resource-group $functionAppRg

# Get the Principal ID
$principalId = az functionapp identity show `
  --name $functionAppName `
  --resource-group $functionAppRg `
  --query principalId -o tsv

# Grant Log Analytics Reader role
az role assignment create `
  --assignee $principalId `
  --role "Log Analytics Reader" `
  --scope $lawResourceId
```

---

## Step 5: Configure Function App Settings

```powershell
# Variables
$functionAppName = "<function-app-name>"
$resourceGroup = "<function-app-rg>"
$workspaceId = "<your-workspace-id>"  # GUID from LAW Properties

az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --settings "LOG_ANALYTICS_WORKSPACE_ID=$workspaceId"
```

---

## Verification

### 1. Verify DNS Resolution

From the Function App's Kudu console (**Advanced Tools** → **Go** → **Debug Console** → **CMD**):

```bash
nslookup <workspace-id>.ods.opinsights.azure.com
```

**Expected:** Resolves to a private IP (e.g., `10.x.x.x`)  
**Problem:** If it resolves to a public IP, DNS zones aren't linked correctly

### 2. Verify VNet Integration

**Azure Portal** → **Function App** → **Networking** → **VNet Integration**

Check that:
- VNet integration is enabled
- Shows the correct VNet/subnet
- "Route All" is enabled

### 3. Test a Query

Invoke one of the Function endpoints:

```powershell
$functionUrl = "https://<function-app>.azurewebsites.net/api/list_tables"
$functionKey = "<your-function-key>"

Invoke-RestMethod -Uri $functionUrl -Headers @{ "x-functions-key" = $functionKey }
```

---

## Checklist

| Requirement | Verification |
|-------------|--------------|
| ✅ Private Endpoint to AMPLS exists | `az network private-endpoint list --resource-group <rg>` |
| ✅ DNS zones created and linked | `az network private-dns zone list --resource-group <rg>` |
| ✅ Function has VNet integration | Portal → Function App → Networking |
| ✅ `WEBSITE_VNET_ROUTE_ALL=1` set | Portal → Function App → Configuration → App Settings |
| ✅ Managed Identity enabled | Portal → Function App → Identity |
| ✅ LAW Reader role assigned | Portal → Log Analytics Workspace → Access Control (IAM) |
| ✅ Workspace ID configured | Portal → Function App → Configuration → App Settings |
| ✅ DNS resolves to private IP | Kudu console: `nslookup <workspace-id>.ods.opinsights.azure.com` |

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| DNS resolves to public IP | DNS zones not linked to VNet | Link private DNS zones to VNet |
| 403 Forbidden from LAW | Missing RBAC | Grant "Log Analytics Reader" to Function's Managed Identity |
| Connection timeout | VNet routing not enabled | Set `WEBSITE_VNET_ROUTE_ALL=1` |
| Private Endpoint not working | Wrong group ID | Ensure group ID is `azuremonitor` |
| Function can't reach LAW | Subnet NSG blocking traffic | Allow outbound to `AzureMonitor` service tag |

---

## Network Security Considerations

| Traffic Path | Network | Security |
|--------------|---------|----------|
| SRE Agent → Function App | Public HTTPS | Function Key + TLS 1.2 |
| Function App → Log Analytics | Private (VNet) | Private Endpoint + Managed Identity |

The Function App's public endpoint is protected by:
- **Function Key** authentication (required for all requests)
- **TLS 1.2** encryption in transit
- Optional: IP restrictions, Azure AD authentication

If you require fully private access (SRE Agent → Function App), you would need:
1. Private Endpoint for the Function App
2. SRE Agent connected to a VNet that can reach the Function's Private Endpoint

---

## Related Resources

- [Azure Monitor Private Link documentation](https://docs.microsoft.com/azure/azure-monitor/logs/private-link-security)
- [Azure Functions VNet Integration](https://docs.microsoft.com/azure/azure-functions/functions-networking-options)
- [Private DNS Zone configuration](https://docs.microsoft.com/azure/private-link/private-endpoint-dns)
