"""
Azure Function to query Log Analytics via Private Endpoint.

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
    Execute a KQL query against Log Analytics.
    
    Request body:
    {
        "query": "Heartbeat | take 10",
        "timespan": "PT1H"  // Optional, defaults to 1 hour
    }
    """
    logging.info("Processing query_logs request")

    try:
        req_body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Invalid JSON in request body"}),
            status_code=400,
            mimetype="application/json"
        )

    query = req_body.get("query")
    if not query:
        return func.HttpResponse(
            json.dumps({"error": "Missing 'query' parameter"}),
            status_code=400,
            mimetype="application/json"
        )

    # Parse timespan (default to 1 hour)
    timespan_str = req_body.get("timespan", "PT1H")
    timespan = parse_timespan(timespan_str)

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

        # Execute query via Private Endpoint
        response = client.query_workspace(
            workspace_id=WORKSPACE_ID,
            query=query,
            timespan=timespan
        )

        if response.status == LogsQueryStatus.SUCCESS:
            # Convert tables to JSON-serializable format
            results = []
            for table in response.tables:
                # In azure-monitor-query v2.0.0+, columns is a list of strings
                columns = table.columns if isinstance(table.columns[0], str) else [col.name for col in table.columns]
                for row in table.rows:
                    results.append(dict(zip(columns, row)))

            return func.HttpResponse(
                json.dumps({
                    "status": "success",
                    "row_count": len(results),
                    "results": results
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
        logging.error(f"Query failed: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


def parse_timespan(timespan_str: str) -> timedelta:
    """Parse ISO 8601 duration string to timedelta."""
    # Simple parser for common formats: PT1H, PT24H, P1D, P7D
    timespan_str = timespan_str.upper()
    
    if timespan_str.startswith("PT"):
        # Hours format: PT1H, PT24H
        hours_str = timespan_str[2:].rstrip("H")
        try:
            return timedelta(hours=int(hours_str))
        except ValueError:
            return timedelta(hours=1)
    elif timespan_str.startswith("P"):
        # Days format: P1D, P7D
        days_str = timespan_str[1:].rstrip("D")
        try:
            return timedelta(days=int(days_str))
        except ValueError:
            return timedelta(days=1)
    else:
        return timedelta(hours=1)
