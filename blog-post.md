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
                                    │ HTTPS (REST API + Easy Auth Bearer Token)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure SRE Agent                                     │
│                    (Outside the VNet)                                       │
│                                                                             │
│  "Investigate errors on my workload VMs in the Originations LAW"           │
│                                                                             │
│  ✓ Acquires Bearer Token via Managed Identity                              │
│  ✓ Calls Azure Function endpoints over HTTPS with token                    │
│  ✓ Function queries LAW via Private Endpoint                               │
│  ✓ Results returned to agent for analysis                                  │
│  ✓ No secrets or function keys required                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## How the Data Flows: Step by Step

Understanding the exact data flow is key to this pattern. Here's how a query travels from SRE Agent to Log Analytics:

```
Azure SRE Agent (cloud service, outside VNet)
        │
        │ HTTPS call with Bearer Token (Easy Auth)
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
| **SRE Agent PythonTool** | Cloud (outside VNet) | Acquires Bearer Token via Managed Identity, calls Azure Function over HTTPS |

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
# IMPORTANT: Scope to the workspace resource, not the function app's resource group
az role assignment create `
  --assignee-object-id $(az functionapp identity show ...) `
  --role "Log Analytics Reader" `
  --scope /subscriptions/.../workspaces/originations-law
```

---

### Step 5: Configure Easy Auth (Microsoft Entra ID) on the Function App

Instead of function keys, we secure the Azure Function with **Easy Auth** (Microsoft Entra ID authentication). This eliminates the need to manage secrets—the SRE Agent authenticates using its Managed Identity.

#### 5a. Set Function Auth Level to Anonymous

Since Easy Auth handles authentication at the platform level, set `authLevel` to `anonymous` in each `function.json`:

```json
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get", "post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
```

#### 5b. Enable Easy Auth via Azure Portal

1. Navigate to your **Function App** in the Azure Portal
2. Go to **Settings** → **Authentication**
3. Click **Add identity provider**
4. Select **Microsoft** as the identity provider
5. Configure:
   - **App registration type**: Create new
   - **Supported account types**: Current tenant (single tenant)
   - **Client assertion type**: Federated identity credential (recommended)
   - **Restrict access**: Require authentication
   - **Unauthenticated requests**: HTTP 401 Unauthorized
6. Under **Allowed client applications**, add the SRE Agent's Managed Identity Client ID
7. Click **Add**

Note the **Application (client) ID** created—you'll need it for the PythonTool configuration.

#### 5c. Configure SRE Agent Subagent

Create a specialized subagent that uses the Azure Function endpoints with Easy Auth. The PythonTools acquire a Bearer Token from the SRE Agent's Managed Identity to authenticate.

#### Subagent Definition

```yaml
api_version: azuresre.ai/v2
kind: ExtendedAgent
metadata:
  name: PrivateLAWQuery
  tags:
    - ampls
    - private-link
    - easy-auth
spec:
  instructions: |
    You are a specialized Site Reliability Engineer focused on querying Log Analytics
    workspaces that are protected by Azure Monitor Private Link Scope (AMPLS) with
    private-only query access mode.

    ## Architecture Pattern
    This agent uses an Azure Function deployed in a VNet as a query proxy, authenticated
    via Easy Auth (Microsoft Entra ID) instead of function keys:

    SRE Agent → (Bearer Token) → Azure Function (VNet-integrated) → Private Endpoint → AMPLS → LAW

    ## Available Tools
    - PrivateLAW_QueryLogs: Execute KQL queries against the private LAW
    - PrivateLAW_ListTables: List available tables and row counts
    - PrivateLAW_CheckVMHealth: Check VM heartbeat status
    - PrivateLAW_AnalyzeErrors: Analyze error trends from Syslog

  handoffDescription: |
    Hand off to this agent when the user needs to query Log Analytics workspaces
    protected by Azure Monitor Private Link Scope (AMPLS) with private-only access.
    This agent uses an Azure Function as a VNet-integrated query proxy secured
    with Easy Auth (Entra ID).

  tools:
    - PrivateLAW_QueryLogs
    - PrivateLAW_ListTables
    - PrivateLAW_CheckVMHealth
    - PrivateLAW_AnalyzeErrors
```

#### Tool Definitions (PythonTools with Easy Auth)

Each tool acquires a Bearer Token from the SRE Agent's Managed Identity and calls the Azure Function endpoints.

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
    - easy-auth
spec:
  type: PythonTool
  toolMode: Auto
  description: Execute KQL queries against a private Log Analytics workspace via AMPLS using Easy Auth (Entra ID)
  functionCode: |
    import json
    import urllib.request
    import urllib.error
    import os

    def main(**kwargs):
        query = kwargs.get('query', '')
        timespan = kwargs.get('timespan', 'P1D')

        if not query:
            return {"error": "Query parameter is required"}

        # Replace with your Function App URL and App Registration Client ID
        function_url = 'https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/query_logs'
        app_id = '<YOUR-APP-REGISTRATION-CLIENT-ID>'

        # Acquire token from SRE Agent's managed identity
        identity_endpoint = os.environ.get('IDENTITY_ENDPOINT', '')
        identity_header = os.environ.get('IDENTITY_HEADER', '')

        if not identity_endpoint or not identity_header:
            return {"error": "Managed identity not available."}

        token_url = f"{identity_endpoint}?api-version=2019-08-01&resource=api://{app_id}"
        token_req = urllib.request.Request(token_url)
        token_req.add_header('X-IDENTITY-HEADER', identity_header)

        try:
            with urllib.request.urlopen(token_req, timeout=10) as token_resp:
                token_data = json.loads(token_resp.read().decode('utf-8'))
                access_token = token_data.get('access_token', '')
        except Exception as e:
            return {"error": f"Failed to acquire token: {str(e)}"}

        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {access_token}'
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

#### How Easy Auth Token Acquisition Works

The PythonTool runs inside the SRE Agent sandbox, which has a Managed Identity. The token acquisition flow:

1. **PythonTool** reads `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` environment variables (set automatically by the SRE Agent runtime)
2. **PythonTool** calls the identity endpoint with `resource=api://<app-id>` to get a Bearer Token
3. **PythonTool** includes the token in the `Authorization: Bearer <token>` header
4. **Easy Auth** on the Function App validates the token against the App Registration
5. **Function App** executes the query using its own Managed Identity

> 💡 **No secrets required**: Unlike function keys, Easy Auth uses Managed Identity tokens that are automatically rotated and never stored in code or configuration.

#### PythonTool Requirements

| Requirement | Details |
|-------------|----------|
| **Function Name** | Must be `def main(**kwargs)` - the runtime calls `main()` |
| **Return Type** | JSON-serializable dict or list |
| **Error Handling** | Wrap HTTP calls in try/except to return structured errors |
| **Token Acquisition** | Use `IDENTITY_ENDPOINT` + `IDENTITY_HEADER` for managed identity tokens |
| **App Registration** | Configure the App Registration Client ID as the token `resource` |

#### Deploy via srectl CLI

Apply the agent and tools using the SRE Agent CLI:

```powershell
# Apply tool definitions
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_QueryLogs.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_ListTables.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_CheckVMHealth.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_AnalyzeErrors.yaml

# Apply agent definition
srectl apply-yaml --file agents/EasyAuth/PrivateLAWQuery.yaml
```

Or deploy via the Azure Portal Builder UI.

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
| 🔑 **API Authentication** | Easy Auth (Microsoft Entra ID) with Bearer Token—no secrets to manage |
| 🌐 **VNet Routing** | `vnetRouteAllEnabled: true` for all traffic |
| 📝 **Audit Trail** | All invocations logged in Application Insights |

---

## Azure Functions vs MCP Approach

| Aspect | Azure Functions (this sample) | MCP Server |
|--------|-------------------------------|------------|
| **SRE Agent Integration** | Custom HTTP tools | MCP tool |
| **Protocol** | REST API | MCP Streamable HTTP |
| **Hosting** | Azure Functions (EP1) | Container Apps |
| **Authentication** | Easy Auth (Entra ID Bearer Token) | API Key |
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

# Configure Easy Auth on the Function App (see Step 5 above)

# Inject failures to generate logs
./inject-failure.ps1

# Deploy SRE Agent tools with srectl
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_QueryLogs.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_ListTables.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_CheckVMHealth.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAW_AnalyzeErrors.yaml
srectl apply-yaml --file agents/EasyAuth/PrivateLAWQuery.yaml

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
The workspace remains fully private; only the trusted Function can query it. Easy Auth (Entra ID) eliminates the need to manage function keys—the SRE Agent authenticates with its Managed Identity.

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

**Tags**: `Azure Monitor` `Private Link` `AMPLS` `Azure Functions` `Log Analytics` `VNet Integration` `Easy Auth` `Entra ID` `SRE` `DevOps` `Security`
