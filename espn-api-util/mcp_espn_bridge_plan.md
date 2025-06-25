# ESPN Fantasy Baseball MCP Bridge  
*A full walkthrough of exposing a `stdio` MCP server over HTTP using Apache APISIX*

> Status – June 25, 2025: bridge works end-to-end.  `GET /espn-bb/sse` streams; tool calls succeed via JSON-RPC.  Bridge is operational and ready for production deployment.

---

## 1  Why a "bridge" at all?
The ESPN Fantasy Baseball service is already implemented as a **Model Context Protocol (MCP) server** in Python.  MCP clients (Claude Desktop, Cursor, Cline, etc.) talk to it through **stdin/stdout**. That is perfect for local workflows but useless when you need an HTTPS endpoint for a browser or for the Go Orchestrator running in prod.

Re-writing the server for HTTP would break authentication as ESPN prevents HTTP API access, only python can carry the cookie credentials correctly.  Instead we **insert an API gateway that translates HTTP ⇄ stdio**:

```
 HTTP(S)              (mcp-bridge plugin)           STDIO
┌──────────┐          ┌───────────────────┐         ┌─────────────┐
│ client   │ ⇆ JSON →│   Apache APISIX    │ ⇆ text │ python mcp  │
└──────────┘   SSE ← │ ‑- mcp-bridge ‑-  │ ← text │  server     │
                    └───────────────────┘         └─────────────┘
```

## 2  High-level call flow
1. Client opens **`GET /espn-bb/sse`** – APISIX keeps the TCP connection open and immediately sends:
   ```
   event: endpoint
   data: /espn-bb/message?sessionId=<uuid>
   ```
2. Client POSTs a JSON-RPC payload (e.g. `{ "method":"tools/list" }`) to that `/message?...` URL.
3. `mcp-bridge` writes the JSON frame to the Python process' **stdin**.
4. The Python server writes results on **stdout** – the plugin streams them back to the caller over the same SSE channel.

*Multiple* HTTP callers share the same Python process; the plugin demuxes messages by `sessionId`.

## 3  Container build from scratch
We cannot use the stock `apache/apisix:3.12-ai` image (doesn't exist) and the default `apache/apisix:dev` image ships with Debian 11 (Python 3.9).  So we compile Python 3.11 in a multi-stage Dockerfile.

```dockerfile
######## 1 – build Python ###############
FROM apache/apisix:dev AS builder
RUN apt-get update && \
    apt-get install -y build-essential libssl-dev zlib1g-dev libreadline-dev \
                   libbz2-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
                   libxml2-dev libxmlsec1-dev libffi-dev && \
    curl -sSL https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz | tar xz && \
    cd Python-3.11.9 && \
    ./configure --enable-optimizations --enable-shared && \
    make -j$(nproc) && make install && \
    python3.11 -m ensurepip && \
    pip install --no-cache-dir poetry==1.8.3 && \
    mkdir /srv

######## 2 – runtime ###############
FROM apache/apisix:dev
# Lua can't find lyaml without these:
ENV LUA_PATH="/usr/local/apisix/deps/share/lua/5.1/?.lua;/usr/local/apisix/deps/share/lua/5.1/?/init.lua;;" \
    LUA_CPATH="/usr/local/apisix/deps/lib/lua/5.1/?.so;;" \
    PYTHONUNBUFFERED=1 PYTHONPATH=/srv

COPY --from=builder /usr/local/bin/python3.11 /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.11 /usr/local/lib/python3.11

# project source (assumes we're at repo root)
COPY espn-api-util/baseball_mcp /srv/baseball_mcp
COPY espn-api-util/conf /usr/local/apisix/conf
COPY espn-api-util/pyproject.toml espn-api-util/poetry.lock /srv/

RUN pip3.11 install --no-cache-dir poetry==1.8.3 && \
    cd /srv && poetry config virtualenvs.create false && poetry install --only main --no-interaction

EXPOSE 9080 9180
CMD ["/usr/local/apisix/docker/run.sh"]
```

## 4  APISIX YAML (stand-alone, no etcd)
`espn-api-util/conf/config.yaml`
```yaml
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
apisix:
  enable_admin: false           # read config only from YAML
  node_listen: 9080
plugins:
  - cors
  - mcp-bridge
  - server-info
```

`espn-api-util/conf/apisix.yaml` (only the relevant route)
```yaml
routes:
  - id: espn-bb-mcp-bridge
    name: "ESPN Fantasy Baseball MCP Bridge"
    uri: /espn-bb/*
    methods:
      - GET
      - POST
      - OPTIONS
    plugins:
      cors:
        allow_origins: "*"
        allow_methods: "GET,POST,OPTIONS"
        allow_headers: "Authorization,Content-Type,Accept"
        allow_credentials: true
        max_age: 86400
      mcp-bridge:
        base_uri: "/espn-bb"
        command: "/bin/sh"
        args:
          - "-c"
          - "ESPN_S2=$ESPN_S2 SWID=$SWID LEAGUE_ID=$LEAGUE_ID PYTHONPATH=/srv PYTHONUNBUFFERED=1 exec /usr/local/bin/python3.11 -m baseball_mcp.baseball_mcp_server"
    upstream:          # dummy upstream required by schema
      type: roundrobin
      nodes:
        - host: 127.0.0.1
          port: 1
          weight: 1
#END
```
Note the **dummy upstream** – APISIX insists every route has one even if the plugin never forwards.

## 5  Running it locally
```bash
cd espn-api-util

# Setup: Create .env file with ESPN credentials (required)
cp .env.example .env  # Edit with your ESPN_S2, SWID, LEAGUE_ID

./start-bridge.sh --rebuild       # wrapper around docker-compose build up -d

# open a second terminal
curl -N http://localhost:9080/espn-bb/sse
# copy the sessionId from the 'data:' field of the 'endpoint' event

curl -X POST -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"tools/list","id":"1"}' \
     "http://localhost:9080/espn-bb/message?sessionId=<id>"
     
# Response streams back on the SSE connection from the first curl command
```

## 6  Common failure modes & fixes
| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `404 Not Found` & CORS headers on `/espn-bb/*` | Route matched but plugin exited (bad command) *or* missing upstream | Check `/usr/local/apisix/logs/error.log`. Verify `python3.11 -m baseball_mcp.baseball_mcp_server` runs.  Ensure upstream block present. |
| `/sse` hangs forever | Python process failed to start | Tail error log, fix import paths. |
| `/message …` returns 500 | ESPN cookies absent or expired | Supply fresh `ESPN_S2`, `SWID`, `LEAGUE_ID`. |

## 7  CI smoke-test (inside container)
```bash
python3.11 -m baseball_mcp.baseball_mcp_server --help   # returns 0
curl -s http://localhost:9080/apisix/status | jq .status.total   # should print a number
```

## 8  Roadmap
* Add Prometheus scrape of `/srv/metrics` once the Python side exports them.
* Sticky sessions on the LB so SSE connections stay on the same APISIX node.
* Scripted credential rotation via Kubernetes secret + rolling reload.

---
*Document last updated: 25 Jun 2025 after successful bridge deployment and testing.*