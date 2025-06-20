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
Fantasy data micro-services (FastAPI / Python)
```

## Prerequisites

- Node 18+ & npm or yarn
- Python 3.11 & Poetry
- Go 1.21+
- Clerk account & Postgres database

## Repository layout

This mono-repo currently houses **one** data micro-service – an ESPN Fantasy Baseball service that is being upgraded from an MCP stdio server to a RESTful FastAPI container.

```
flaim-app/
└── espn-api-util/         # ESPN Baseball micro-service (Python)
```

*Full details & commands live in* `espn-api-util/README.md`.  In short:

```bash
# MCP (legacy, stable)
cd espn-api-util && ./setup.sh && ./start-dev.sh

# FastAPI (in progress)
cd espn-api-util && poetry install && poetry run uvicorn app.main:app --reload
```

Other components (front-ends, orchestrator, additional providers) will live in their own repos and talk to this service over HTTPS.

## Roadmap snapshot

| Area | Status |
|------|--------|
| Web front-end (Next.js 13 + Vercel AI SDK) | scaffolded ✔︎ |
| iOS front-end (SwiftUI + Exyte Chat) | prototype ✔︎ |
| Go orchestrator w/ OpenAI function calling | WIP |
| ESPN Baseball micro-service (this repo) | v1 MCP ✔︎, v2 FastAPI 🚧 |
| Yahoo / Sleeper services | planned |

Once the FastAPI rewrite hits parity the Docker image will publish to AWS ECR and run on ECS/Fargate behind an ALB.  Credentials are env-vars today but the code is layered so Secrets Manager can be dropped in later.

Once the FastAPI service is live **every endpoint accepts `?stream=true`**.
When that flag is present the response is sent as **Server-Sent Events** with frames:
`started` → zero or more `progress` → `done` / `error` plus a heartbeat comment every 25 s.
The Go orchestrator consumes the stream and relays it to the web / iOS UIs so users see live status while the LLM reasons.

#### Testing streaming endpoints

```bash
curl -N http://localhost:8000/roster?league_id=YOUR_LEAGUE_ID&stream=true
```

---
© 2024 FLAIM