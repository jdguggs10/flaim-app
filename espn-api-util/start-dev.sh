#!/usr/bin/env bash

# ESPN Fantasy Baseball MCP Server - Development Launcher
# Starts the server in stdio mode for local development and testing

set -e

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define paths
VENV_PATH="$SCRIPT_DIR/.venv"
BASEBALL_MCP_DIR="$SCRIPT_DIR/baseball_mcp"
SERVER_SCRIPT="$BASEBALL_MCP_DIR/baseball_mcp_server.py"

echo "🏃 Starting ESPN Fantasy Baseball MCP Server in development mode..." >&2
echo "📁 Project directory: $SCRIPT_DIR" >&2

# Check if virtual environment exists
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo "❌ Virtual environment not found at $VENV_PATH" >&2
    echo "   Run ./setup.sh first to create the virtual environment" >&2
    exit 1
fi

# Check if server script exists
if [ ! -f "$SERVER_SCRIPT" ]; then
    echo "❌ Server script not found at $SERVER_SCRIPT" >&2
    echo "   Make sure the baseball_mcp directory contains all required files" >&2
    exit 1
fi

# Activate the virtual environment
echo "🔧 Activating virtual environment..." >&2
source "$VENV_PATH/bin/activate"

# Change to the project root directory
cd "$SCRIPT_DIR"

echo "🐍 Python: $(which python)" >&2
echo "📂 Working directory: $(pwd)" >&2
echo "🚀 Starting MCP server in stdio mode..." >&2
echo "" >&2

# Start the MCP server using Poetry
exec poetry run python -m baseball_mcp.baseball_mcp_server