# Private Log Analytics Query Sample (AMPLS Pattern)

Query a Log Analytics Workspace protected by Azure Monitor Private Link Scope (AMPLS) using Azure Functions as a VNet-integrated proxy for Azure SRE Agent.

## Why This Pattern?

**The Problem**: When `publicNetworkAccessForQuery: Disabled` is set on a Log Analytics workspace, external queries—including from Azure SRE Agent—are blocked.

**The Solution**: Deploy an Azure Function inside a VNet with Private Endpoint access to the AMPLS. SRE Agent calls the Function as custom HTTP tools, which query Log Analytics on its behalf.

```
Azure SRE Agent → Azure Function (in VNet) → Private Endpoint → AMPLS → Log Analytics Workspace
```

> 💡 Log Analytics Workspaces cannot be created inside a VNet. AMPLS + Private Endpoints are required for private access.

---

## 📍 Key File Locations

| What You Need | Location |
|---------------|----------|
| **Azure Function Code** | [`src/log-analytics-function/`](src/log-analytics-function/) |
| **Subagent YAML** | [`src/log-analytics-function/agents/CrossSubscriptionAMPLS/`](src/log-analytics-function/agents/CrossSubscriptionAMPLS/CrossSubscriptionAMPLS.yaml) |
| **All Scripts** | [`scripts/`](scripts/) |

### Function Endpoints

| Function | File | Purpose |
|----------|------|---------|
| `query_logs` | [`query_logs/__init__.py`](src/log-analytics-function/query_logs/__init__.py) | Execute KQL queries |
| `list_tables` | [`list_tables/__init__.py`](src/log-analytics-function/list_tables/__init__.py) | List available tables |
| `check_vm_health` | [`check_vm_health/__init__.py`](src/log-analytics-function/check_vm_health/__init__.py) | Check VM heartbeat |
| `analyze_errors` | [`analyze_errors/__init__.py`](src/log-analytics-function/analyze_errors/__init__.py) | Analyze Syslog errors |

---

## Quick Start

### 1. Deploy with Azure Developer CLI

```bash
git clone https://github.com/BandaruDheeraj/private-law-query-sample
cd private-law-query-sample
azd up
```

This creates:
- **Log Analytics Workspace** with public query access disabled
- **AMPLS** with `queryAccessMode: PrivateOnly`
- **VNet + Private Endpoint** connecting to AMPLS
- **Azure Functions** (VNet-integrated) with 4 HTTP endpoints
- **Sample VMs** sending logs to the workspace

### 2. Get the Function Key

```powershell
az functionapp keys list `
  --name <FUNCTION_APP_NAME> `
  --resource-group <RESOURCE_GROUP> `
  --query functionKeys.default -o tsv
```

Or: **Azure Portal** → **Function App** → **App keys** → **default**

### 3. Configure SRE Agent

1. Go to **Azure Portal** → **SRE Agent** → **Builder** → **Subagent builder**
2. Create a subagent using the YAML from [`agents/CrossSubscriptionAMPLS/`](src/log-analytics-function/agents/CrossSubscriptionAMPLS/)
3. Add PythonTools for each function (see examples below)

### 4. Test It

Ask SRE Agent:
> "List the tables in the Log Analytics workspace"

---

## Creating PythonTools in SRE Agent

### Tool Configuration

| Field | Example |
|-------|---------|
| **Name** | `CrossSubAMPLS_QueryLogs` |
| **Description** | Execute KQL queries against private Log Analytics |

### Parameter Schema (for QueryLogs)

```json
{
  "type": "object",
  "properties": {
    "query": { "type": "string", "description": "KQL query to execute" },
    "timespan": { "type": "string", "description": "ISO 8601 duration (e.g., PT1H, P1D)" }
  },
  "required": ["query"]
}
```

### Function Code Template

```python
import json
import urllib.request
import urllib.error

def main(**kwargs):
    query = kwargs.get("query")
    timespan = kwargs.get("timespan", "P1D")
    
    if not query:
        return {"error": "Missing required parameter: query"}
    
    # Replace with your values
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

> ⚠️ **Important**: Use `def main(**kwargs)` — not `def execute()`. Use `urllib` — not `requests`.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/inject-failure.ps1` | Simulate application issues for demo |
| `scripts/fix-issue.ps1` | Apply remediation |
| `scripts/cleanup.ps1` | Delete all resources |

---

## Cleanup

```powershell
./scripts/cleanup.ps1
# or
azd down
```

---

## Related

- [Azure Monitor Private Link documentation](https://docs.microsoft.com/azure/azure-monitor/logs/private-link-security)
- [Azure Functions VNet Integration](https://docs.microsoft.com/azure/azure-functions/functions-networking-options)
