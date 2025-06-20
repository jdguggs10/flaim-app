# ESPN Fantasy Baseball FastAPI Migration & Fargate Deployment Plan

## Migration Todo List

### Phase 1: Project Structure & Foundation
1. **Create FastAPI directory structure** (`app/`, `app/tools/`, etc.)
2. **Set up pyproject.toml** with FastAPI dependencies (fastapi, uvicorn, sse-starlette, pydantic)
3. **Create app/deps.py** with league dependency injection using environment variables
4. **Create basic app/main.py** FastAPI application skeleton

### Phase 2: Core Infrastructure
5. **Implement SSE streaming infrastructure** (EventSourceResponse wrapper)
6. **Port utils.py functionality** (error handling, serialization helpers)
7. **Port metadata.py constants** (position maps, stats maps, activity maps)
8. **Create Dockerfile** for production deployment

### Phase 3: Tool Migration (40+ endpoints)
9. **Port Authentication tools** (remove session-based auth, use env vars)
10. **Port League Management tools** (4 endpoints: info, settings, standings, scoreboard)
11. **Port Team Operations tools** (3 endpoints: roster, info, schedule)
12. **Port Player Analysis tools** (5 endpoints: stats, free_agents, top_performers, search, waiver_claims)
13. **Port Transaction tools** (9 endpoints: recent_activity, waiver, trade, add_drop, team, player_history, lineup, settings, keeper)
14. **Port Draft Analysis tools** (5 endpoints: results, round, team_picks, analysis, scarcity)
15. **Port Matchup tools** (2 endpoints: week_results, boxscore)
16. **Port Metadata tools** (3 endpoints: positions, stats, activity_types)

### Phase 4: Testing & Validation
17. **Set up local development environment** with poetry
18. **Test all endpoints locally** with curl commands
19. **Verify SSE streaming** works with `?stream=true` parameter
20. **Compare MCP vs FastAPI responses** for data consistency

### Phase 5: Deployment Preparation
21. **Create AWS ECR repository**
22. **Build and test Docker image locally**
23. **Set up ECS cluster and task definition**
24. **Configure Application Load Balancer** (360s timeout for SSE)
25. **Set up environment variables** (ESPN_S2, SWID, LEAGUE_ID)

### Phase 6: Deployment & CI/CD
26. **Deploy to AWS Fargate**
27. **Run production smoke tests**
28. **Create GitHub Actions workflow** for automated deployment
29. **Update documentation** to reflect new FastAPI endpoints

### Phase 7: Cleanup & Future-Proofing
30. **Add observability** (health checks, basic logging)
31. **Document API endpoints** (OpenAPI/Swagger)
32. **Prepare for Secrets Manager integration** (abstraction layer)
33. **Archive old MCP server** once FastAPI is validated

**Project Status:** Initial development - no existing users, MCP server does not need to remain functional during transition.

**Estimated Timeline:** 2-3 days of focused development

---

## TL;DR  
Migrate the current ESPN Fantasy Baseball MCP server (40+ tools) to a FastAPI HTTP service. Replace the MCP stdio protocol with idiomatic RESTful JSON endpoints (one per tool) **optionally streamed via Server-Sent Events (`?stream=true`) that report started / progress / done frames**. Ship it in a slim Docker image (`python:3.12-slim`) running `uvicorn --workers 2`. Deploy to Amazon ECR → ECS/Fargate behind an Application Load Balancer **(idle-timeout 360 s for long SSE sockets)**. Hard-code personal `ESPN_S2`, `SWID`, and `LEAGUE_ID` as environment variables for single-user access, but keep a thin abstraction layer so the same credentials can later be pulled from AWS Secrets Manager. Future: Optional Clerk/JWT middleware. CI/CD via GitHub Actions.

---

## 1  Directory bootstrap  

```
espn-api-util/
├─ app/
│  ├─ __init__.py
│  ├─ main.py          # FastAPI entry-point
│  ├─ deps.py          # cookie injector / future Clerk JWT
│  └─ tools/
│     ├─ league.py
│     ├─ roster.py
│     └─ …
├─ Dockerfile
└─ pyproject.toml
```

---

## 2  FastAPI skeleton (hard-coded cookies)  

```python
# app/deps.py
from functools import lru_cache
from espn_api.baseball import League
import os
import datetime

@lru_cache
def get_league():
    current_year = datetime.datetime.now().year
    return League(
        league_id=int(os.getenv("LEAGUE_ID")),
        year=current_year,  # Baseball season runs spring-fall in same calendar year
        espn_s2=os.getenv("ESPN_S2"),
        swid=os.getenv("SWID"),
    )
```

```python
# app/main.py
from fastapi import FastAPI, Depends
from pydantic import BaseModel
from .deps import get_league

app = FastAPI(title="ESPN-Baseball-API")

class TeamRosterRequest(BaseModel):
    team_id: int

@app.get("/league/standings")
async def league_get_standings(league = Depends(get_league)):
    """Return current league standings."""
    return league.standings()

@app.post("/team/roster")
async def team_get_roster(payload: TeamRosterRequest, league = Depends(get_league)):
    """Return roster for the given team_id (1-based)."""
    if not 1 <= payload.team_id <= len(league.teams):
        return {"ok": False, "error": "team_id out of range"}
    roster_data = league.teams[payload.team_id - 1].roster
    return {"ok": True, "data": roster_data}

# … replicate the remaining 40+ tool functions as first-class REST handlers …
```

---

## 2.5  SSE status channel (optional)

* Pass `?stream=true` to any endpoint to upgrade the response to **text/event-stream**.
* Frames: `started` → zero or more `progress` `{pct}` → `done` / `error`.
* Heartbeat comment (`: 💓\n\n`) every 25 s keeps ALB / browser connection alive.
* Example request:

```bash
curl -N -H "Accept: text/event-stream" \
     -X POST http://localhost:8000/team/roster?stream=true \
     -d '{"team_id":1}'
```

FastAPI snippet:
```python
from sse_starlette.sse import EventSourceResponse

@app.post("/team/roster")
async def team_get_roster(payload: TeamRosterRequest, league=Depends(get_league)):
    async def stream():
        yield {"event": "started", "data": {"tool": "team_get_roster"}}
        # long-running work simulated here
        roster = league.teams[payload.team_id - 1].roster
        yield {"event": "done", "data": roster}
    return EventSourceResponse(stream())
```

ALB / Uvicorn knobs:
* ALB idle-timeout 360 s
* `uvicorn --timeout-keep-alive 75`

---

## 3  Local test run  

```bash
poetry install                      # install deps from pyproject.toml
uvicorn app.main:app --reload  # dev mode
curl -X POST http://localhost:8000/team/roster -d '{"team_id":1}' -H "Content-Type: application/json"
curl http://localhost:8000/league/standings
```

---

## 4  Production-grade Dockerfile  

```Dockerfile
FROM python:3.12-slim
WORKDIR /app

# Install Poetry and project dependencies
RUN pip install --no-cache-dir poetry
COPY pyproject.toml poetry.lock* ./
RUN poetry config virtualenvs.create false \
    && poetry install --only main --no-interaction --no-ansi

COPY app ./app
EXPOSE 80
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80", "--workers", "2"]
```

---

## 5  AWS ECR push  

```bash
aws ecr create-repository --repository-name espn-baseball-api
docker build -t espn-baseball-api:latest .
docker tag espn-baseball-api:latest <acct>.dkr.ecr.<region>.amazonaws.com/espn-baseball-api:latest
aws ecr get-login-password | docker login --username AWS --password-stdin <acct>.dkr.ecr.<region>.amazonaws.com
docker push <acct>.dkr.ecr.<region>.amazonaws.com/espn-baseball-api:latest
```

---

## 6  Fargate launch (console or IaC)  

1. **ECS Cluster** → *Networking-only (Fargate)*  
2. **Task definition**  
   * 0.25 vCPU / 0.5 GB RAM  
   * Env-vars: `ESPN_S2`, `SWID`, `LEAGUE_ID`  
3. **Service** → attach an **Application Load Balancer**; path rule `/` → target-group(port 80)  
4. **Security group**: inbound 443, outbound anywhere  

*(Terraform later if you prefer)*  

---

## 7  CI/CD (optional but nice)  

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Fargate
on:
  push:
    branches: [ main ]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: <acct>.dkr.ecr.<region>.amazonaws.com
          ...
      - uses: aws-actions/amazon-ecs-render-task-definition@v1
      - uses: aws-actions/amazon-ecs-deploy-task-definition@v1
```

---

## 8  Smoke test in prod  

```bash
curl https://baseball-api.yourdomain.com/team/roster -d '{"team_id":1}' -H "Content-Type: application/json"
curl https://baseball-api.yourdomain.com/league/standings
```

---

## 9  Migration from Current MCP Server

### Tools to Migrate (40+ total)
* **Authentication**: `auth_store_credentials` → Environment variables
* **League Management**: `league_get_info`, `league_get_settings`, `league_get_standings`, `league_get_scoreboard`
* **Team Operations**: `team_get_roster`, `team_get_info`, `team_get_schedule`
* **Player Analysis**: `player_get_stats`, `player_get_free_agents`, `player_search`, etc.
* **Transactions**: All transaction history tools
* **Draft Analysis**: `draft_get_results`, `draft_get_analysis`, etc.
* **Matchups**: `matchup_get_week_results`, `matchup_get_boxscore`
* **Metadata**: `metadata_get_positions`, `metadata_get_stats`, etc.

### Future Enhancements
* **Clerk JWT middleware** for multi-user access (currently single-user)
* **Encrypted credential storage** (AWS Secrets Manager)
* **Observability** via OpenTelemetry + CloudWatch
* **Rate limiting** and caching for ESPN API calls

---

### Ship it 🚀