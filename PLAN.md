# Go Log Simulator — Master Plan

> Compatible: Claude Code · Kiro · Codex · Antigravity
> Status: Ready for implementation
> Base: statucred-logs-example (Java → Go port)

---

## Architecture

```
Browser ──POST /api/run/{id}──► Go HTTP Server ──exec.Command──► scenarios/0N/main.go
                                      │                                    │
                                      │◄──── stdout (JSON lines) ──────────┘
                                      │
                                      ├── SSE stream ──► Browser
                                      └── tee ──► logs/sim-<id>.log
                                                        │
                                              Filebeat (tagged: scenario_id=<id>)
                                                        │
                                                   Logstash
                                                        │
                                              index: sim-<id>
                                                        │
                                                 Elasticsearch
                                                        │
                                        Kibana (per-scenario dashboard)
```

**Stack:** Go 1.22 stdlib only · vanilla HTML/JS · ELK 8.12.0 · Docker Compose

---

## Project Structure

```
go-simulator/
├── PLAN.md
├── agents/
│   ├── README.md
│   ├── core-builder.md
│   ├── scenario-implementor.md
│   ├── kibana-expert.md
│   ├── demo-expert.md
│   └── qa-agent.md
│
├── scenarios/
│   ├── README.md                    ← scenario index
│   └── 0N-name/
│       ├── main.go                  ← standalone Go binary (scenario-implementor)
│       ├── setup.sh                 ← create index template, dashboard, alerts (kibana-expert)
│       ├── reset.sh                 ← delete this scenario's index + kibana objects (kibana-expert)
│       ├── dashboard.ndjson         ← importable Kibana saved objects (kibana-expert)
│       ├── discover_url.md          ← pre-built Kibana Discover URL (kibana-expert)
│       ├── README.md                ← what/why/how (demo-expert)
│       ├── verbal_script.md         ← live demo script (demo-expert)
│       └── notebooklm_prompt.md     ← paste-ready NotebookLM prompt (demo-expert)
│
├── scripts/
│   ├── setup-all.sh                 ← runs all scenarios/*/setup.sh
│   └── reset-all.sh                 ← runs all scenarios/*/reset.sh
│
├── internal/
│   ├── logger/logger.go             ← slog JSON logger with timezone + time injection
│   └── scenarios/registry.go        ← metadata only (ID, Name, BinPath, etc.)
│
├── cmd/server/
│   ├── main.go                      ← HTTP server, exec runner, SSE
│   └── scenarios_init.go            ← registers scenario metadata
│
├── web/index.html                   ← single-page UI (embedded)
│
├── elk/
│   ├── filebeat/filebeat.yml        ← 5 inputs, one per scenario log file
│   ├── kibana/kibana.yml
│   └── logstash/logstash.conf       ← routes per scenario_id → sim-<id> index
│
├── docker-compose.yml
├── Dockerfile                       ← builds server + all 5 scenario binaries
├── Makefile
├── go.mod
└── .env.example
```

---

## Scenarios

| # | ID | Trigger | Key Fields | Log Pattern |
|---|----|---------|-----------|------------|
| 01 | auth-brute-force | login hammering | user_id, ip_address, attempt_count, error_code | 5×WARN → 1×ERROR |
| 02 | payment-decline | gateway failure | user_id, order_id, amount, gateway, error_code | 1×INFO + 7×ERROR + 1×WARN |
| 03 | db-slow-query | missing index | db_host, table_name, duration_ms, sla_breach | 3×INFO → 5×WARN → 2×ERROR |
| 04 | cache-stampede | TTL expiry | cache_key, cache_hit, latency_ms, db_fallback | 2×INFO → 7×WARN → 2×ERROR → 1×INFO |
| 05 | api-degradation | upstream degradation | endpoint, status_code, latency_ms, retry_count | 3×INFO → 4×WARN → 3×ERROR |

Full log sequences: see `agents/scenario-implementor.md`

---

## Scenario Execution Model

Each scenario is a **standalone Go binary** built from `scenarios/0N-name/main.go`.

### Binary flags
```
--tz=Asia/Kolkata        timezone for log timestamps (default: Asia/Kolkata / IST)
--compress-time          compress simulated time window into actual run (fast emit, spread timestamps)
--time-window=30m        simulated time span to compress (default: 30m)
--log-file=<path>        file to write logs to (in addition to stdout)
```

### Time compression
- **Without `--compress-time`:** logs emitted in real time with real delays, timestamps = now (IST)
- **With `--compress-time`:** logs emitted at 300ms intervals (fast), each log timestamp = `startTime + i × (timeWindow/logCount)`
- This lets a 30-min attack compressed into 6 seconds show a meaningful timeline in Kibana

### Timestamp format
All timestamps in **IST (Asia/Kolkata, UTC+5:30)** in RFC3339 format:
```
2026-04-10T15:30:45+05:30
```

### Logstash: use log timestamp, not ingestion time
```ruby
date {
  match => ["[go_json][time]", "ISO8601"]
  target => "@timestamp"
  timezone => "Asia/Kolkata"
}
```

### Web server runs scenario
```go
cmd := exec.CommandContext(ctx, binPath, "--tz=Asia/Kolkata", "--compress-time",
                                         "--log-file=logs/sim-"+id+".log")
cmd.Stdout = sseWriter  // each JSON line → SSE data event
cmd.Start()
```

---

## Per-Scenario Index

Each scenario writes to its own Elasticsearch index: `sim-<scenario-id>`

| Scenario | ES Index | Kibana Index Pattern |
|----------|----------|---------------------|
| auth-brute-force | `sim-auth-brute-force` | `sim-auth-brute-force*` |
| payment-decline | `sim-payment-decline` | `sim-payment-decline*` |
| db-slow-query | `sim-db-slow-query` | `sim-db-slow-query*` |
| cache-stampede | `sim-cache-stampede` | `sim-cache-stampede*` |
| api-degradation | `sim-api-degradation` | `sim-api-degradation*` |

Logstash routes via `scenario_id` tag set by Filebeat:
```ruby
output {
  if [scenario_id] == "auth-brute-force" {
    elasticsearch { index => "sim-auth-brute-force" }
  }
  # ... etc
}
```

---

## Per-Scenario Log Files

Each scenario binary writes to its own log file (tee'd from stdout):

| Scenario | Log File |
|----------|---------|
| auth-brute-force | `logs/sim-auth-brute-force.log` |
| payment-decline | `logs/sim-payment-decline.log` |
| db-slow-query | `logs/sim-db-slow-query.log` |
| cache-stampede | `logs/sim-cache-stampede.log` |
| api-degradation | `logs/sim-api-degradation.log` |

Filebeat watches each file independently, tags with `scenario_id`.

---

## Comprehensive Kibana Dashboards

Each scenario dashboard has **6 panels** covering the full incident picture:

| Panel | Type | Shows |
|-------|------|-------|
| 1 Incident Timeline | Area chart (stacked, by level) | Log volume over time — shows incident escalation |
| 2 Error Rate | Gauge / Big Number | % of ERROR logs in window |
| 3 Level Distribution | Donut chart | INFO / WARN / ERROR breakdown |
| 4 Scenario Metric A | Line chart | Primary numeric field over time (scenario-specific) |
| 5 Scenario Metric B | Bar / Pie | Key categorical field distribution (scenario-specific) |
| 6 Recent Events | Data table | Last 20 log entries with key fields as columns |

Per-scenario panel 4 + 5:

| Scenario | Panel 4 | Panel 5 |
|----------|---------|---------|
| 01 auth | `attempt_count` line chart | `error_code` bar (INVALID_PASSWORD vs ACCOUNT_LOCKED) |
| 02 payment | `amount` (failed transactions) | `gateway` breakdown (stripe vs paypal) |
| 03 db | `duration_ms` line chart | `sla_breach` true/false ratio |
| 04 cache | `latency_ms` line chart | `cache_hit` true/false ratio |
| 05 api | `latency_ms` line chart | `status_code` distribution |

---

## Per-Scenario Scripts

Each scenario folder has:

### setup.sh
- Creates ES index template for `sim-<id>` (field mappings)
- Imports `dashboard.ndjson` via Kibana Saved Objects API
- Creates 2 alert rules via Kibana Alerting API
- Idempotent (safe to run multiple times)

### reset.sh
- Deletes ES index: `DELETE /sim-<id>`
- Deletes Kibana saved objects for this scenario (dashboard + visualizations + index pattern)
- Deletes Kibana alert rules for this scenario
- Flags: `--dry-run`

### scripts/setup-all.sh
```bash
for dir in scenarios/0*/; do bash "$dir/setup.sh"; done
```

### scripts/reset-all.sh
```bash
for dir in scenarios/0*/; do bash "$dir/reset.sh"; done
```

---

## API

```
GET  /                  → index.html
GET  /api/scenarios     → [{id,name,description,duration_sec,log_count,index,compress_time_default}]
POST /api/run/{id}      → SSE: data:{json}\n\n ... data:[DONE]\n\n
     query params: ?compress=true&tz=Asia/Kolkata
GET  /api/status        → {"status":"ok","elk":"up|down"}
```

---

## Web UI

Single HTML file, embedded. No CDN. Inline CSS + JS.

Features:
- Scenario cards: name, description, log count, simulated duration, ES index name
- "Compress Time" toggle per scenario (default: on)
- "Run" button → POST /api/run/{id}?compress=true
- SSE log stream: INFO=green, WARN=yellow, ERROR=red, monospace `<pre>`
- "Open Kibana Dashboard" → links to per-scenario dashboard URL
- "Open Discover" → links to per-scenario Discover URL
- Status dot (polls /api/status, shows ELK health)
- "Clear" button
- Dark theme

---

## Logger (`internal/logger/logger.go`)

```go
package logger
// New(path string, tz *time.Location) *Logger
// - writes JSON to file (path) + stdout
// - all timestamps use tz (default Asia/Kolkata)

// NewWithTimeOverride(path string, tz *time.Location, startTime time.Time, logCount int, compress bool) *Logger
// - when compress=true: each log call advances synthetic time by (timeWindow/logCount)
// - synthetic time is used as the "time" field in JSON
// - real emit is immediate

// Methods: Info/Warn/Error(msg string, args ...any)
```

---

## ELK Changes

### logstash.conf
```ruby
filter {
  if [log_type] =~ /^sim-/ {
    json { source => "message" target => "go_json" }
    mutate {
      rename => { "[go_json][msg]" => "app_message"
                  "[go_json][level]" => "app_level"
                  "[go_json][scenario]" => "scenario" }
      add_field => { "scenario_id" => "%{[go_json][scenario]}" }
    }
    date {
      match => ["[go_json][time]", "ISO8601"]
      target => "@timestamp"
      timezone => "Asia/Kolkata"
    }
    # promote all go_json fields to top level
    ruby { code => 'event.get("[go_json]").to_hash.each { |k,v| event.set(k,v) }' }
    mutate { remove_field => ["go_json", "message"] }
  }
}

output {
  if [log_type] == "sim-auth-brute-force"  { elasticsearch { index => "sim-auth-brute-force" } }
  if [log_type] == "sim-payment-decline"   { elasticsearch { index => "sim-payment-decline" } }
  if [log_type] == "sim-db-slow-query"     { elasticsearch { index => "sim-db-slow-query" } }
  if [log_type] == "sim-cache-stampede"    { elasticsearch { index => "sim-cache-stampede" } }
  if [log_type] == "sim-api-degradation"   { elasticsearch { index => "sim-api-degradation" } }
}
```

### filebeat.yml
```yaml
# 5 inputs, one per scenario
- type: log
  paths: [/var/log/app/sim-auth-brute-force.log]
  fields: { log_type: sim-auth-brute-force }
  fields_under_root: true

- type: log
  paths: [/var/log/app/sim-payment-decline.log]
  fields: { log_type: sim-payment-decline }
  fields_under_root: true
# ... repeat for all 5
```

---

## Phases

```
Phase 1: core-builder          → server (exec model), logger (IST+compress), ELK, UI          ✅ DONE
Phase 2: scenario-implementor  → 5 × main.go, commit+push after each                          ✅ DONE
Phase 3: kibana-expert         → 5 × (setup.sh + reset.sh + dashboard.ndjson + discover_url.md)  🔄 PARTIAL (01 missing discover_url.md; 03-05 not started)
Phase 3: demo-expert           → 5 × (README.md + verbal_script.md + notebooklm_prompt.md)    🔄 PARTIAL (01-02 done; 03-05 not started)
Phase 4: qa-agent              → end-to-end validation                                         ⏳ NOT STARTED
```

## Progress (as of 2026-04-15)

### Phase 1 — core-builder ✅
All files in `cmd/`, `internal/`, `web/`, `elk/`, `scripts/`, `docker-compose.yml`, `Dockerfile`, `Makefile`, `go.mod` complete.

Notable fixes applied post-merge:
- Filebeat switched to `filestream` input type; added `close_inactive` + `scan_frequency` for macOS Docker Desktop
- Logstash strips Filebeat metadata fields from ES docs
- `--compress-time` backdate fix: timestamps backdate from `startTime`, not `now`
- `index.html` Discover URL format fixed: `dataViewId`, 15min window, 2s auto-refresh, no scenario filter query

### Phase 2 — scenario-implementor ✅
All 5 `scenarios/0N-name/main.go` committed. `cmd/server/scenarios_init.go` has 2 uncommitted changes (adding `IndexPatternID` for scenarios 03-05).

> **Pending commit:** `scenarios_init.go` (IndexPatternID for 03/04/05) + `index.html` (Discover URL fix)

### Phase 3 — kibana-expert 🔄

| Scenario | setup.sh | reset.sh | dashboard.ndjson | discover_url.md |
|----------|----------|----------|-----------------|-----------------|
| 01 auth-brute-force | ✅ | ✅ | ✅ | ❌ missing |
| 02 payment-decline | ✅ | ✅ | ✅ | ✅ |
| 03 db-slow-query | ❌ | ❌ | ❌ | ❌ |
| 04 cache-stampede | ❌ | ❌ | ❌ | ❌ |
| 05 api-degradation | ❌ | ❌ | ❌ | ❌ |

**Next:** kibana-expert agent must add `discover_url.md` for 01 and all 4 artifacts for 03/04/05.

### Phase 3 — demo-expert 🔄

| Scenario | README.md | verbal_script.md | notebooklm_prompt.md |
|----------|-----------|-----------------|----------------------|
| 01 auth-brute-force | ✅ | ✅ | ✅ |
| 02 payment-decline | ✅ | ✅ | ✅ |
| 03 db-slow-query | ❌ | ❌ | ❌ |
| 04 cache-stampede | ❌ | ❌ | ❌ |
| 05 api-degradation | ❌ | ❌ | ❌ |

**Next:** demo-expert agent must add all 3 files for scenarios 03/04/05.

### Phase 4 — qa-agent ⏳
Not started. Run after Phase 3 is fully complete.

---

## Agent Ownership

| Agent | Owns | Must not touch |
|-------|------|---------------|
| core-builder | cmd/, internal/, web/, elk/, docker-compose.yml, Dockerfile, Makefile, go.mod, scripts/*.sh | scenarios/ |
| scenario-implementor | scenarios/*/main.go, cmd/server/scenarios_init.go | elk/, web/, agents/ |
| kibana-expert | scenarios/*/setup.sh, scenarios/*/reset.sh, scenarios/*/dashboard.ndjson, scenarios/*/discover_url.md, scenarios/README.md | Go source, demo files |
| demo-expert | scenarios/*/README.md, scenarios/*/verbal_script.md, scenarios/*/notebooklm_prompt.md | Go source, kibana files |
| qa-agent | qa/report.md (write only) | everything else (read-only) |

---

## Autonomy Rules (all agents)

1. Proceed without asking. Make the obvious choice.
2. When blocked: give exactly 2 options with tradeoffs. No open-ended questions.
3. Ambiguous spec → pick simpler. Note choice in comment.
4. Missing dependency file → infer from PLAN.md. Don't halt.

---

## Git Rules (scenario-implementor)

After each scenario binary builds (`go build ./scenarios/0N-name`):
```bash
git add scenarios/<id>/main.go cmd/server/scenarios_init.go
git commit -m "feat(scenario): implement <scenario-id>"
git push origin HEAD
```
Order: 01 → 02 → 03 → 04 → 05. One commit per scenario.

---

## Worktree Protocol

**Every AI agent/tool that touches this repo must work in its own worktree — never directly on `main`.**

### Naming convention

```
.worktrees/<tool>-<role>[-NNN]
```

| Segment | Examples |
|---------|---------|
| `<tool>` | `claude`, `gemini`, `gpt`, `cursor`, `copilot`, `kiro`, `codex` |
| `<role>` | `core-builder`, `scenario-02`, `kibana-expert`, `demo-expert`, `qa` |
| `[-NNN]` | `-002`, `-003` — only when same tool+role runs more than once |

**Examples:**
```
.worktrees/claude-scenario-02
.worktrees/gemini-kibana-expert
.worktrees/gpt-scenario-03-002   ← second attempt by same tool
.worktrees/cursor-demo-expert
```

Branch name mirrors the worktree: `feat/<tool>-<role>[-NNN]`

### Create worktree

```bash
# always branch off main
git fetch origin main
git worktree add .worktrees/<tool>-<role> -b feat/<tool>-<role> origin/main
cd .worktrees/<tool>-<role>
```

### Find the latest code (for any agent picking up mid-project)

```bash
# list all active worktrees
git worktree list

# list all feature branches sorted by commit date (latest first)
git branch -a --sort=-committerdate | grep feat/

# see what each branch added
git log --oneline main..feat/<tool>-<role>
```

### Finish & merge

```bash
# build must pass before merge
go build ./cmd/server
go build ./scenarios/<N>-<id>   # if applicable

# commit inside worktree, push feature branch
git add <files>
git commit -m "feat(<role>): <description>"
git push origin feat/<tool>-<role>

# merge to main (from repo root, not worktree)
cd /path/to/repo-root
git checkout main
git pull origin main
git merge feat/<tool>-<role> --no-ff -m "feat(<role>): merge <description>"
git push origin main

# cleanup
git worktree remove .worktrees/<tool>-<role>
git branch -d feat/<tool>-<role>
git push origin --delete feat/<tool>-<role>
```

Merge to `main` only after the phase's acceptance criteria pass.

### .worktrees is gitignored

`.worktrees/` is in `.gitignore` — worktree directories are never committed.

---

## Acceptance Criteria

- [x] `docker-compose up` starts full stack
- [x] `http://localhost:8080` shows UI
- [x] Each scenario runs, streams logs, writes to `logs/sim-<id>.log`
- [x] Each scenario's logs appear in its own Kibana index within 30s
- [ ] `make setup-all` creates 5 dashboards + 10 alerts (only 01+02 fully set up)
- [ ] Each dashboard shows 6 panels with meaningful data (only 01+02)
- [ ] `make reset-all` wipes all 5 scenario indexes + Kibana objects (only 01+02)
- [x] Time compression: `--compress-time` shows 30min spread in Kibana timeline
- [x] All timestamps in IST (UTC+5:30)
- [ ] QA agent reports PASS for all 5 scenarios

---

## Constraints

1. No external Go dependencies. Stdlib only.
2. No JS framework. Vanilla HTML/CSS/JS.
3. Scenarios = logs only. No real network/DB calls.
4. Max 8 fields per log line.
5. ELK stays at 8.12.0.
6. Single server binary + 5 scenario binaries. Embed web/ in server.
