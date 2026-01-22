"""
Azure Function to list tables in Log Analytics workspace.

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
    List all tables available in the Log Analytics workspace.
    """
    logging.info("Processing list_tables request")

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

        # Query to list all tables
        query = """
        search *
        | summarize count() by $table
        | project TableName = $table, RowCount = count_
        | order by RowCount desc
        """

        response = client.query_workspace(
            workspace_id=WORKSPACE_ID,
            query=query,
            timespan=timedelta(days=1)
        )

        if response.status == LogsQueryStatus.SUCCESS:
            tables = []
            for table in response.tables:
                for row in table.rows:
                    tables.append({
                        "name": row[0],
                        "row_count_24h": row[1]
                    })

            return func.HttpResponse(
                json.dumps({
                    "status": "success",
                    "table_count": len(tables),
                    "tables": tables
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
        logging.error(f"List tables failed: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
