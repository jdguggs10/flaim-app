#!/bin/bash

# ESPN Fantasy Baseball MCP Server Setup Script
# Creates virtual environment and installs dependencies

set -e

echo "🏗️ Setting up ESPN Fantasy Baseball MCP Server..."

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
REQUIRED_VERSION="3.12"

if [[ "$(echo "$PYTHON_VERSION < $REQUIRED_VERSION" | bc -l 2>/dev/null || echo "1")" == "1" ]]; then
    echo "❌ Python $REQUIRED_VERSION or higher is required. Found: $PYTHON_VERSION"
    exit 1
fi

echo "✅ Python version check passed: $PYTHON_VERSION"

# Create virtual environment
if [ ! -d ".venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv .venv
else
    echo "✅ Virtual environment already exists"
fi

# Activate virtual environment
echo "🔄 Activating virtual environment..."
source .venv/bin/activate

# Upgrade pip
echo "⬆️ Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "📥 Installing dependencies..."
if [ -f "pyproject.toml" ]; then
    pip install -e .
else
    echo "❌ pyproject.toml not found"
    exit 1
fi

# Make scripts executable
echo "🔧 Setting script permissions..."
chmod +x start-dev.sh 2>/dev/null || true

# Create VS Code settings
echo "🆚 Configuring VS Code settings..."
mkdir -p .vscode
cat > .vscode/settings.json << EOF
{
    "python.defaultInterpreterPath": "./.venv/bin/python3",
    "python.terminal.activateEnvironment": true,
    "python.analysis.extraPaths": [
        "./.venv/lib/python3.12/site-packages"
    ]
}
EOF

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  ./start-dev.sh                # Start development server"
echo "  Configure Claude Desktop manually (see README.md for instructions)"
echo ""