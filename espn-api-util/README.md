# ESPN Fantasy Baseball MCP Server

A comprehensive Model Context Protocol (MCP) server providing seamless access to ESPN Fantasy Baseball data through Claude Desktop and other MCP-compatible AI assistants.

In parallel a **FastAPI rewrite (v2)** is under way.  That version keeps the same tool surface but exposes HTTP endpoints, plus an optional `?stream=true` flag that emits Server-Sent Events (started / progress / done) instead of waiting for the full JSON payload.

## 🚀 Quick Start

### Initial Setup
```bash
cd espn-api-util
./setup.sh                    # Create virtual environment and install dependencies
```

### Development Server
```bash
./start-dev.sh                # Start server in stdio mode for local development
```

### Verification
Ask Claude Desktop to:
- `Use the metadata_get_positions tool to show available positions`
- `Get league info for league ID [your-league-id]`

## 🏗️ Architecture

This server follows a modular architecture optimized for maintainability and extensibility:

### Core Modules
- **`auth.py`** - ESPN authentication (ESPN_S2/SWID cookies)
- **`utils.py`** - League caching, serialization, error handling
- **`metadata.py`** - ESPN constant mappings (positions, stats, activities)

### Data Access Modules
- **`league.py`** - League info, settings, standings, scoreboard
- **`roster.py`** - Team rosters, info, schedules
- **`players.py`** - Player stats, free agents, search
- **`transactions.py`** - All transaction types (trades, waivers, add/drop)
- **`draft.py`** - Draft results and analysis
- **`matchups.py`** - Weekly matchups, boxscores

### Server Entry Point
- **`baseball_mcp_server.py`** - FastMCP server with 40+ registered tools

## 🔐 Authentication (Private Leagues)

### Obtain ESPN Cookies
1. Log into your ESPN Fantasy Baseball league
2. Open browser developer tools (F12)
3. Navigate to Application/Storage → Cookies → espn.com
4. Copy values for `ESPN_S2` and `SWID`

### Store Credentials
```
Use the auth_store_credentials tool with my ESPN_S2 and SWID cookies.
ESPN_S2: 'your_espn_s2_value'
SWID: 'your_swid_value'
```

**Note**: Credentials are session-based and must be re-entered after server restarts.

## 🛠️ Available Tools (40+ Total)

### Authentication
- `auth_store_credentials` - Store ESPN cookies
- `auth_logout` - Clear stored credentials

### League Management
- `league_get_info` - Basic league information
- `league_get_settings` - Detailed league configuration
- `league_get_standings` - Current standings
- `league_get_scoreboard` - Weekly matchup overview

### Team Operations
- `team_get_roster` - Team roster with player details
- `team_get_info` - Team metadata and statistics
- `team_get_schedule` - Season schedule and results

### Player Analysis
- `player_get_stats` - Individual player statistics
- `player_get_free_agents` - Available free agents (filterable)
- `player_get_top_performers` - Top performers by category
- `player_search` - Search players by name
- `player_get_waiver_claims` - Recent waiver activity

### Transaction History
- `transaction_get_recent_activity` - All recent transactions
- `transaction_get_waiver_activity` - Waiver wire moves
- `transaction_get_trade_activity` - Trade activity
- `transaction_get_add_drop_activity` - Add/drop transactions
- `transaction_get_team_transactions` - Team-specific transactions
- `transaction_get_player_history` - Player transaction history
- `transaction_get_lineup_activity` - Lineup changes
- `transaction_get_settings_activity` - League setting changes
- `transaction_get_keeper_activity` - Keeper/dynasty activity

### Draft Analysis
- `draft_get_results` - Complete draft results
- `draft_get_round` - Specific round picks
- `draft_get_team_picks` - Team's draft selections
- `draft_get_analysis` - Draft statistics and insights
- `draft_get_scarcity_analysis` - Position scarcity analysis

### Matchups & Scoring
- `matchup_get_week_results` - Weekly matchup results
- `matchup_get_boxscore` - Detailed matchup breakdown

### Metadata
- `metadata_get_positions` - Position ID mappings
- `metadata_get_stats` - Statistical category mappings
- `metadata_get_activity_types` - Transaction type mappings

## 💻 Development

### Project Structure
```
espn-api-util/
├── baseball_mcp/               # Core MCP server modules
│   ├── baseball_mcp_server.py  # FastMCP server entry point
│   ├── auth.py                # ESPN authentication
│   ├── league.py              # League data tools
│   ├── roster.py              # Team/roster tools
│   ├── players.py             # Player analysis tools
│   ├── transactions.py        # Transaction history tools
│   ├── draft.py               # Draft analysis tools
│   ├── matchups.py            # Matchup/scoring tools
│   ├── metadata.py            # ESPN mappings
│   └── utils.py               # Utilities and error handling
├── .venv/                      # Python virtual environment
├── start-dev.sh               # Development server launcher
├── setup.sh                   # Environment setup script
└── pyproject.toml             # Project dependencies
```

### Adding New Tools
1. Implement function in appropriate module (e.g., `players.py`)
2. Register tool in `baseball_mcp_server.py` using `@mcp.tool()`
3. Follow existing error handling patterns
4. Test with `./start-dev.sh`

### Testing & Debugging
```bash
./start-dev.sh               # Development server with console output
```

## ⚙️ Claude Desktop Integration

### Configuration Files
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Linux**: `~/.config/claude-desktop/claude_desktop_config.json`

### Sample Configuration
```json
{
  "mcpServers": {
    "espn-baseball": {
      "command": "/path/to/espn-api-util/start-dev.sh"
    }
  }
}
```

## 📊 Usage Examples

### Basic League Analysis
```
Get league 123456 standings:
→ league_get_standings(league_id=123456)

Check this week's matchups:
→ league_get_scoreboard(league_id=123456)
```

### Team Management
```
View team 1's roster:
→ team_get_roster(league_id=123456, team_id=1)

Check their recent moves:
→ transaction_get_team_transactions(league_id=123456, team_id=1)
```

### Player Research
```
Find available catchers:
→ player_get_free_agents(league_id=123456, position="C", limit=20)

Search for Mike Trout:
→ player_search(league_id=123456, query="Mike Trout")
```

### Draft Analysis
```
Review complete draft:
→ draft_get_results(league_id=123456)

Analyze position scarcity:
→ draft_get_scarcity_analysis(league_id=123456)
```

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Server not in Claude" | Run `./setup.sh`, configure Claude Desktop manually, restart Claude Desktop |
| "Authentication failed" | Re-authenticate with `auth_store_credentials` tool |
| "Tool not working" | Verify parameters and ensure authentication for private leagues |
| "Python import error" | Run `./setup.sh` to set up virtual environment |
| "Permission denied" | Run `chmod +x start-dev.sh` to make script executable |

## 📋 Requirements

- **Python**: 3.12+
- **Dependencies**: `espn-api>=0.45.0`, `mcp[cli]>=1.5.0`
- **Optional**: Claude Desktop for AI integration

## ⚠️ Important Notes

- **Baseball Only**: This server is specifically for ESPN Fantasy Baseball
- **Session-Based Auth**: Credentials don't persist across server restarts
- **ESPN API Limits**: Be mindful of request rate limits
- **Current Year**: Uses current calendar year for baseball season

## 📄 License

MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- Built on [cwendt94/espn-api](https://github.com/cwendt94/espn-api)
- Uses [Anthropic MCP](https://github.com/anthropics/mcp) framework 