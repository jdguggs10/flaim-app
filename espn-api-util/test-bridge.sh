#!/bin/bash

# ESPN Fantasy Baseball MCP Bridge - Test Script
# Verifies the bridge functionality with sample API calls

set -e

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 Testing ESPN Fantasy Baseball MCP Bridge..."

# Load environment variables
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Configuration
BASE_URL="http://localhost:9080/espn-bb"
TEST_TIMEOUT=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local expected_status="$5"
    
    echo -n "Testing $name... "
    
    if [ "$method" == "POST" ] && [ -n "$data" ]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Accept: text/event-stream" \
            --max-time $TEST_TIMEOUT \
            -d "$data" \
            "$BASE_URL$endpoint" 2>/dev/null || echo "HTTPSTATUS:000")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "Accept: text/event-stream" \
            --max-time $TEST_TIMEOUT \
            "$BASE_URL$endpoint" 2>/dev/null || echo "HTTPSTATUS:000")
    fi
    
    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')
    
    if [ "$http_status" -eq "$expected_status" ]; then
        echo -e "${GREEN}✅ PASS${NC} (HTTP $http_status)"
        if [ ${#body} -gt 100 ]; then
            echo "   Response: ${body:0:100}..."
        else
            echo "   Response: $body"
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (HTTP $http_status, expected $expected_status)"
        if [ ${#body} -gt 200 ]; then
            echo "   Response: ${body:0:200}..."
        else
            echo "   Response: $body"
        fi
    fi
    echo
}

# Check if bridge is running
echo "🔍 Checking if MCP bridge is running..."
if ! curl -f -s http://localhost:9080/apisix/status >/dev/null; then
    echo -e "${RED}❌ APISIX is not running. Start it with: ./start-bridge.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✅ APISIX is running${NC}"
echo

# Test 1: MCP Tools List (should work without authentication)
test_endpoint "MCP Tools List" "GET" "/tools/list" "" 200

# Test 2: MCP Initialize
init_data='{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {
            "roots": {
                "listChanged": false
            },
            "sampling": {}
        },
        "clientInfo": {
            "name": "test-client",
            "version": "1.0.0"
        }
    }
}'
test_endpoint "MCP Initialize" "POST" "/initialize" "$init_data" 200

# Test 3: Get League Info (requires ESPN credentials)
league_data='{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
        "name": "league_get_info",
        "arguments": {
            "league_id": "'$LEAGUE_ID'"
        }
    }
}'
test_endpoint "League Info" "POST" "/tools/call" "$league_data" 200

# Test 4: Get League Standings
standings_data='{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
        "name": "league_get_standings",
        "arguments": {
            "league_id": "'$LEAGUE_ID'"
        }
    }
}'
test_endpoint "League Standings" "POST" "/tools/call" "$standings_data" 200

# Test 5: Get Metadata Positions
positions_data='{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "tools/call",
    "params": {
        "name": "metadata_get_positions",
        "arguments": {}
    }
}'
test_endpoint "Metadata Positions" "POST" "/tools/call" "$positions_data" 200

# Test 6: Invalid endpoint (should return 404)
test_endpoint "Invalid Endpoint" "GET" "/invalid/endpoint" "" 404

echo "🏁 Bridge testing complete!"
echo
echo "📊 Additional monitoring:"
echo "   docker-compose logs -f apisix | grep espn-bb"
echo "   docker-compose logs -f mcp"
echo
echo "🔧 Admin API endpoints:"
echo "   curl http://localhost:9180/apisix/admin/routes"
echo "   curl http://localhost:9180/apisix/admin/plugins/list"
echo