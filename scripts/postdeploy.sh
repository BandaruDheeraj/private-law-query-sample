#!/bin/bash
# Post-deploy hook - runs after application is deployed

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Post-Deploy: Verifying Azure Function"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get Function App URL
FUNCTION_APP_URL=$(azd env get-values | grep FUNCTION_APP_URL | cut -d'=' -f2 | tr -d '"')
FUNCTION_API_KEY=$(azd env get-values | grep FUNCTION_API_KEY | cut -d'=' -f2 | tr -d '"')

echo "📋 Function App URL: $FUNCTION_APP_URL"
echo ""

# Wait for the Function App to be ready
echo "⏳ Waiting for Function App to be ready..."
sleep 15

# Test the Function App by listing tables
echo "🔍 Testing Function App connectivity..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "x-functions-key: $FUNCTION_API_KEY" \
    "${FUNCTION_APP_URL}/api/list_tables" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Function App is ready and can query Log Analytics!"
else
    echo "⚠️  Function App test returned: $HTTP_STATUS"
    echo "   The function may still be warming up."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Deployment Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "1. Run ./inject-failure.ps1 to simulate issues"
echo "2. Configure SRE Agent with the Function App URL as HTTP tools"
echo "3. Ask SRE Agent to investigate the errors"
echo ""
