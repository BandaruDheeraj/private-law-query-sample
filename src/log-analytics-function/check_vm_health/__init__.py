"""
Azure Function to check VM health via Heartbeat table.

This function runs inside a VNet-integrated Azure Function App,
enabling it to query Log Analytics workspaces protected by Private Link.
"""

import json
import logging
import os
from datetime import timedelta

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus

# Get workspace ID from environment
WORKSPACE_ID = os.environ.get("LOG_ANALYTICS_WORKSPACE_ID", "")


def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Check health of VMs by analyzing Heartbeat table.
    """
    logging.info("Processing check_vm_health request")

    if not WORKSPACE_ID:
        return func.HttpResponse(
            json.dumps({"error": "LOG_ANALYTICS_WORKSPACE_ID not configured"}),
            status_code=500,
            mimetype="application/json"
        )

    try:
        # Use DefaultAzureCredential (Managed Identity in Azure)
        credential = DefaultAzureCredential()
        client = LogsQueryClient(credential)

        # Query to check VM health
        query = """
        Heartbeat
        | where TimeGenerated > ago(1h)
        | summarize 
            LastHeartbeat = max(TimeGenerated),
            HeartbeatCount = count()
            by Computer, OSType, Version
        | extend 
            Status = iff(LastHeartbeat < ago(5m), "Disconnected", "Connected"),
            MinutesSinceLastHeartbeat = datetime_diff('minute', now(), LastHeartbeat)
        | project 
            Computer,
            OSType,
            Status,
            LastHeartbeat,
            MinutesSinceLastHeartbeat,
            HeartbeatCount
        | order by Status asc, Computer asc
        """

        response = client.query_workspace(
            workspace_id=WORKSPACE_ID,
            query=query,
            timespan=timedelta(hours=1)
        )

        if response.status == LogsQueryStatus.SUCCESS:
            vms = []
            connected_count = 0
            disconnected_count = 0

            for table in response.tables:
                # In azure-monitor-query v2.0.0+, columns is a list of strings
                columns = table.columns if isinstance(table.columns[0], str) else [col.name for col in table.columns]
                for row in table.rows:
                    vm = dict(zip(columns, row))
                    vms.append(vm)
                    if vm.get("Status") == "Connected":
                        connected_count += 1
                    else:
                        disconnected_count += 1

            return func.HttpResponse(
                json.dumps({
                    "status": "success",
                    "summary": {
                        "total_vms": len(vms),
                        "connected": connected_count,
                        "disconnected": disconnected_count
                    },
                    "vms": vms
                }, default=str),
                status_code=200,
                mimetype="application/json"
            )
        else:
            return func.HttpResponse(
                json.dumps({
                    "status": "partial",
                    "error": str(response.partial_error)
                }),
                status_code=206,
                mimetype="application/json"
            )

    except Exception as e:
        logging.error(f"Check VM health failed: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
