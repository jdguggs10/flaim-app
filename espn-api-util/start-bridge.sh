#!/bin/bash

# ESPN Fantasy Baseball MCP Bridge - Startup Script
# Starts the complete MCP bridge stack with APISIX gateway

set -e

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting ESPN Fantasy Baseball MCP Bridge..."
echo "📁 Working directory: $SCRIPT_DIR"

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ .env file not found!"
    echo "   Copy .env.example to .env and fill in your ESPN credentials:"
    echo "   cp .env.example .env"
    exit 1
fi

# Load environment variables
echo "🔧 Loading environment variables..."
set -a
source .env
set +a

# Verify required environment variables
REQUIRED_VARS=("ESPN_S2" "SWID" "LEAGUE_ID")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Required environment variable $var is not set in .env"
        exit 1
    fi
done

echo "✅ Environment variables loaded successfully"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker is running"

# Check if docker-compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ docker-compose not found. Please install Docker Compose."
    exit 1
fi

# Parse command line arguments
REBUILD=false
DEV_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            REBUILD=true
            shift
            ;;
        --dev)
            DEV_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--rebuild] [--dev]"
            echo "  --rebuild  Force rebuild of Docker images"
            echo "  --dev      Use development mode with live code mounting"
            exit 1
            ;;
    esac
done

# Build and start services
if [ "$DEV_MODE" = true ]; then
    echo "🚀 Starting in development mode..."
    docker-compose down --remove-orphans
    docker-compose --profile development up -d apisix-dev
else
    echo "🏗️ Building and starting production services..."
    docker-compose down --remove-orphans
    
    if [ "$REBUILD" = true ]; then
        echo "🔄 Force rebuilding images..."
        docker-compose build --no-cache apisix
    else
        docker-compose build apisix
    fi
    
    docker-compose up -d apisix
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🏥 Checking service health..."

# Check APISIX
if curl -f -s http://localhost:9080/apisix/status >/dev/null; then
    echo "✅ APISIX is healthy"
else
    echo "❌ APISIX is not healthy"
    if [ "$DEV_MODE" = true ]; then
        docker-compose logs apisix-dev
    else
        docker-compose logs apisix
    fi
fi

echo ""
echo "🎉 ESPN Fantasy Baseball MCP Bridge is now running!"
echo ""
if [ "$DEV_MODE" = true ]; then
    echo "🔧 Development Mode Active:"
    echo "   Live code changes will be reflected immediately"
    echo "   Logs: docker-compose logs -f apisix-dev"
else
    echo "🏭 Production Mode Active:"
    echo "   Using baked-in Docker image"
    echo "   Logs: docker-compose logs -f apisix"
fi
echo ""
echo "📊 Service URLs:"
echo "   MCP Bridge API: http://localhost:9080/espn-bb"
echo "   APISIX Status:  http://localhost:9080/apisix/status"
echo ""
echo "🧪 Test the bridge:"
echo "   ./test-bridge.sh"
echo ""
echo "🛑 Stop services:"
echo "   docker-compose down"
echo ""
echo "💡 Options:"
echo "   ./start-bridge.sh --dev      # Development mode with live code"
echo "   ./start-bridge.sh --rebuild  # Force rebuild images"
echo ""