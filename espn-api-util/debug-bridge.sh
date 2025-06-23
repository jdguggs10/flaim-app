#!/bin/bash

# ESPN Fantasy Baseball MCP Bridge - Debug Script
# Provides debugging tools and diagnostics for the MCP bridge

set -e

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 ESPN Fantasy Baseball MCP Bridge - Debug Mode${NC}"
echo

# Function to show service status
show_service_status() {
    echo -e "${YELLOW}📊 Service Status:${NC}"
    docker-compose ps
    echo
}

# Function to show recent logs
show_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    echo -e "${YELLOW}📝 Recent logs for $service (last $lines lines):${NC}"
    docker-compose logs --tail="$lines" "$service" 2>/dev/null || echo "Service $service not found"
    echo
}

# Function to test MCP server directly
test_mcp_direct() {
    echo -e "${YELLOW}🧪 Testing MCP server directly:${NC}"
    
    # Test if MCP container is running
    if ! docker-compose ps mcp | grep -q "Up"; then
        echo -e "${RED}❌ MCP container is not running${NC}"
        return 1
    fi
    
    # Execute MCP tools list directly in container
    echo "Testing tools/list in MCP container..."
    docker-compose exec -T mcp python -m baseball_mcp.baseball_mcp_server << 'EOF'
{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
EOF
    echo
}

# Function to check APISIX routes
check_apisix_routes() {
    echo -e "${YELLOW}🛣️ APISIX Routes:${NC}"
    curl -s http://localhost:9180/apisix/admin/routes | jq '.' 2>/dev/null || echo "Could not fetch routes (jq not installed or APISIX not responding)"
    echo
}

# Function to check APISIX plugins
check_apisix_plugins() {
    echo -e "${YELLOW}🔌 APISIX Available Plugins:${NC}"
    curl -s http://localhost:9180/apisix/admin/plugins/list | jq '.[] | select(. == "mcp-bridge")' 2>/dev/null || echo "mcp-bridge plugin not found or jq not installed"
    echo
}

# Function to show environment variables
show_env_vars() {
    echo -e "${YELLOW}🌍 Environment Variables:${NC}"
    if [ -f ".env" ]; then
        echo "ESPN_S2: ${ESPN_S2:0:20}..." 
        echo "SWID: $SWID"
        echo "LEAGUE_ID: $LEAGUE_ID"
    else
        echo ".env file not found"
    fi
    echo
}

# Function to check network connectivity
check_network() {
    echo -e "${YELLOW}🌐 Network Connectivity:${NC}"
    
    # Check if ports are open
    ports=(9080 9180 2379)
    for port in "${ports[@]}"; do
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "Port $port: ${GREEN}✅ Open${NC}"
        else
            echo -e "Port $port: ${RED}❌ Closed${NC}"
        fi
    done
    echo
}

# Function to perform health checks
health_checks() {
    echo -e "${YELLOW}🏥 Health Checks:${NC}"
    
    # APISIX health
    if curl -f -s http://localhost:9080/apisix/status >/dev/null; then
        echo -e "APISIX: ${GREEN}✅ Healthy${NC}"
    else
        echo -e "APISIX: ${RED}❌ Unhealthy${NC}"
    fi
    
    # etcd health  
    if docker-compose exec -T etcd etcdctl endpoint health >/dev/null 2>&1; then
        echo -e "etcd: ${GREEN}✅ Healthy${NC}"
    else
        echo -e "etcd: ${RED}❌ Unhealthy${NC}"
    fi
    
    # MCP container
    if docker-compose ps mcp | grep -q "Up"; then
        echo -e "MCP Container: ${GREEN}✅ Running${NC}"
    else
        echo -e "MCP Container: ${RED}❌ Not Running${NC}"
    fi
    echo
}

# Function to show resource usage
show_resources() {
    echo -e "${YELLOW}💻 Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "(espn-mcp|CONTAINER)"
    echo
}

# Main menu
show_menu() {
    echo -e "${BLUE}🛠️ Debug Options:${NC}"
    echo "1. Show service status"
    echo "2. Show recent logs (all services)"
    echo "3. Show APISIX logs"
    echo "4. Show MCP logs"
    echo "5. Test MCP server directly"
    echo "6. Check APISIX routes"
    echo "7. Check APISIX plugins"
    echo "8. Show environment variables"
    echo "9. Check network connectivity"
    echo "10. Perform health checks"
    echo "11. Show resource usage"
    echo "12. Full diagnostic report"
    echo "13. Interactive shell in MCP container"
    echo "0. Exit"
    echo
}

# Interactive mode
if [ $# -eq 0 ]; then
    while true; do
        show_menu
        read -p "Select option (0-13): " choice
        echo
        
        case $choice in
            1) show_service_status ;;
            2) show_logs apisix; show_logs mcp; show_logs etcd ;;
            3) show_logs apisix 100 ;;
            4) show_logs mcp 100 ;;
            5) test_mcp_direct ;;
            6) check_apisix_routes ;;
            7) check_apisix_plugins ;;
            8) show_env_vars ;;
            9) check_network ;;
            10) health_checks ;;
            11) show_resources ;;
            12) 
                echo -e "${BLUE}📋 Full Diagnostic Report:${NC}"
                echo "================================"
                show_env_vars
                health_checks
                check_network
                show_service_status
                show_resources
                ;;
            13) 
                echo "Starting interactive shell in MCP container..."
                docker-compose exec mcp /bin/bash
                ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        clear
    done
else
    # Command line mode
    case "$1" in
        "status") show_service_status ;;
        "logs") show_logs "${2:-apisix}" "${3:-50}" ;;
        "test") test_mcp_direct ;;
        "routes") check_apisix_routes ;;
        "plugins") check_apisix_plugins ;;
        "env") show_env_vars ;;
        "network") check_network ;;
        "health") health_checks ;;
        "resources") show_resources ;;
        "report") 
            show_env_vars
            health_checks
            check_network
            show_service_status
            show_resources
            ;;
        *) 
            echo "Usage: $0 [status|logs|test|routes|plugins|env|network|health|resources|report]"
            exit 1
            ;;
    esac
fi