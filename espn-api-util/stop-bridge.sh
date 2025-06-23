#!/bin/bash

# ESPN Fantasy Baseball MCP Bridge - Stop Script
# Gracefully stops all bridge services and cleans up resources

set -e

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🛑 Stopping ESPN Fantasy Baseball MCP Bridge...${NC}"

# Function to stop services gracefully
stop_services() {
    echo "📋 Stopping services..."
    
    if docker-compose ps -q | grep -q .; then
        docker-compose down
        echo -e "${GREEN}✅ Services stopped${NC}"
    else
        echo -e "${YELLOW}⚠️ No services were running${NC}"
    fi
}

# Function to clean up resources
cleanup_resources() {
    local cleanup_volumes="$1"
    
    if [ "$cleanup_volumes" = "true" ]; then
        echo "🧹 Cleaning up volumes and networks..."
        
        # Remove volumes
        docker volume rm espn-mcp-apisix-logs espn-mcp-etcd-data espn-mcp-prometheus-data 2>/dev/null || true
        
        # Remove network
        docker network rm espn-mcp-bridge 2>/dev/null || true
        
        echo -e "${GREEN}✅ Cleanup complete${NC}"
    else
        echo -e "${YELLOW}💾 Volumes preserved (use --clean to remove)${NC}"
    fi
}

# Function to show final status
show_status() {
    echo "📊 Final status:"
    
    # Check if any containers are still running
    if docker ps --filter "name=espn-mcp" --format "{{.Names}}" | grep -q .; then
        echo -e "${RED}❌ Some containers are still running:${NC}"
        docker ps --filter "name=espn-mcp" --format "table {{.Names}}\t{{.Status}}"
    else
        echo -e "${GREEN}✅ All containers stopped${NC}"
    fi
    
    # Check for remaining volumes
    volumes=$(docker volume ls --filter "name=espn-mcp" --format "{{.Name}}" | wc -l)
    if [ "$volumes" -gt 0 ]; then
        echo -e "${YELLOW}💾 $volumes volumes preserved${NC}"
    fi
}

# Parse command line arguments
CLEAN_VOLUMES=false
FORCE_STOP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_VOLUMES=true
            shift
            ;;
        --force)
            FORCE_STOP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --clean   Remove volumes and networks"
            echo "  --force   Force stop containers"
            echo "  --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Stop services
if [ "$FORCE_STOP" = "true" ]; then
    echo "⚡ Force stopping containers..."
    docker-compose kill 2>/dev/null || true
    docker-compose rm -f 2>/dev/null || true
else
    stop_services
fi

# Cleanup if requested
cleanup_resources "$CLEAN_VOLUMES"

# Show final status
show_status

echo
echo -e "${GREEN}🎉 ESPN Fantasy Baseball MCP Bridge stopped successfully!${NC}"
echo

if [ "$CLEAN_VOLUMES" = "false" ]; then
    echo "💡 Tips:"
    echo "   To remove all data: $0 --clean"
    echo "   To restart quickly: ./start-bridge.sh"
    echo
fi