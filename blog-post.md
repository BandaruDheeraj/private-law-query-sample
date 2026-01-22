# Querying Private Log Analytics with Azure Functions: The AMPLS Pattern

> ✅ **Tested**: This pattern has been fully deployed and verified working on January 21, 2026.

> **SDK Note**: This sample uses `azure-monitor-query>=2.0.0`. The SDK v2.0.0 introduced breaking changes to the column access pattern. The sample code handles this by iterating through table columns using `table.columns` with dynamic attribute access.

## TL;DR

A Log Analytics Workspace **cannot be created inside a VNet**—it's a PaaS service with public endpoints. For private access, use **Azure Monitor Private Link Scope (AMPLS)** with Private Endpoints. When queries are blocked by Private Link, deploy **Azure Functions inside your VNet** as a query proxy for Azure SRE Agent.

> 📝 **What We Built**: This sample deploys to a **single subscription** with two resource groups (`rg-originations-*` and `rg-workload-*`). The same pattern works identically across subscriptions—simply deploy each resource group to a different subscription.

---

## The Misconception

> *"Just put the Log Analytics Workspace in the VNet subnet."*

This sounds intuitive, but **it's not how Azure Monitor works**.

| Resource Type | Can Live in VNet? | How to Access Privately |
|--------------|:-----------------:|-------------------------|
| Virtual Machine | ✅ Yes | Direct—it has a NIC |
| Container App | ✅ Yes | VNet integration |
| Azure SQL | ❌ No | Private Endpoint |
| Storage Account | ❌ No | Private Endpoint |
| **Log Analytics Workspace** | ❌ **No** | **AMPLS + Private Endpoint** |

Log Analytics Workspaces (and most Azure PaaS services) don't have NICs, don't get IP addresses from subnets, and can't be "placed" inside a VNet. They use **public endpoints by default**.

To achieve private network access, you need: **Azure Monitor Private Link Scope (AMPLS)** together with **Private Endpoints**.

---

## The Architecture: Separating Concerns with Resource Groups

In this sample, we separate logging infrastructure from workloads using resource groups (simulating how enterprises often separate these across subscriptions):

### Originations Resource Group (`rg-originations-ampls-demo`)

| Component | Configuration |
|-----------|---------------|
| Log Analytics Workspace | `law-originations-ampls-demo` |
| Public Query Access | **Disabled** |
| Public Ingestion Access | Enabled |
| AMPLS | `queryAccessMode: PrivateOnly` |

### Workload Resource Group (`rg-workload-ampls-demo`)

| Component | Configuration |
|-----------|---------------|
| Virtual Network | `vnet-workload-ampls-demo` with 2 subnets |
| Private Endpoint | Connects to AMPLS in originations RG |
| Azure Function | `func-law-query-ampls-demo` (VNet-integrated) |
| Workload VMs | app-vm, db-vm, web-vm with Azure Monitor Agent |

> 💡 **Cross-Subscription Note**: This same pattern works across subscriptions. Deploy each resource group to a different subscription and configure cross-subscription RBAC for the Function's Managed Identity.

---

## The Problem: Blocked Queries

When you configure:
- `publicNetworkAccessForQuery: Disabled` on the LAW
- `queryAccessMode: PrivateOnly` on the AMPLS

**All external queries are blocked**—including those from Azure SRE Agent (which runs as a cloud service, not in your VNet).

Try querying from outside the VNet and you'll see:

```
❌ InsufficientAccessError: The query was blocked due to private link 
   configuration. Access is denied because this request was not made 
   through a private endpoint.
```

---

## The Solution: Azure Functions as Query Proxy

Deploy **Azure Functions inside the workload VNet**. This serverless proxy:

| Capability | Description |
|------------|-------------|
| 🏠 **Runs inside VNet** | VNet-integrated with `vnetRouteAllEnabled: true` |
| 🔑 **Uses Managed Identity** | Authenticates to LAW via Azure RBAC |
| 🌐 **Exposes HTTPS endpoints** | SRE Agent calls as custom HTTP tools |
| 🔍 **Proxies queries** | Transforms API calls into KQL queries |
| ⚡ **Serverless scaling** | Pay only when queries are executed |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                ORIGINATIONS RESOURCE GROUP (rg-originations-ampls-demo)     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    Log Analytics Workspace                              ││
│  │                                                                          ││
│  │  • publicNetworkAccessForQuery: Disabled                                ││
│  │  • publicNetworkAccessForIngestion: Enabled                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                  │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │               Azure Monitor Private Link Scope (AMPLS)                  ││
│  │                                                                          ││
│  │  • queryAccessMode: PrivateOnly ← Blocks all public queries            ││
│  │  • ingestionAccessMode: Open                                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │ Private Link Service
                                    ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                WORKLOAD RESOURCE GROUP (rg-workload-ampls-demo)               │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         Virtual Network                                  │ │
│  │                                                                          │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │ │
│  │  │              Private Endpoint (to AMPLS)                          │   │ │
│  │  │  • DNS: privatelink.oms.opinsights.azure.com                      │   │ │
│  │  │  • DNS: privatelink.monitor.azure.com                             │   │ │
│  │  └───────────────────────────┬──────────────────────────────────────┘   │ │
│  │                              │                                          │ │
│  │  ┌───────────────────────────┴──────────────────────────────────────┐   │ │
│  │  │              Azure Functions (VNet-Integrated)                    │   │ │
│  │  │                                                                    │   │ │
│  │  │  ┌────────────────────────────────────────────────────────────┐   │   │ │
│  │  │  │           Log Analytics Query Functions                     │   │   │ │
│  │  │  │   • query_logs: Execute KQL queries                         │   │   │ │
│  │  │  │   • list_tables: List available tables                      │   │   │ │
│  │  │  │   • check_vm_health: Check Heartbeat status                 │   │   │ │
│  │  │  │   • analyze_errors: Find error patterns                     │   │   │ │
│  │  │  │   • Queries LAW via Private Endpoint ✅                     │   │   │ │
│  │  │  │   • Authenticates with Managed Identity                     │   │   │ │
│  │  │  └────────────────────────────────────────────────────────────┘   │   │ │
│  │  └───────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                          │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐   │ │
│  │  │                    Workload VMs                                    │   │ │
│  │  │  • app-vm, db-vm, web-vm                                          │   │ │
│  │  │  • Azure Monitor Agent → sends logs to LAW                        │   │ │
│  │  │  • No public IPs                                                   │   │ │
│  │  └───────────────────────────────────────────────────────────────────┘   │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (REST API + Function Key)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure SRE Agent                                     │
│                    (Outside the VNet)                                       │
│                                                                             │
│  "Investigate errors on my workload VMs in the Originations LAW"           │
│                                                                             │
│  ✓ Calls Azure Function endpoints over HTTPS                               │
│  ✓ Function queries LAW via Private Endpoint                               │
│  ✓ Results returned to agent for analysis                                  │
│  ✓ No direct VNet or LAW access required                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## How the Data Flows: Step by Step

Understanding the exact data flow is key to this pattern. Here's how a query travels from SRE Agent to Log Analytics:

```
Azure SRE Agent (cloud service, outside VNet)
        │
        │ HTTPS call with Function Key
        ▼
Azure Function (func-law-query-ampls-demo)
        │
        │ ← VNet-integrated into "functions" subnet
        │ ← vnetRouteAllEnabled: true (all traffic routes through VNet)
        │ ← Uses Managed Identity for auth
        │
        ▼
Private Endpoint (in "endpoints" subnet)
        │
        │ ← Connects to AMPLS in originations RG
        │ ← DNS: privatelink.oms.opinsights.azure.com
        │
        ▼
AMPLS (Azure Monitor Private Link Scope)
        │
        │ ← queryAccessMode: PrivateOnly
        │
        ▼
Log Analytics Workspace (law-originations-ampls-demo)
        │
        │ ← publicNetworkAccessForQuery: Disabled
        │
        ✅ Query succeeds (came from Private Endpoint)
```

### Component Roles

| Component | Location | Role |
|-----------|----------|------|
| **Azure Function** | Inside VNet (`functions` subnet) | Query proxy with public HTTPS endpoint and Managed Identity for LAW auth |
| **Private Endpoint** | Inside VNet (`endpoints` subnet) | Connects to AMPLS, enables private network path to Log Analytics |
| **AMPLS** | Originations RG | Links LAW to Private Endpoint, enforces PrivateOnly query mode |
| **LAW** | Originations RG | Stores logs, blocks public queries, allows Private Endpoint queries |
| **SRE Agent PythonTool** | Cloud (outside VNet) | Makes HTTP calls to Azure Function using Function Key |

### The Key Insight

The Azure Function acts as a **bridge** between two networks:

1. **Public side**: The Function has a public HTTPS endpoint (`https://func-law-query-ampls-demo.azurewebsites.net`) that SRE Agent can call from anywhere
2. **Private side**: The Function's VNet integration routes all outbound traffic through the VNet, where the Private Endpoint provides access to AMPLS-protected Log Analytics

This is why the pattern works—the Function "translates" public API calls into private network queries.

---

## Why This Pattern Works

**Data ingestion** and **query access** use different network paths:

| Operation | Direction | Network | Status |
|-----------|-----------|---------|:------:|
| 📥 Log Ingestion | AMA → Private Endpoint → LAW | Private | ✅ Works |
| ❌ External Query | Public Internet → LAW | Public | ❌ Blocked |
| ✅ VNet Query | VNet → Private Endpoint → LAW | Private | ✅ Works |
| ✅ SRE Agent Query | HTTPS → Function → PE → LAW | Hybrid | ✅ Works |

---

## Setting Up the Architecture

### Step 1: Configure the Originations LAW

Create the Log Analytics Workspace with public query access disabled:

```powershell
# Create Log Analytics Workspace
az monitor log-analytics workspace create `
  --resource-group originations-rg `
  --workspace-name originations-law `
  --location eastus

# Disable public query access
az monitor log-analytics workspace update `
  --resource-group originations-rg `
  --workspace-name originations-law `
  --set properties.publicNetworkAccessForQuery=Disabled
```

---

### Step 2: Create the Azure Monitor Private Link Scope

```powershell
# Create AMPLS
az monitor private-link-scope create `
  --name originations-ampls `
  --resource-group originations-rg

# Link the workspace to AMPLS
az monitor private-link-scope scoped-resource create `
  --name law-link `
  --resource-group originations-rg `
  --scope-name originations-ampls `
  --linked-resource "/subscriptions/.../workspaces/originations-law"

# Set to Private Only (block public queries)
az monitor private-link-scope update `
  --name originations-ampls `
  --resource-group originations-rg `
  --query-access PrivateOnly
```

---

### Step 3: Create the Private Endpoint in Workload Resource Group

```powershell
# Create a Private Endpoint in the workload RG connecting to AMPLS in originations RG
az network private-endpoint create `
  --name pe-ampls `
  --resource-group rg-workload-ampls-demo `
  --vnet-name vnet-workload-ampls-demo `
  --subnet endpoints `
  --private-connection-resource-id "/subscriptions/.../resourceGroups/rg-originations-ampls-demo/providers/Microsoft.Insights/privateLinkScopes/ampls-originations-ampls-demo" `
  --group-id azuremonitor `
  --connection-name ampls-connection
```

---

### Step 4: Deploy the Azure Function

Deploy the Log Analytics query functions with VNet integration:

```powershell
# Create Elastic Premium plan for VNet integration
az functionapp plan create `
  --name plan-law-query `
  --resource-group workload-rg `
  --location eastus `
  --sku EP1 `
  --is-linux true

# Create Function App with VNet integration
az functionapp create `
  --name func-law-query `
  --resource-group workload-rg `
  --plan plan-law-query `
  --storage-account stfuncdata `
  --runtime python `
  --runtime-version 3.11 `
  --functions-version 4 `
  --assign-identity '[system]'

# Integrate with VNet
az functionapp vnet-integration add `
  --name func-law-query `
  --resource-group workload-rg `
  --vnet workload-vnet `
  --subnet functions

# Enable VNet route all
az resource update `
  --resource-group workload-rg `
  --name func-law-query `
  --resource-type Microsoft.Web/sites `
  --set properties.vnetRouteAllEnabled=true

# Grant Log Analytics Reader role
az role assignment create `
  --assignee-object-id $(az functionapp identity show ...) `
  --role "Log Analytics Reader" `
  --scope /subscriptions/.../workspaces/originations-law
```

---

### Step 5: Configure SRE Agent Subagent

Create a specialized subagent that uses the Azure Function endpoints. This subagent will be invoked when users ask about querying private Log Analytics workspaces.

#### Subagent Definition

Create the subagent YAML file in your agents directory:

```yaml
api_version: azuresre.ai/v2
kind: ExtendedAgent
metadata:
  name: PrivateLAWQuery
  tags:
    - ampls
    - private-link
    - log-analytics
spec:
  instructions: |
    You are a specialized Site Reliability Engineer focused on querying Log Analytics 
    workspaces that are protected by Azure Monitor Private Link Scope (AMPLS) with 
    private-only query access mode.
    
    ## Architecture Pattern
    This agent uses an Azure Function deployed in a VNet as a query proxy:
    
    SRE Agent → Azure Function (VNet-integrated) → Private Endpoint → AMPLS → LAW
    
    ## Available Tools
    - PrivateLAW_QueryLogs: Execute KQL queries
    - PrivateLAW_ListTables: List available tables
    - PrivateLAW_CheckVMHealth: Check VM heartbeat status
    - PrivateLAW_AnalyzeErrors: Analyze error trends
    
  handoffDescription: |
    Hand off to this agent when the user needs to query Log Analytics workspaces 
    protected by Azure Monitor Private Link Scope (AMPLS) with private-only access.
    This agent uses an Azure Function as a VNet-integrated query proxy.
    
  tools:
    - PrivateLAW_QueryLogs
    - PrivateLAW_ListTables
    - PrivateLAW_CheckVMHealth
    - PrivateLAW_AnalyzeErrors
```

#### Tool Definitions (PythonTools)

Each tool calls the Azure Function endpoints using HTTP.

> ⚠️ **Critical**: PythonTools **must** use `def main(**kwargs)` as the function signature. Using `def execute(**kwargs)` will result in `NameError: main is not defined`.

```yaml
# PrivateLAW_QueryLogs.yaml
api_version: azuresre.ai/v2
kind: ExtendedAgentTool
metadata:
  name: PrivateLAW_QueryLogs
  tags:
    - ampls
    - private-link
spec:
  type: PythonTool
  toolMode: Auto
  description: Execute KQL queries against a private Log Analytics workspace via AMPLS
  functionCode: |
    import json
    import urllib.request
    import urllib.error
    import os
    
    def main(**kwargs):  # IMPORTANT: Must be 'main', not 'execute'
        query = kwargs.get('query', '')
        timespan = kwargs.get('timespan', 'P1D')
        
        if not query:
            return {"error": "Query parameter is required"}
        
        # Get configuration from environment variables
        # Replace with your Azure Function URL and key
        function_url = os.environ.get('CROSS_SUB_AMPLS_FUNCTION_URL', 
            'https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/query_logs')
        function_key = os.environ.get('CROSS_SUB_AMPLS_FUNCTION_KEY', 
            '<YOUR-FUNCTION-KEY>')
        
        headers = {
            'Content-Type': 'application/json',
            'x-functions-key': function_key
        }
        body = json.dumps({'query': query, 'timespan': timespan}).encode('utf-8')
        
        try:
            req = urllib.request.Request(function_url, data=body, headers=headers, method='POST')
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else str(e)
            return {"error": f"HTTP {e.code}: {error_body}", "status": "failed"}
        except Exception as e:
            return {"error": f"Unexpected error: {str(e)}", "status": "failed"}
  parameters:
    - name: query
      type: string
      description: The KQL query to execute
      required: true
    - name: timespan
      type: string
      description: ISO 8601 duration (PT1H, P1D, P7D)
      required: false
```

#### Environment Variables

Configure the SRE Agent environment with the Function URL and API key:

| Variable | Description | Example |
|----------|-------------|---------|
| `CROSS_SUB_AMPLS_FUNCTION_URL` | Azure Function base URL | `https://func-law-query.azurewebsites.net/api/query_logs` |
| `CROSS_SUB_AMPLS_FUNCTION_KEY` | Function API key | `abc123...` |

#### PythonTool Requirements

| Requirement | Details |
|-------------|----------|
| **Function Name** | Must be `def main(**kwargs)` - the runtime calls `main()` |
| **Return Type** | JSON-serializable dict or list |
| **Error Handling** | Wrap HTTP calls in try/except to return structured errors |
| **Environment Variables** | Use `os.environ.get()` with fallbacks for demo environments |
| **Secrets Management** | In production, use Key Vault; fallback keys are for demos only |

#### Deploy via Azure Portal

You can create the subagent and tools directly in the Azure Portal:

**Step 1: Navigate to Subagent Builder**

1. Open the [Azure Portal](https://portal.azure.com)
2. Navigate to your **Azure SRE Agent** resource
3. In the left sidebar, expand **Builder** and click **Subagent builder**

**Step 2: Create the Subagent**

1. Click **+ Create subagent**
2. Fill in the subagent details:
   - **Name**: `CrossSubscriptionAMPLS`
   - **Description**: Query Log Analytics workspaces protected by AMPLS using Azure Function as cross-subscription proxy
   - **Tags**: `ampls`, `cross-subscription`, `private-link`, `log-analytics`
3. In the **Instructions** field, paste the agent instructions from the YAML above
4. In the **Handoff Description** field, describe when to hand off to this agent
5. Click **Save**

**Step 3: Create the PythonTools**

1. In the Subagent builder, click on your new subagent
2. Click **+ Add tool** and select **PythonTool**
3. For each tool (QueryLogs, ListTables, CheckVMHealth, AnalyzeErrors):
   - **Name**: `CrossSubAMPLS_QueryLogs` (etc.)
   - **Description**: Enter the tool description
   - **Function Code**: Paste the Python code from the YAML examples above
   - **Parameters**: Add the required parameters (query, timespan, etc.)
4. Click **Save** after adding each tool

**Step 4: Configure Environment Variables**

In the PythonTool code, you'll need to configure:

| Variable | Description | How to Get It |
|----------|-------------|---------------|
| `CROSS_SUB_AMPLS_FUNCTION_URL` | Your Azure Function URL | Azure Portal → Function App → Overview → URL |
| `CROSS_SUB_AMPLS_FUNCTION_KEY` | Function API key | Azure Portal → Function App → App keys → Host keys |

> 💡 **Tip**: For demo purposes, you can hardcode these values in the PythonTool code. For production, use Azure Key Vault integration.

**Step 5: Test the Subagent**

1. Start a new chat in Azure SRE Agent
2. Ask: "Use the CrossSubscriptionAMPLS subagent to list tables in my private Log Analytics workspace"
3. Verify the agent hands off correctly and tools execute

Now when users ask "get my logs for a resource that is within the private network", the meta agent will hand off to the PrivateLAWQuery subagent which queries via the Function proxy.

---

## The Investigation Flow

With this architecture, SRE Agent can investigate issues even though the LAW blocks public queries:

| Step | Actor | Action |
|:----:|-------|--------|
| 1️⃣ | **You** | "There are errors on my workload VMs. Investigate." |
| 2️⃣ | **SRE Agent** | Calls Azure Function's `query_logs` endpoint |
| 3️⃣ | **Azure Function** | Queries LAW via Private Endpoint |
| 4️⃣ | **Log Analytics** | Returns results (allowed—request came from PE) |
| 5️⃣ | **Azure Function** | Returns JSON response to SRE Agent |
| 6️⃣ | **SRE Agent** | Analyzes logs, identifies root cause, responds |

---

## Security Considerations

This architecture maintains security while enabling AI-assisted investigation:

| Concern | How It's Secured |
|---------|------------------|
| 🔐 **Log Analytics** | Public query access disabled, Private Link only |
| 🔗 **Private Endpoint** | In isolated subnet with NSG rules |
| 🪪 **Azure Function** | Managed Identity for LAW access (no secrets) |
| 🔑 **API Authentication** | Function Key required for all calls |
| 🌐 **VNet Routing** | `vnetRouteAllEnabled: true` for all traffic |
| 📝 **Audit Trail** | All invocations logged in Application Insights |

---

## Azure Functions vs MCP Approach

| Aspect | Azure Functions (this sample) | MCP Server |
|--------|-------------------------------|------------|
| **SRE Agent Integration** | Custom HTTP tools | MCP tool |
| **Protocol** | REST API | MCP Streamable HTTP |
| **Hosting** | Azure Functions (EP1) | Container Apps |
| **Authentication** | Function Key | API Key |
| **Scaling** | Auto-scale (serverless) | Container-based |
| **Cold Start** | ~1-2 seconds | Always-on option |
| **Best For** | Simple query proxy | Rich tool ecosystem |

> 💡 See the [private-vnet-observability](../private-vnet-observability/) sample for the MCP-based approach.

---

## Try It Yourself

Deploy this sample environment to see the pattern in action:

```bash
# Clone the sample repository
git clone https://github.com/BandaruDheeraj/private-law-query-sample
cd private-law-query-sample

# Deploy with Azure Developer CLI (single subscription, two resource groups)
azd up

# Inject failures to generate logs
./inject-failure.ps1

# Configure SRE Agent with the Function URL from the output
# Ask SRE Agent to investigate
```

This creates:
- `rg-originations-{env}`: LAW + AMPLS (private query access)
- `rg-workload-{env}`: VNet + PE + Functions + VMs

---

## Key Takeaways

**🚫 Log Analytics Workspaces are not VNet resources**
They use public endpoints by default. You cannot "place" them inside a VNet.

**🔗 AMPLS is the solution for private access**
Azure Monitor Private Link Scope with Private Endpoints enables private queries.

**📁 Resource groups simulate cross-subscription**
This sample uses two resource groups; the same pattern works across subscriptions.

**⚡ Azure Functions provide serverless query proxy**
VNet-integrated Functions with Managed Identity can query private Log Analytics for SRE Agent.

**🔒 Security is maintained**
The workspace remains fully private; only the trusted Function can query it.

---

## Resources

| Resource | Link |
|----------|------|
| 📦 **Sample Repository** | [github.com/BandaruDheeraj/private-law-query-sample](https://github.com/BandaruDheeraj/private-law-query-sample) |
| 📖 Azure Monitor Private Link | [docs.microsoft.com/azure/azure-monitor/logs/private-link-security](https://docs.microsoft.com/azure/azure-monitor/logs/private-link-security) |
| 🔗 Azure Functions VNet Integration | [docs.microsoft.com/azure/azure-functions/functions-networking-options](https://docs.microsoft.com/azure/azure-functions/functions-networking-options) |
| 🛡️ AMPLS Design Guidance | [docs.microsoft.com/azure/azure-monitor/logs/private-link-design](https://docs.microsoft.com/azure/azure-monitor/logs/private-link-design) |
| 🔐 Managed Identity for Azure Functions | [docs.microsoft.com/azure/app-service/overview-managed-identity](https://docs.microsoft.com/azure/app-service/overview-managed-identity) |
| 🚀 Azure Developer CLI (azd) | [learn.microsoft.com/azure/developer/azure-developer-cli](https://learn.microsoft.com/azure/developer/azure-developer-cli/) |

---

## About the Author

*Dheeraj Bandaru is a Senior Program Manager at Microsoft working on Azure SRE Agent. Follow for more patterns on AI-assisted operations and Azure infrastructure.*

---

**Tags**: `Azure Monitor` `Private Link` `AMPLS` `Azure Functions` `Log Analytics` `VNet Integration` `SRE` `DevOps` `Security`
