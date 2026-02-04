# Querying Private Log Analytics with Azure Functions (AMPLS Pattern)

![Status](https://img.shields.io/badge/Status-Tested-green) ![Pattern](https://img.shields.io/badge/Pattern-Azure%20Functions-blue) ![SDK](https://img.shields.io/badge/azure--monitor--query-v2.0.0-orange)

Demonstrate how Azure SRE Agent can query a Log Analytics Workspace protected by Azure Monitor Private Link Scope (AMPLS) using Azure Functions as a VNet-integrated query proxy.

> ✅ **Tested on January 21, 2026**: Full integration test passed with Azure Functions querying private LAW through AMPLS.

---

## 📍 Quick Reference: Key File Locations

| What You Need | Location | Description |
|---------------|----------|-------------|
| **🔧 Azure Function Code** | [`src/log-analytics-function/`](src/log-analytics-function/) | Python Azure Functions that query Log Analytics via Private Endpoint |
| **🤖 Subagent YAML** | [`src/log-analytics-function/agents/CrossSubscriptionAMPLS/`](src/log-analytics-function/agents/CrossSubscriptionAMPLS/CrossSubscriptionAMPLS.yaml) | Copy this YAML into the **Subagent Builder UI** in Azure SRE Agent |
| **🛠️ PythonTool Examples** | See [Creating Custom PythonTools](#creating-custom-pythontools-in-sre-agent) section below | Code examples for creating HTTP tools in the SRE Agent UI |

### Function Endpoints (Azure Functions Code)

| Function | File | Purpose |
|----------|------|---------|
| `query_logs` | [`src/log-analytics-function/query_logs/__init__.py`](src/log-analytics-function/query_logs/__init__.py) | Execute KQL queries against Log Analytics |
| `list_tables` | [`src/log-analytics-function/list_tables/__init__.py`](src/log-analytics-function/list_tables/__init__.py) | List available tables in the workspace |
| `check_vm_health` | [`src/log-analytics-function/check_vm_health/__init__.py`](src/log-analytics-function/check_vm_health/__init__.py) | Check VM heartbeat status |
| `analyze_errors` | [`src/log-analytics-function/analyze_errors/__init__.py`](src/log-analytics-function/analyze_errors/__init__.py) | Analyze Syslog errors |

---

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
                                    │ HTTPS (REST API + Function Key)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure SRE Agent                                     │
│                    (Outside the VNet)                                       │
│                                                                             │
│  "Investigate errors in my Originations LAW from the workload VMs"         │
│                                                                             │
│  ✓ Calls Azure Function endpoints over HTTPS                               │
│  ✓ Function queries LAW via Private Endpoint                               │
│  ✓ Results returned to agent for analysis                                  │
│  ✓ No direct VNet or LAW access required                                   │
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
- `FUNCTION_APP_NAME` - Use to retrieve the Function Key from Azure Portal

### Get the Function Key

After `azd up` completes, retrieve the Function Key:

```powershell
# Get the function key for authentication
az functionapp keys list \
  --name <FUNCTION_APP_NAME> \
  --resource-group <WORKLOAD_RESOURCE_GROUP> \
  --query functionKeys.default -o tsv
```

Or via Azure Portal: **Function App** → **App keys** → **Host keys** → **default**

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
./scripts/inject-failure.ps1 -ResourceGroup "workload-rg"
```

This simulates application issues on the workload VMs that will be logged to the Originations LAW.

### 4. Configure SRE Agent Subagent

Create a dedicated subagent for cross-subscription AMPLS queries. This subagent uses PythonTools that call the Azure Function endpoints.

#### Option A: Create via Azure Portal

Create the subagent and tools directly in the Azure Portal:

1. **Navigate to your SRE Agent** in the Azure Portal
2. Go to **Builder** → **Subagent builder**
3. Click **+ Create subagent** and fill in:
   - **Name**: `CrossSubscriptionAMPLS`
   - **Description**: Query Log Analytics workspaces protected by AMPLS
   - **Tags**: `ampls`, `cross-subscription`, `private-link`
4. Add the **Instructions** and **Handoff Description** from the YAML examples in this sample
5. Click **+ Add tool** to add each PythonTool:
   - `CrossSubAMPLS_QueryLogs` - Execute KQL queries
   - `CrossSubAMPLS_ListTables` - List available tables
   - `CrossSubAMPLS_CheckVMHealth` - Check VM health
   - `CrossSubAMPLS_AnalyzeErrors` - Analyze errors
6. For each tool, paste the **Function Code** from the YAML files in this sample
7. Configure the **Function URL** and **Function Key** in the tool code:
   - Function URL: `https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/<endpoint>`
   - Function Key: Get from Azure Portal → Function App → App keys

> ⚠️ **Important PythonTool Requirement**: All PythonTools must use `def main(**kwargs)` as the function signature. Using `def execute(**kwargs)` will result in runtime errors.

#### Option B: Use YAML Templates

Reference the YAML template in [`src/log-analytics-function/agents/CrossSubscriptionAMPLS/CrossSubscriptionAMPLS.yaml`](src/log-analytics-function/agents/CrossSubscriptionAMPLS/CrossSubscriptionAMPLS.yaml) for the complete subagent configuration. Copy the contents into the Subagent Builder UI.

#### Configuring Function URL and Key

In your PythonTool code, configure these values:

| Variable | Description | Where to Find It |
|----------|-------------|------------------|
| `CROSS_SUB_AMPLS_FUNCTION_URL` | Base URL for each endpoint | Azure Portal → Function App → Overview → URL |
| `CROSS_SUB_AMPLS_FUNCTION_KEY` | Azure Function API key | Azure Portal → Function App → App keys → Host keys |

**Example URLs for each tool:**

| Tool | Endpoint |
|------|----------|
| QueryLogs | `https://<your-function-app>.azurewebsites.net/api/query_logs` |
| ListTables | `https://<your-function-app>.azurewebsites.net/api/list_tables` |
| CheckVMHealth | `https://<your-function-app>.azurewebsites.net/api/check_vm_health` |
| AnalyzeErrors | `https://<your-function-app>.azurewebsites.net/api/analyze_errors` |

#### Subagent Handoff Behavior

When a user asks:
> "Get my logs for a resource that is within the private network"

The meta_agent will recognize this as a private LAW query scenario and hand off to the `CrossSubscriptionAMPLS` subagent based on the handoff description:

> "Hand off to this agent when the user needs to query Log Analytics workspaces protected by Azure Monitor Private Link Scope (AMPLS) with private-only access."

The subagent then uses the PythonTools to call the Azure Function, which queries the private LAW via Private Endpoint.

### 5. Test with SRE Agent

Open Azure SRE Agent and ask:

> "List the tables available in the Log Analytics workspace"

> "Query the last 24 hours of errors from the workload VMs"

> "Check the health of all VMs in the workspace"

> "Analyze errors from the past 48 hours"

### 6. Cleanup

```powershell
./scripts/cleanup.ps1 -ResourceGroup "workload-rg"
./scripts/cleanup.ps1 -ResourceGroup "originations-rg"
```

## What You'll Learn

- Why Log Analytics Workspaces can't be created inside VNets
- How Azure Monitor Private Link Scope (AMPLS) enables private query access
- Deploying Azure Functions with VNet integration for private resource access
- Using Private Endpoints to access AMPLS-protected workspaces
- Configuring SRE Agent PythonTools as serverless query proxy
- Separating concerns with resource groups (simulates cross-subscription pattern)

## Creating Custom PythonTools in SRE Agent

This section provides everything you need to create custom PythonTools in the Azure SRE Agent UI Builder.

### Step 1: Navigate to the Tool Builder

1. Open the **Azure Portal** and navigate to your **Azure SRE Agent** resource
2. Go to **Builder** → **Subagent builder**
3. Select your subagent (or create one first)
4. Click **+ Add tool** → **PythonTool**

### Step 2: Tool Configuration Fields

When creating a PythonTool, you'll need to fill in these fields:

| Field | Description | Example |
|-------|-------------|---------|
| **Name** | Unique tool identifier (snake_case recommended) | `CrossSubAMPLS_QueryLogs` |
| **Description** | What the tool does (LLM uses this to decide when to call it) | `Execute KQL queries against a private Log Analytics workspace via Azure Function proxy` |
| **Parameters** | Input parameters the tool accepts (JSON schema) | See below |
| **Function Code** | Python code with `def main(**kwargs)` entry point | See examples below |

### Step 3: Parameter Definition

Define parameters as a JSON schema. Example for the QueryLogs tool:

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "The KQL query to execute against Log Analytics"
    },
    "timespan": {
      "type": "string",
      "description": "ISO 8601 duration (e.g., PT1H, P1D, P7D). Default: P1D"
    }
  },
  "required": ["query"]
}
```

### Step 4: Function Code Template

All PythonTools **must** use `def main(**kwargs)` as the entry point:

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    """
    Query Log Analytics workspace via Azure Function proxy.
    
    Args:
        query (str): KQL query to execute
        timespan (str, optional): ISO 8601 duration like "PT1H", "P1D"
    
    Returns:
        dict: Query results or error message
    """
    # Extract parameters
    query = kwargs.get("query")
    timespan = kwargs.get("timespan", "P1D")
    
    if not query:
        return {"error": "Missing required parameter: query"}
    
    # Azure Function configuration
    # ⚠️ Replace these with your actual values after deployment
    FUNCTION_URL = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/query_logs"
    FUNCTION_KEY = "<YOUR-FUNCTION-KEY>"
    
    # Build request
    payload = json.dumps({
        "query": query,
        "timespan": timespan
    }).encode("utf-8")
    
    headers = {
        "Content-Type": "application/json",
        "x-functions-key": FUNCTION_KEY
    }
    
    try:
        req = urllib.request.Request(FUNCTION_URL, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=60) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.reason}", "details": e.read().decode()}
    except urllib.error.URLError as e:
        return {"error": f"Connection failed: {str(e.reason)}"}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}
```

### Complete PythonTool Examples

#### CrossSubAMPLS_QueryLogs

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    """Execute KQL queries against private Log Analytics workspace."""
    query = kwargs.get("query")
    timespan = kwargs.get("timespan", "P1D")
    
    if not query:
        return {"error": "Missing required parameter: query"}
    
    FUNCTION_URL = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/query_logs"
    FUNCTION_KEY = "<YOUR-FUNCTION-KEY>"
    
    payload = json.dumps({"query": query, "timespan": timespan}).encode("utf-8")
    headers = {"Content-Type": "application/json", "x-functions-key": FUNCTION_KEY}
    
    try:
        req = urllib.request.Request(FUNCTION_URL, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        return {"error": str(e)}
```

#### CrossSubAMPLS_ListTables

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    """List available tables in the private Log Analytics workspace."""
    FUNCTION_URL = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/list_tables"
    FUNCTION_KEY = "<YOUR-FUNCTION-KEY>"
    
    headers = {"x-functions-key": FUNCTION_KEY}
    
    try:
        req = urllib.request.Request(FUNCTION_URL, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        return {"error": str(e)}
```

#### CrossSubAMPLS_CheckVMHealth

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    """Check VM heartbeat and connectivity status."""
    FUNCTION_URL = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/check_vm_health"
    FUNCTION_KEY = "<YOUR-FUNCTION-KEY>"
    
    headers = {"x-functions-key": FUNCTION_KEY}
    
    try:
        req = urllib.request.Request(FUNCTION_URL, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        return {"error": str(e)}
```

#### CrossSubAMPLS_AnalyzeErrors

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    """Analyze Syslog errors from the workspace."""
    hours = kwargs.get("hours", 24)
    
    FUNCTION_URL = f"https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/analyze_errors?hours={hours}"
    FUNCTION_KEY = "<YOUR-FUNCTION-KEY>"
    
    headers = {"x-functions-key": FUNCTION_KEY}
    
    try:
        req = urllib.request.Request(FUNCTION_URL, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        return {"error": str(e)}
```

### Important PythonTool Rules

| Rule | Description |
|------|-------------|
| ✅ Use `def main(**kwargs)` | Required entry point signature |
| ❌ Don't use `def execute()` | Will cause runtime errors |
| ✅ Return `dict` or JSON-serializable | Results must be JSON-compatible |
| ✅ Handle all exceptions | Wrap calls in try/except |
| ✅ Use `urllib` for HTTP | Available in the sandbox environment |
| ❌ Don't use `requests` library | Not available in sandbox |
| ✅ Include timeouts | Prevent hanging on slow responses |

### Where to Get Your Configuration Values

| Value | How to Find It |
|-------|----------------|
| **Function App URL** | Azure Portal → Function App → Overview → URL |
| **Function Key** | Azure Portal → Function App → App keys → Host keys → default |
| **Workspace ID** | Azure Portal → Log Analytics Workspace → Properties → Workspace ID |

---

## Azure Functions vs MCP Approach

| Aspect | Azure Functions (this sample) | MCP Server |
|--------|-------------------------------|------------|
| **SRE Agent Integration** | Custom HTTP tools | MCP tool |
| **Protocol** | REST API | MCP Streamable HTTP |
| **Hosting** | Azure Functions (Elastic Premium) | Container Apps |
| **Authentication** | Function Key | API Key |
| **Scaling** | Auto-scale (serverless) | Container-based |
| **Cold Start** | ~1-2 seconds | Always-on option |
| **Best For** | Simple query proxy | Rich tool ecosystem |

> 💡 See [private-vnet-observability](../private-vnet-observability/) for the MCP-based approach.

## Files in This Sample

| File | Description |
|------|-------------|
| `azure.yaml` | Azure Developer CLI manifest |
| `deploy-sample.ps1` | Full environment deployment |
| `inject-failure.ps1` | Simulate application issues |
| `fix-issue.ps1` | Apply remediation |
| `cleanup.ps1` | Delete all resources |
| `infra/` | Bicep infrastructure modules |
| `src/log-analytics-function/` | Azure Functions source code |
| `blog-post.md` | Full tutorial article |

## SRE Agent Integration Files

| File | Description |
|------|-------------|
| `agents/CrossSubscriptionAMPLS/CrossSubscriptionAMPLS.yaml` | Subagent definition |
| `tools/CrossSubAMPLS_QueryLogs/CrossSubAMPLS_QueryLogs.yaml` | Execute KQL queries tool |
| `tools/CrossSubAMPLS_ListTables/CrossSubAMPLS_ListTables.yaml` | List tables tool |
| `tools/CrossSubAMPLS_CheckVMHealth/CrossSubAMPLS_CheckVMHealth.yaml` | Check VM health tool |
| `tools/CrossSubAMPLS_AnalyzeErrors/CrossSubAMPLS_AnalyzeErrors.yaml` | Analyze errors tool |

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
| 🔑 **API Protection** | Function endpoints require Function Key authentication |
| 📝 **Audit Trail** | All function invocations logged in Application Insights |
| 🌐 **VNet Routing** | `vnetRouteAllEnabled: true` ensures all traffic goes through VNet |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `NameError: main is not defined` | PythonTool uses `def execute` | Change to `def main(**kwargs)` |
| `HTTP 401 Unauthorized` | Invalid or missing function key | Verify the function key is correct |
| `HTTP 403 Forbidden` | Missing Log Analytics Reader role | Grant role to Function App's managed identity |
| `0 tables returned` | Workspace has no data ingestion | Connect data sources and wait for ingestion |
| `Connection failed` | VNet integration not working | Verify `vnetRouteAllEnabled: true` |

### Verifying Tool Deployment

Verify your tools are deployed via the Azure Portal:

1. Navigate to your **Azure SRE Agent** resource
2. Go to **Builder** → **Subagent builder**
3. Click on your **CrossSubscriptionAMPLS** subagent
4. Verify all 4 tools are listed:
   - CrossSubAMPLS_QueryLogs
   - CrossSubAMPLS_ListTables
   - CrossSubAMPLS_CheckVMHealth
   - CrossSubAMPLS_AnalyzeErrors
5. Test by starting a new chat and asking: "Use CrossSubscriptionAMPLS to list tables"

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

