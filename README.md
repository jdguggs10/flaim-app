# Fantasy League AI Manager (FLAIM)

FLAIM is an **AI-powered assistant for fantasy sports**.  The system is split into four loosely-coupled layers so each piece can evolve (or scale) independently:

1. **Front-ends** – Next.js web app & SwiftUI iOS app
2. **AI Orchestrator** – stateless Go service that drives the LLM (OpenAI / Claude) and performs the function-calling loop
3. **Data micro-services** – small REST/MCP services that fetch live data from fantasy providers (ESPN, Yahoo, Sleeper …)
4. **Storage & Auth** – Postgres for user data / tokens and Clerk for authentication  
  - Clerk handles user sign-in; ESPN session tokens (`s2`, `swid`) and league IDs are stored encrypted in Postgres

```text
Browser / iOS
        │            (Bearer JWT)
        ▼
Front-end chat UI ──► POST /chat ──► Go Orchestrator (LLM agent)
                           ▲ function-call
                           │
                           ▼
Fantasy data micro-services (MCP / Python)
```

## Prerequisites

- Node 18+ & npm or yarn
- Python 3.11 & Poetry
- Go 1.21+
- Clerk account & Postgres database

## Repository layout

This mono-repo currently houses **one** data micro-service – an ESPN Fantasy Baseball MCP server that is fronted by Apache APISIX via the `mcp-bridge` plugin.

```
flaim-app/
└── espn-api-util/         # ESPN Baseball micro-service (Python)
```

*Full details & commands live in* `espn-api-util/README.md`.  In short:

```bash
# Start the MCP server locally (stdio mode)
cd espn-api-util && ./setup.sh && ./start-dev.sh
```

### Production / HTTP bridge (APISIX)

If you want the ESPN micro-service reachable over the network—e.g. by the Go orchestrator or a web client—run it behind Apache APISIX using the *mcp-bridge* plugin.  The repo already contains a turnkey setup:

```bash
# inside espn-api-util/
./start-bridge.sh            # spins up APISIX + the MCP container

# Once the containers are healthy open an SSE stream and call a tool:
#
#   curl -N http://localhost:9080/espn-bb/sse
#
#   # copy the sessionId from the `data:` line, then:
#   curl -X POST -H "Content-Type: application/json" \
#        -d '{"jsonrpc":"2.0","method":"tools/list","id":"1"}' \
#        "http://localhost:9080/espn-bb/message?sessionId=<id>"
#
# The JSON tool index will arrive back on the open SSE stream.
```

The full build + deployment rationale lives in `espn-api-util/mcp_espn_bridge_plan.md`.

Other components (front-ends, orchestrator, additional providers) will live in their own repos and talk to this service over HTTPS.

## Roadmap snapshot

| Area | Status |
|------|--------|
| Web front-end (Next.js 13 + Vercel AI SDK) | scaffolded ✔︎ |
| iOS front-end (SwiftUI + Exyte Chat) | prototype ✔︎ |
| Go orchestrator w/ OpenAI function calling | WIP |
| ESPN Baseball micro-service (this repo) | MCP ✔︎ (exposed via APISIX) |
| Yahoo / Sleeper services | planned |

Production deploy runs the MCP container behind **Apache APISIX** configured with the `mcp-bridge` plugin.  The gateway converts HTTP requests to MCP frames and streams the results back to clients via **Server-Sent Events (SSE)**.  Secrets (`ESPN_S2`, `SWID`, `LEAGUE_ID`) are injected as environment variables and rotated by the deployment pipeline.

---
© 2024 FLAIM