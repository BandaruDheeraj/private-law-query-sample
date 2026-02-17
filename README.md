# Querying Private Log Analytics with Azure Functions (AMPLS Pattern)

![Status](https://img.shields.io/badge/Status-Tested-green) ![Pattern](https://img.shields.io/badge/Pattern-Azure%20Functions-blue) ![SDK](https://img.shields.io/badge/azure--monitor--query-v2.0.0-orange)

Demonstrate how Azure SRE Agent can query a Log Analytics Workspace protected by Azure Monitor Private Link Scope (AMPLS) using Azure Functions as a VNet-integrated query proxy.

> ✅ **Tested on January 21, 2026**: Full integration test passed with Azure Functions querying private LAW through AMPLS.

## Scenario Overview

**The Reality**: Log Analytics Workspaces cannot be created inside a VNet as a network resource. Azure Monitor uses public endpoints by default and requires **Azure Monitor Private Link Scopes (AMPLS)** together with **Private Endpoints** for private network access.

**What We Built**:
- **Originations Resource Group**: Contains the Log Analytics Workspace + AMPLS with public query access disabled
- **Workload Resource Group**: Contains the VNet, Private Endpoint, Azure Functions, and sample VMs

> 📝 **Note**: This sample deploys everything to a **single subscription** with two resource groups. The same pattern works identically across subscriptions—simply deploy each resource group to a different subscription and ensure cross-subscription RBAC is configured.

**The Problem**: When `publicNetworkAccessForQuery: Disabled` is set on the Log Analytics workspace, external queries (including from Azure SRE Agent) are blocked—even though your resources are sending logs.

**The Solution**: Deploy an Azure Function in the workload VNet that has Private Endpoint access to the LAW. SRE Agent calls the Function endpoints as custom HTTP tools, which query Log Analytics on behalf of the agent.

> 💡 **Note**: For an alternative approach using MCP (Model Context Protocol), see the [private-vnet-observability](../private-vnet-observability/) sample.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Originations Resource Group                             │
│                     (rg-originations-ampls-demo)                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    Log Analytics Workspace                              ││
│  │                                                                          ││
│  │  • publicNetworkAccessForQuery: Disabled                                ││
│  │  • publicNetworkAccessForIngestion: Enabled (or via AMPLS)              ││
│  │  • Connected to AMPLS with queryAccessMode: PrivateOnly                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                  │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │               Azure Monitor Private Link Scope (AMPLS)                  ││
│  │                                                                          ││
│  │  • Links: Log Analytics Workspace                                        ││
│  │  • Ingestion Access Mode: Open (or PrivateOnly)                         ││
│  │  • Query Access Mode: PrivateOnly                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │ Private Link Service
                                    │
┌───────────────────────────────────┼─────────────────────────────────────────┐
│                      Workload Resource Group                                │
│                      (rg-workload-ampls-demo)                               │
│  ┌─────────────────────────────────┼────────────────────────────────────────┐
│  │                     Virtual Network                                      │
│  │                                 │                                        │
│  │  ┌──────────────────────────────┴──────────────────────────────────────┐│
│  │  │               Private Endpoint (to AMPLS)                           ││
│  │  │  • Connects to Azure Monitor Private Link Scope                     ││
│  │  │  • DNS: privatelink.monitor.azure.com                               ││
│  │  │  • DNS: privatelink.oms.opinsights.azure.com                        ││
│  │  │  • DNS: privatelink.ods.opinsights.azure.com                        ││
│  │  └─────────────────────────────────────────────────────────────────────┘│
│  │                                                                          │
│  │  ┌───────────────────────────────────────────────────────────────────────┐
│  │  │                Azure Functions (VNet-Integrated)                      │
│  │  │                                                                       │
│  │  │  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  │  │          Log Analytics Query Functions                          │ │
│  │  │  │   • query_logs: Execute KQL queries                             │ │
│  │  │  │   • list_tables: List available tables                          │ │
│  │  │  │   • check_vm_health: Check VM health via Heartbeat              │ │
│  │  │  │   • analyze_errors: Analyze syslog errors                       │ │
│  │  │  │   • Queries LAW via Private Endpoint                            │ │
│  │  │  │   • Authenticates with Managed Identity                         │ │
│  │  │  └─────────────────────────────────────────────────────────────────┘ │
│  │  └───────────────────────────────────────────────────────────────────────┘
│  │                                                                          │
│  │  ┌───────────────────────────────────────────────────────────────────────┐
│  │  │                     Workload VMs                                      │
│  │  │  • app-vm, db-vm, web-vm                                             │
│  │  │  • Azure Monitor Agent sending logs to LAW                           │
│  │  │  • No public IPs                                                      │
│  │  └───────────────────────────────────────────────────────────────────────┘
│  └──────────────────────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (REST API + Easy Auth Bearer Token)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure SRE Agent                                     │
│                    (Outside the VNet)                                       │
│                                                                             │
│  "Investigate errors in my Originations LAW from the workload VMs"         │
│                                                                             │
│  ✓ Acquires Bearer Token via Managed Identity                              │
│  ✓ Calls Azure Function endpoints over HTTPS with token                    │
│  ✓ Function queries LAW via Private Endpoint                               │
│  ✓ Results returned to agent for analysis                                  │
│  ✓ No secrets or function keys required                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Insight: LAW Cannot Live in a VNet

**Important Clarification**: A Log Analytics Workspace **cannot be created inside a VNet** as a network resource. Azure Monitor (including Log Analytics) uses public endpoints by default.

To achieve private access:
1. Create an **Azure Monitor Private Link Scope (AMPLS)**
2. Link your Log Analytics Workspace to the AMPLS
3. Create a **Private Endpoint** in your VNet pointing to the AMPLS
4. Set `queryAccessMode: PrivateOnly` to block public queries

This is the architecture pattern used in enterprise scenarios like the Originations workspace.

## Prerequisites

- Azure subscription with Contributor access
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed (recommended)
- Azure Functions Core Tools (for local testing)

## Quick Start with azd

The entire sample can be deployed with a single command using Azure Developer CLI:

```bash
# Clone the sample repository
git clone https://github.com/BandaruDheeraj/private-law-query-sample
cd private-law-query-sample

# Deploy everything with a single command
azd up
```

This deploys to a **single subscription** with two resource groups:
- **rg-originations-{env}**: Log Analytics Workspace + AMPLS (private query access)
- **rg-workload-{env}**: VNet + Private Endpoint + Azure Functions + Sample VMs
- **Azure Function App**: 4 HTTP endpoints (query_logs, list_tables, check_vm_health, analyze_errors)
- **RBAC**: Managed Identity with Log Analytics Reader role

After deployment, `azd` outputs:
- `FUNCTION_APP_URL` - Use this URL in your SRE Agent PythonTools
- `FUNCTION_APP_NAME` - Use to configure Easy Auth in the Azure Portal

### Configure Easy Auth

After `azd up` completes, configure Easy Auth (Microsoft Entra ID) on the Function App:

1. Navigate to your **Function App** in the Azure Portal
2. Go to **Settings** → **Authentication** → **Add identity provider** → **Microsoft**
3. Configure single-tenant with HTTP 401 for unauthenticated requests
4. Add the SRE Agent's Managed Identity Client ID as an allowed client application
5. Note the **Application (client) ID** for your PythonTool configuration

See the [blog post](https://techcommunity.microsoft.com/blog/appsonazureblog/how-azure-sre-agent-can-investigate-resources-in-a-private-network/4494911) for detailed step-by-step instructions.

## Alternative: Step-by-Step Deployment

### What We Deployed

In our tested deployment, we created two resource groups in a single subscription:

| Resource Group | Resources Created |
|----------------|-------------------|
| `rg-originations-ampls-demo` | Log Analytics Workspace, AMPLS |
| `rg-workload-ampls-demo` | VNet, Private Endpoint, Azure Functions, Sample VMs |

#### 1. Deploy the Originations Resources

```powershell
# Create resource group
az group create --name rg-originations-ampls-demo --location eastus

# Deploy LAW + AMPLS using Bicep
az deployment group create \
  --resource-group rg-originations-ampls-demo \
  --template-file ./infra/modules/log-analytics.bicep \
  --parameters workspaceName=law-originations-ampls-demo
```

Creates:
- Log Analytics Workspace with `publicNetworkAccessForQuery: Disabled`
- Azure Monitor Private Link Scope with `queryAccessMode: PrivateOnly`

#### 2. Deploy the Workload Resources

```powershell
# Create resource group
az group create --name rg-workload-ampls-demo --location eastus

# Deploy VNet, PE, Functions, VMs using Bicep
az deployment group create \
  --resource-group rg-workload-ampls-demo \
  --template-file ./infra/modules/workload.bicep \
  --parameters vnetName=vnet-workload-ampls-demo \
               functionAppName=func-law-query-ampls-demo \
               workspaceResourceId="/subscriptions/.../workspaces/law-originations-ampls-demo"
```

Creates:
- Virtual Network with `functions` and `endpoints` subnets
- Private Endpoint connecting to the AMPLS
- Azure Functions (Elastic Premium EP1, VNet-integrated)
- Sample VMs (app-vm, db-vm, web-vm) with Azure Monitor Agent

#### 3. Grant RBAC for Cross-Resource-Group Access

```powershell
# Get the Function App's managed identity
$principalId = az functionapp identity show \
  --name func-law-query-ampls-demo \
  --resource-group rg-workload-ampls-demo \
  --query principalId -o tsv

# Grant Log Analytics Reader on the LAW in the other resource group
az role assignment create \
  --assignee $principalId \
  --role "Log Analytics Reader" \
  --scope "/subscriptions/.../resourceGroups/rg-originations-ampls-demo/providers/Microsoft.OperationalInsights/workspaces/law-originations-ampls-demo"
```

### 3. Inject the Failure

```powershell
./inject-failure.ps1 -ResourceGroup "workload-rg"
```

This simulates application issues on the workload VMs that will be logged to the Originations LAW.

### 4. Configure SRE Agent Subagent

Create a dedicated subagent for cross-subscription AMPLS queries. This subagent uses PythonTools that call the Azure Function endpoints, authenticated via Easy Auth (Entra ID Bearer Tokens).

#### Option A: Deploy via srectl CLI

Apply the YAML templates from this sample:

```powershell
# Apply tool definitions
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_QueryLogs.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_ListTables.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_CheckVMHealth.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_AnalyzeErrors.yaml

# Apply agent definition
srectl apply-yaml --file agents/EasyAuth/PrivateLAWQuery.yaml
```

#### Option B: Create via Azure Portal

Create the subagent and tools directly in the Azure Portal:

1. **Navigate to your SRE Agent** in the Azure Portal
2. Go to **Builder** → **Subagent builder**
3. Click **+ Create subagent** and fill in:
   - **Name**: `PrivateLAWQuery`
   - **Description**: Query Log Analytics workspaces protected by AMPLS via Easy Auth
   - **Tags**: `ampls`, `private-link`, `easy-auth`
4. Add the **Instructions** and **Handoff Description** from the YAML examples
5. Click **+ Add tool** to add each PythonTool
6. For each tool, paste the **Function Code** from the YAML files in the `agents/EasyAuth/` directory
7. Update the **Function App URL** and **App Registration Client ID** in each tool

> ⚠️ **Important PythonTool Requirement**: All PythonTools must use `def main(**kwargs)` as the function signature.

#### Configuring Easy Auth in PythonTools

In your PythonTool code, configure these values:

| Variable | Description | Where to Find It |
|----------|-------------|------------------|
| `function_url` | Endpoint URL for each function | Azure Portal → Function App → Overview → URL |
| `app_id` | App Registration Client ID | Azure Portal → Function App → Authentication → App (client) ID |

The PythonTool acquires a Bearer Token automatically using the SRE Agent's Managed Identity—no secrets to manage.

### 5. Test with SRE Agent

Open Azure SRE Agent and ask:

> "List the tables available in the Log Analytics workspace"

> "Query the last 24 hours of errors from the workload VMs"

> "Check the health of all VMs in the workspace"

> "Analyze errors from the past 48 hours"

### 6. Cleanup

```powershell
./cleanup.ps1 -ResourceGroup "workload-rg"
./cleanup.ps1 -ResourceGroup "originations-rg"
```

## What You'll Learn

- Why Log Analytics Workspaces can't be created inside VNets
- How Azure Monitor Private Link Scope (AMPLS) enables private query access
- Deploying Azure Functions with VNet integration for private resource access
- Using Private Endpoints to access AMPLS-protected workspaces
- Configuring SRE Agent PythonTools as serverless query proxy
- Separating concerns with resource groups (simulates cross-subscription pattern)

## Azure Functions vs MCP Approach

| Aspect | Azure Functions (this sample) | MCP Server |
|--------|-------------------------------|------------|
| **SRE Agent Integration** | Custom HTTP tools | MCP tool |
| **Protocol** | REST API | MCP Streamable HTTP |
| **Hosting** | Azure Functions (Elastic Premium) | Container Apps |
| **Authentication** | Easy Auth (Entra ID Bearer Token) | API Key |
| **Scaling** | Auto-scale (serverless) | Container-based |
| **Cold Start** | ~1-2 seconds | Always-on option |
| **Best For** | Simple query proxy | Rich tool ecosystem |

> 💡 See [private-vnet-observability](../private-vnet-observability/) for the MCP-based approach.

## Files in This Sample

| File | Description |
|------|-------------|
| `azure.yaml` | Azure Developer CLI manifest |
| `scripts/inject-failure.ps1` | Simulate application issues |
| `scripts/fix-issue.ps1` | Apply remediation |
| `scripts/cleanup.ps1` | Delete all resources |
| `infra/` | Bicep infrastructure modules |
| `src/log-analytics-function/` | Azure Functions source code |

## SRE Agent Integration Files

| File | Description |
|------|-------------|
| `agents/EasyAuth/PrivateLAWQuery.yaml` | Subagent definition (Easy Auth) |
| `agents/EasyAuth/PrivateLAW_QueryLogs.yaml` | Execute KQL queries tool |
| `agents/EasyAuth/PrivateLAW_ListTables.yaml` | List tables tool |
| `agents/EasyAuth/PrivateLAW_CheckVMHealth.yaml` | Check VM health tool |
| `agents/EasyAuth/PrivateLAW_AnalyzeErrors.yaml` | Analyze errors tool |

## Estimated Cost

| Resource | Hourly Cost | Notes |
|----------|-------------|-------|
| Functions (EP1) | ~$0.12 | Elastic Premium plan |
| Log Analytics ingestion | ~$0.10 | Based on log volume |
| Private Endpoints | ~$0.01 | Per endpoint per hour |
| VMs (3 × B2s) | ~$0.12 | For demo workloads |
| **Total** | ~$0.35/hour | For demo duration |

> 💡 **Tip**: Run cleanup immediately after the demo to minimize costs.

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| 🔐 **Query Access** | LAW blocks public queries via AMPLS `queryAccessMode: PrivateOnly` |
| 🔗 **Private Access** | Private Endpoint in workload VNet connects to AMPLS in originations RG |
| 🪪 **Authentication** | Function App uses Managed Identity for Azure auth (cross-RG RBAC) |
| 🔑 **API Protection** | Easy Auth (Entra ID) with Bearer Token—no secrets to manage |
| 📝 **Audit Trail** | All function invocations logged in Application Insights |
| 🌐 **VNet Routing** | `vnetRouteAllEnabled: true` ensures all traffic goes through VNet |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `NameError: main is not defined` | PythonTool uses `def execute` | Change to `def main(**kwargs)` |
| `HTTP 401 Unauthorized` | Easy Auth rejecting the token | Verify the SRE Agent's MI Client ID is in the allowed client applications |
| `HTTP 403 Forbidden` | Missing Log Analytics Reader role | Grant role to Function App's managed identity on the **workspace** (not the function app's RG) |
| `0 tables returned` | Workspace has no data ingestion | Connect data sources and wait for ingestion |
| `Connection failed` | VNet integration not working | Verify `vnetRouteAllEnabled: true` |
| `Failed to acquire token` | Managed identity not available | Verify `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are set in the PythonTool sandbox |

### Verifying Tool Deployment

Verify your tools are deployed via the Azure Portal:

1. Navigate to your **Azure SRE Agent** resource
2. Go to **Builder** → **Subagent builder**
3. Click on your **PrivateLAWQuery** subagent
4. Verify all 4 tools are listed:
   - PrivateLAW_QueryLogs
   - PrivateLAW_ListTables
   - PrivateLAW_CheckVMHealth
   - PrivateLAW_AnalyzeErrors
5. Test by starting a new chat and asking: "Use PrivateLAWQuery to list tables"

## SDK Compatibility

This sample uses `azure-monitor-query>=2.0.0`. The SDK had a breaking change in v2.0.0 where column names are returned as strings instead of objects:

```python
# Handles both old and new azure-monitor-query formats
columns = table.columns if isinstance(table.columns[0], str) else [col.name for col in table.columns]
```

## Azure Policy Considerations

The sample's storage account includes `allowBlobPublicAccess: false` to comply with common enterprise policies. If your subscription has additional policies, you may need to adjust:

| Policy | Sample Configuration |
|--------|----------------------|
| Storage public access | `allowBlobPublicAccess: false` ✅ |
| HTTPS only | `supportsHttpsTrafficOnly: true` ✅ |
| TLS version | `minimumTlsVersion: TLS1_2` ✅ |

## Related Resources

- [Azure Monitor Private Link documentation](https://docs.microsoft.com/azure/azure-monitor/logs/private-link-security)
- [Azure Functions VNet Integration](https://docs.microsoft.com/azure/azure-functions/functions-networking-options)
- [Private VNet Observability Sample (MCP approach)](../private-vnet-observability/)
