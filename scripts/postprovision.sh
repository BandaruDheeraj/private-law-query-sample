#!/bin/bash
# Post-provision hook - runs after infrastructure is deployed

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Post-Provision: Configuring resources"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get outputs from azd
WORKLOAD_RG=$(azd env get-values | grep WORKLOAD_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"')
FUNCTION_APP_URL=$(azd env get-values | grep FUNCTION_APP_URL | cut -d'=' -f2 | tr -d '"')

echo "📋 Workload Resource Group: $WORKLOAD_RG"
echo "📋 Function App URL: $FUNCTION_APP_URL"

# Wait for VMs to be ready
echo ""
echo "⏳ Waiting for VMs to be ready..."
sleep 30

# Install stress utility on VMs for failure injection
for VM in app-vm db-vm web-vm; do
    echo "📦 Installing stress utility on $VM..."
    az vm run-command invoke \
        --resource-group "$WORKLOAD_RG" \
        --name "$VM" \
        --command-id RunShellScript \
        --scripts "apt-get update && apt-get install -y stress" \
        --output none 2>/dev/null || true
done

echo ""
echo "✅ Post-provision configuration complete!"
echo ""
