"""
Azure Function to analyze errors in logs.

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
    Analyze errors in logs from the past N hours.
    
    Query parameters:
    - hours: Number of hours to look back (default: 24)
    """
    logging.info("Processing analyze_errors request")

    # Get hours parameter
    hours = req.params.get("hours", "24")
    try:
        hours = int(hours)
    except ValueError:
        hours = 24

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

        # Query to analyze errors from Syslog
        query = f"""
        Syslog
        | where TimeGenerated > ago({hours}h)
        | where SeverityLevel in ("err", "error", "crit", "critical", "alert", "emerg")
        | summarize 
            ErrorCount = count(),
            FirstSeen = min(TimeGenerated),
            LastSeen = max(TimeGenerated)
            by Computer, Facility, SeverityLevel
        | order by ErrorCount desc
        | take 50
        """

        response = client.query_workspace(
            workspace_id=WORKSPACE_ID,
            query=query,
            timespan=timedelta(hours=hours)
        )

        if response.status == LogsQueryStatus.SUCCESS:
            errors = []
            total_error_count = 0

            for table in response.tables:
                # In azure-monitor-query v2.0.0+, columns is a list of strings
                columns = table.columns if isinstance(table.columns[0], str) else [col.name for col in table.columns]
                for row in table.rows:
                    error = dict(zip(columns, row))
                    errors.append(error)
                    total_error_count += error.get("ErrorCount", 0)

            # Get top error messages
            message_query = f"""
            Syslog
            | where TimeGenerated > ago({hours}h)
            | where SeverityLevel in ("err", "error", "crit", "critical", "alert", "emerg")
            | summarize Count = count() by SyslogMessage
            | order by Count desc
            | take 10
            """

            message_response = client.query_workspace(
                workspace_id=WORKSPACE_ID,
                query=message_query,
                timespan=timedelta(hours=hours)
            )

            top_messages = []
            if message_response.status == LogsQueryStatus.SUCCESS:
                for table in message_response.tables:
                    for row in table.rows:
                        top_messages.append({
                            "message": row[0][:200],  # Truncate long messages
                            "count": row[1]
                        })

            return func.HttpResponse(
                json.dumps({
                    "status": "success",
                    "timespan_hours": hours,
                    "summary": {
                        "total_errors": total_error_count,
                        "unique_patterns": len(errors)
                    },
                    "errors_by_source": errors,
                    "top_error_messages": top_messages
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
        logging.error(f"Analyze errors failed: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
