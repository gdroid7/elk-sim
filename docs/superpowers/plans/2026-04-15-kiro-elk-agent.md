# Kiro ELK Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create three standalone Kiro agents + one hook in `.kiro/` that give any repo a full ELK stack for log observability in under 60s.

**Architecture:** Agent files in `.kiro/agents/`, hook in `.kiro/hooks/`, ELK config templates in `.kiro/templates/`. The `elk-setup` agent reads templates, substitutes `.env` values, writes to repo root. `kibana-agent` and `elk-debugger` are fully standalone — they read `.env` for context and use `curl` for all ELK API calls. No shared state beyond `.env`.

**Tech Stack:** Kiro agent markdown format · ELK 8.12.0 · Docker Compose v3.8 · curl · bash

---

## File Map

| File | Action | Task |
|------|--------|------|
| `.kiro/templates/docker-compose.yml` | Create | 1 |
| `.kiro/templates/filebeat.yml` | Create | 1 |
| `.kiro/templates/logstash.conf` | Create | 1 |
| `.kiro/templates/kibana.yml` | Create | 1 |
| `.kiro/templates/Makefile` | Create | 1 |
| `.kiro/templates/.env.example` | Create | 1 |
| `.kiro/agents/elk-setup.md` | Create | 2 |
| `.kiro/agents/kibana-agent.md` | Create | 3 |
| `.kiro/agents/elk-debugger.md` | Create | 4 |
| `.kiro/hooks/elk-commit.md` | Create | 5 |
| `.kiro/README.md` | Create | 6 |

---

### Task 1: ELK Config Templates

Templates with `{{PLACEHOLDER}}` substitution. `elk-setup` reads these, substitutes collected values, writes to repo root.

**Files:**
- Create: `.kiro/templates/docker-compose.yml`
- Create: `.kiro/templates/filebeat.yml`
- Create: `.kiro/templates/logstash.conf`
- Create: `.kiro/templates/kibana.yml`
- Create: `.kiro/templates/Makefile`
- Create: `.kiro/templates/.env.example`

- [ ] **Step 1: Create `.kiro/templates/docker-compose.yml`**

```yaml
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms{{ES_HEAP_SIZE}}m -Xmx{{ES_HEAP_SIZE}}m
    ports:
      - "9200:9200"
    volumes:
      - es-data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9200"]
      interval: 10s
      timeout: 5s
      retries: 6

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    ports:
      - "{{KIBANA_PORT}}:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      elasticsearch:
        condition: service_healthy

  logstash:
    image: docker.elastic.co/logstash/logstash:8.12.0
    volumes:
      - ./logstash/logstash.conf:/usr/share/logstash/pipeline/logstash.conf:ro
    ports:
      - "5044:5044"
    depends_on:
      elasticsearch:
        condition: service_healthy

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.12.0
    user: root
    volumes:
      - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - {{LOG_DIR}}:{{LOG_DIR}}:ro
    command: filebeat -e -strict.perms=false
    depends_on:
      - logstash

volumes:
  es-data:
```

- [ ] **Step 2: Create `.kiro/templates/filebeat.yml`**

```yaml
filebeat.inputs:
  - type: filestream
    id: app-logs
    paths:
      - {{LOG_PATH}}
    fields:
      app_name: {{APP_NAME}}
      log_format: {{LOG_FORMAT}}
    fields_under_root: true
    close_inactive: 2m
    scan_frequency: 5s

output.logstash:
  hosts: ["logstash:5044"]

logging.level: info
```

- [ ] **Step 3: Create `.kiro/templates/logstash.conf`**

```ruby
input {
  beats {
    port => 5044
  }
}

filter {
  if [log_format] == "json" {
    json {
      source => "message"
      target => "parsed"
    }
    if "_jsonparsefailure" not in [tags] {
      ruby {
        code => 'event.get("parsed").each { |k,v| event.set(k,v) } rescue nil'
      }
      mutate { remove_field => ["parsed"] }
    }
    date {
      match => ["time", "ISO8601", "yyyy-MM-dd HH:mm:ss", "UNIX_MS"]
      target => "@timestamp"
    }
  }
  mutate {
    remove_field => ["agent", "ecs", "input", "log", "host"]
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "logs-%{[app_name]}-%{+YYYY.MM.dd}"
  }
}
```

- [ ] **Step 4: Create `.kiro/templates/kibana.yml`**

```yaml
server.name: kibana
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://elasticsearch:9200"]
monitoring.ui.container.elasticsearch.enabled: true
```

- [ ] **Step 5: Create `.kiro/templates/Makefile`**

Note: indentation must use tabs, not spaces.

```makefile
.PHONY: up down logs status clean

up:
	docker compose -f elk/docker-compose.yml up -d

down:
	docker compose -f elk/docker-compose.yml down

logs:
	docker compose -f elk/docker-compose.yml logs -f

status:
	@docker compose -f elk/docker-compose.yml ps
	@echo ""
	@echo "=== Elasticsearch health ==="
	@curl -s localhost:9200/_cluster/health | python3 -m json.tool 2>/dev/null || echo "ES not ready yet"
	@echo ""
	@echo "=== Log index doc count ==="
	@curl -s "localhost:9200/logs-{{APP_NAME}}-*/_count" | python3 -m json.tool 2>/dev/null || echo "No index yet"

clean:
	docker compose -f elk/docker-compose.yml down -v
	@echo "Data volumes deleted."
```

- [ ] **Step 6: Create `.kiro/templates/.env.example`**

```
APP_NAME=myapp
LOG_PATH=/absolute/path/to/app.log
LOG_FORMAT=json
RETENTION_DAYS=7
ES_HEAP_SIZE=512
KIBANA_PORT=5601
```

- [ ] **Step 7: Verify all 6 template files exist**

```bash
ls .kiro/templates/
```

Expected output:
```
Makefile  docker-compose.yml  filebeat.yml  kibana.yml  logstash.conf  .env.example
```

- [ ] **Step 8: Commit**

```bash
git add .kiro/templates/
git commit -m "feat(kiro): add ELK config templates"
```

---

### Task 2: `elk-setup` Agent

**Files:**
- Create: `.kiro/agents/elk-setup.md`

- [ ] **Step 1: Create `.kiro/agents/elk-setup.md`**

```markdown
---
name: elk-setup
description: >
  Interactive ELK stack setup for any repo with a log file.
  Installs Docker if needed, discovers log files, writes ELK config,
  starts stack, generates README. Terse caveman style throughout.
---

# elk-setup — ELK Stack Onboarding

Terse. One Q per message. Caveman style — short answers expected.

## Rules
- One question per message. Wait for answer before next.
- Never write files until all Q&A complete.
- All output files go to repo root: `elk/`, `.env`, `Makefile`, `ELK_README.md`.
- Never touch files outside repo root.
- Substitute `{{VAR}}` placeholders in templates with collected values before writing.

---

## Step 1: Check existing config

Read `.env` in current directory.

If exists and `APP_NAME` is set:
> "Stack configured for **{APP_NAME}**.
>
> 1. Reconfigure
> 2. Start stack: `make up`
> 3. Exit"

Wait for choice. If 1 → go to Step 2. If 2 → show `make up` command, stop. If 3 → stop.

If `.env` missing or `APP_NAME` not set → go to Step 2.

---

## Step 2: Check Docker

Run: `docker --version`

If command succeeds → go to Step 3.

If fails:
> "Docker not found. Install?
> 1. Yes (brew install --cask docker)
> 2. Manual install"

If 1 → run `brew install --cask docker` → run `docker --version` again.
  If still fails: "Install failed. Install Docker manually then re-run elk-setup." Stop.
If 2 → show https://docs.docker.com/get-docker/ → stop.

---

## Step 3: Discover log file

Scan these paths for `.log` files:
- `logs/*.log`
- `*.log`
- `log/*.log`
- `/var/log/<name-of-current-folder>/*.log`

Build numbered list of found files. If none found, show empty list.

Ask:
> "Log file?
> [1] /path/to/found/file.log
> [2] /another/found/file.log
> Enter number or full path:"

Validate: path must start with `/`. If relative path given, prepend current working directory.
Check file exists — if not, warn but continue.
Store as `LOG_PATH`.
Derive `LOG_DIR` = parent directory of `LOG_PATH` (e.g. `/var/log/myapp` from `/var/log/myapp/app.log`).

---

## Step 4: App name

Ask:
> "App name? (default: <current-folder-name>)"

Rules: lowercase letters, numbers, hyphens only. No spaces.
If user presses enter with no input → use current folder name as default.
Validate against `^[a-z0-9][a-z0-9-]*$`. If invalid, explain and re-ask.
Store as `APP_NAME`.

---

## Step 5: Log format

Ask:
> "Log format?
> 1. json  →  {\"time\":\"2026-01-01T10:00:00Z\",\"level\":\"ERROR\",\"msg\":\"...\"} 
> 2. text  →  2026-01-01 10:00:00 ERROR something happened"

Store: `1` → `LOG_FORMAT=json`, `2` → `LOG_FORMAT=text`.

---

## Step 6: Customize?

Ask:
> "Customize? (defaults: 7d retention, 512MB heap, port 5601)
> 1. Yes
> 2. No"

If **No**: set `RETENTION_DAYS=7`, `ES_HEAP_SIZE=512`, `KIBANA_PORT=5601`. Go to Step 7.

If **Yes**, ask these three questions one at a time:

**6a:** "Retention days? (default: 7)"
Store as `RETENTION_DAYS`. If blank → 7.

**6b:** "ES heap MB? (default: 512)"
Store as `ES_HEAP_SIZE`. If blank → 512.

**6c:** "Kibana port? (default: 5601)"
Store as `KIBANA_PORT`. If blank → 5601.

---

## Step 7: Write files

Read each template from `.kiro/templates/`. Replace ALL `{{PLACEHOLDER}}` tokens. Write to repo root.

**Write `.env`:**
```
APP_NAME={{APP_NAME}}
LOG_PATH={{LOG_PATH}}
LOG_FORMAT={{LOG_FORMAT}}
RETENTION_DAYS={{RETENTION_DAYS}}
ES_HEAP_SIZE={{ES_HEAP_SIZE}}
KIBANA_PORT={{KIBANA_PORT}}
```

**Write `elk/docker-compose.yml`:**
Read `.kiro/templates/docker-compose.yml`.
Replace: `{{ES_HEAP_SIZE}}` → collected value, `{{KIBANA_PORT}}` → collected value, `{{LOG_DIR}}` → derived value.
Write to `elk/docker-compose.yml`.

**Write `elk/filebeat/filebeat.yml`:**
Read `.kiro/templates/filebeat.yml`.
Replace: `{{LOG_PATH}}`, `{{APP_NAME}}`, `{{LOG_FORMAT}}`.
Write to `elk/filebeat/filebeat.yml`.

**Write `elk/logstash/logstash.conf`:**
Read `.kiro/templates/logstash.conf`. No substitution needed.
Write to `elk/logstash/logstash.conf`.

**Write `elk/kibana/kibana.yml`:**
Read `.kiro/templates/kibana.yml`. No substitution needed.
Write to `elk/kibana/kibana.yml`.

**Write `Makefile`:**
Read `.kiro/templates/Makefile`.
Replace: `{{APP_NAME}}` → collected value.
Write to `Makefile`.

**macOS note:** If `LOG_PATH` does not start with `/Users/` or `/home/`:
> "macOS Docker Desktop: ensure {{LOG_DIR}} is in Docker → Preferences → Resources → File Sharing"

---

## Step 8: Start stack

> "Starting ELK stack..."

Run: `make up`

Poll ES health every 5s, max 12 attempts (60s total):
`curl -s localhost:9200/_cluster/health`

Parse `status` field from JSON response.
When status is `green` or `yellow`:
> "Kibana ready → http://localhost:{{KIBANA_PORT}}"

If 60s elapsed with no healthy response:
> "Stack slow to start. Check with: `make logs`"

---

## Step 9: Generate ELK_README.md

Write `ELK_README.md` to repo root with this content (substitute values):

```markdown
# ELK Stack — {{APP_NAME}}

## Config
- App: {{APP_NAME}}
- Log file: {{LOG_PATH}} ({{LOG_FORMAT}} format)
- Kibana: http://localhost:{{KIBANA_PORT}}
- ES index: logs-{{APP_NAME}}-YYYY.MM.dd

## Commands

| Command | Action |
|---------|--------|
| `make up` | Start stack |
| `make down` | Stop stack |
| `make logs` | Tail container logs |
| `make status` | Container status + ES health |
| `make clean` | Stop + delete all data volumes |

## Agents

| Agent | Purpose |
|-------|---------|
| `kibana-agent` | Create dashboards from plain English |
| `elk-debugger` | Debug pipeline when logs aren't in Kibana |

## Troubleshooting
- Logs not in Kibana? Run the `elk-debugger` agent.
- Stack not starting? Run `make logs` to see errors.
- macOS: log file must be in a Docker-shared directory (Docker → Preferences → Resources → File Sharing).
- ES out of memory? Increase `ES_HEAP_SIZE` in `.env` then run `make clean && make up`.
```

---

## Step 10: Offer Kibana setup

> "Done. Want dashboards?
> Run `kibana-agent` or describe what you want to see."

If user describes inline → tell them:
> "Got it. Run `kibana-agent` and start with: '{{their description}}'"
```

- [ ] **Step 2: Verify file created**

```bash
head -5 .kiro/agents/elk-setup.md
```

Expected:
```
---
name: elk-setup
description: >
  Interactive ELK stack setup for any repo with a log file.
```

- [ ] **Step 3: Commit**

```bash
git add .kiro/agents/elk-setup.md
git commit -m "feat(kiro): add elk-setup agent"
```

---

### Task 3: `kibana-agent` Agent

**Files:**
- Create: `.kiro/agents/kibana-agent.md`

- [ ] **Step 1: Create `.kiro/agents/kibana-agent.md`**

```markdown
---
name: kibana-agent
description: >
  Standalone Kibana dashboard agent. Plain English description → Kibana
  dashboard ndjson + demo log script. Reads .env for context.
  Works any time the stack is running.
---

# kibana-agent — Kibana Dashboard Builder

Terse. One Q per message. Caveman style.

## Rules
- Read `.env` before anything else.
- One question per message. Wait for answer.
- All output files go to `kibana/` and `elk/`.
- Never modify files in `elk/` (config), only add to `kibana/` and `elk/demo-logs.sh`.

---

## Step 1: Check prereqs

Read `.env`. If missing or `APP_NAME` not set:
> "Run elk-setup first."
Stop.

Check ES reachable: `curl -s --max-time 3 localhost:9200/_cluster/health`
If request fails or times out:
> "Stack not running. Run: `make up`"
Stop.

Read from `.env`: `APP_NAME`, `LOG_PATH`, `LOG_FORMAT`, `KIBANA_PORT`.
ES index pattern = `logs-{{APP_NAME}}-*`

---

## Step 2: Ask what to visualize

> "What to show? (plain English)
> e.g. 'error rate over time as line chart'
>      'top 10 endpoints by request count as bar'"

Store as `DESCRIPTION`.

---

## Step 3: Q&A (one at a time)

**3a — Time range:**
> "Time range?
> 1. 15 minutes
> 2. 1 hour
> 3. 24 hours
> 4. 7 days
> 5. Custom"

Map: 1→`now-15m`, 2→`now-1h`, 3→`now-24h`, 4→`now-7d`. For 5, ask: "Enter range (e.g. now-3h):"
Store as `TIME_FROM`.

**3b — Key field:**
> "Key field to plot? (blank = auto from description)"

If blank: infer from `DESCRIPTION` keywords (e.g. "error" → `level`, "latency" → `duration_ms`, "endpoint" → `endpoint`).
Store as `KEY_FIELD`.

**3c — Chart type:**
> "Chart type?
> 1. line
> 2. bar
> 3. pie
> 4. table
> 5. metric (big number)"

Store as `CHART_TYPE` (line/bar/pie/table/metric).

**3d — Title:**
> "Dashboard title?"

Store as `TITLE`.
Derive `SLUG` = `TITLE` lowercased, spaces and special chars replaced with hyphens.

---

## Step 4: Generate `kibana/{{SLUG}}.ndjson`

Generate Kibana 8.12 saved objects ndjson with three objects in this exact order:

**Object 1 — Data view (index pattern):**
```json
{"type":"index-pattern","id":"{{SLUG}}-dataview","attributes":{"title":"logs-{{APP_NAME}}-*","timeFieldName":"@timestamp"},"references":[],"version":"1"}
```

**Object 2 — Visualization:**
```json
{"type":"visualization","id":"{{SLUG}}-viz","attributes":{"title":"{{TITLE}}","visType":"{{CHART_TYPE}}","params":{"type":"{{CHART_TYPE}}","addLegend":true,"addTimeMarker":false},"aggs":[{"id":"1","type":"count","schema":"metric"},{"id":"2","type":"terms","schema":"segment","params":{"field":"{{KEY_FIELD}}.keyword","size":10,"order":"desc","orderBy":"1"}}]},"references":[{"id":"{{SLUG}}-dataview","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}],"version":"1"}
```

**Object 3 — Dashboard:**
```json
{"type":"dashboard","id":"{{SLUG}}-dash","attributes":{"title":"{{TITLE}}","hits":0,"description":"","panelsJSON":"[{\"embeddableConfig\":{},\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15,\"i\":\"1\"},\"id\":\"{{SLUG}}-viz\",\"panelIndex\":\"1\",\"type\":\"visualization\",\"version\":\"8.12.0\"}]","timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"}},"references":[{"id":"{{SLUG}}-viz","name":"1:panel_1","type":"visualization"}],"version":"1"}
```

Write all three objects to `kibana/{{SLUG}}.ndjson`, one JSON object per line (ndjson format).

---

## Step 5: Import to Kibana

Run:
```bash
curl -s -X POST "http://localhost:{{KIBANA_PORT}}/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" \
  -F "file=@kibana/{{SLUG}}.ndjson"
```

Parse HTTP response:
- `"success":true` → "Dashboard '{{TITLE}}' imported ✓"
- Any error → show full response body, suggest: "Check `make logs` for Kibana errors."

---

## Step 6: Generate `elk/demo-logs.sh`

If `LOG_FORMAT=json`, write this script to `elk/demo-logs.sh`:
```bash
#!/bin/bash
# Demo log injector — appends 20 sample JSON logs to {{LOG_PATH}}
LOG_PATH="{{LOG_PATH}}"
echo "Appending 20 logs to $LOG_PATH..."
for i in $(seq 1 20); do
  if   [ $((i % 5)) -eq 0 ]; then LEVEL="ERROR"
  elif [ $((i % 3)) -eq 0 ]; then LEVEL="WARN"
  else LEVEL="INFO"; fi
  echo "{\"time\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"level\":\"$LEVEL\",\"msg\":\"demo event $i\",\"app_name\":\"{{APP_NAME}}\"}" >> "$LOG_PATH"
  sleep 0.3
done
echo "Done. Logs appear in Kibana within ~10s."
```

If `LOG_FORMAT=text`, write:
```bash
#!/bin/bash
# Demo log injector — appends 20 sample text logs to {{LOG_PATH}}
LOG_PATH="{{LOG_PATH}}"
echo "Appending 20 logs to $LOG_PATH..."
for i in $(seq 1 20); do
  if   [ $((i % 5)) -eq 0 ]; then LEVEL="ERROR"
  elif [ $((i % 3)) -eq 0 ]; then LEVEL="WARN"
  else LEVEL="INFO"; fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') $LEVEL demo event $i app={{APP_NAME}}" >> "$LOG_PATH"
  sleep 0.3
done
echo "Done. Logs appear in Kibana within ~10s."
```

Make executable: `chmod +x elk/demo-logs.sh`

---

## Step 7: Show demo prompt

> "Demo ready.
>
> ```bash
> bash elk/demo-logs.sh
> ```
> Then open http://localhost:{{KIBANA_PORT}} → Dashboards → {{TITLE}}
> Logs appear within ~10s."

---

## Step 8: Offer more

> "Another panel?"

If yes → go to Step 2.
```

- [ ] **Step 2: Verify file created**

```bash
head -5 .kiro/agents/kibana-agent.md
```

Expected:
```
---
name: kibana-agent
description: >
  Standalone Kibana dashboard agent. Plain English description → Kibana
```

- [ ] **Step 3: Commit**

```bash
git add .kiro/agents/kibana-agent.md
git commit -m "feat(kiro): add kibana-agent"
```

---

### Task 4: `elk-debugger` Agent

**Files:**
- Create: `.kiro/agents/elk-debugger.md`

- [ ] **Step 1: Create `.kiro/agents/elk-debugger.md`**

```markdown
---
name: elk-debugger
description: >
  Standalone ELK pipeline debugger. Checks each hop: log file → filebeat →
  logstash → elasticsearch. Read-only. Pinpoints where logs drop and gives
  one fix command per failing hop.
---

# elk-debugger — Pipeline Debugger

Read-only. No config changes. Never modifies files. Caveman output.

---

## Step 1: Check .env

Read `.env`. If missing or `APP_NAME` not set:
> "No .env found. Run elk-setup first."
Stop.

Read: `APP_NAME`, `LOG_PATH`, `KIBANA_PORT`.

---

## Step 2: Check containers

Run: `docker compose -f elk/docker-compose.yml ps`

Check that all four services are listed as `running` or `Up`: elasticsearch, kibana, logstash, filebeat.

For each service not running:
> "<service> is not running."

If any service is down:
> "Fix: `make up`"
Stop.

---

## Step 3: Check log file

Check if `LOG_PATH` file exists and is readable.

Run: `wc -c "{{LOG_PATH}}"`

If file missing:
> "Log file NOT FOUND: {{LOG_PATH}}"
> "Fix: ensure your app is writing to this path."
Flag as: `LOG_FILE=FAIL`

If file empty (0 bytes):
> "Log file EMPTY: {{LOG_PATH}}"
> "Fix: run `bash elk/demo-logs.sh` to inject sample logs."
Flag as: `LOG_FILE=EMPTY`

If file has content:
Run: `tail -3 "{{LOG_PATH}}"`
> "Log file OK — last 3 lines:"
> (show output)
Flag as: `LOG_FILE=OK`

---

## Step 4: Check Filebeat → Logstash

Run: `docker compose -f elk/docker-compose.yml logs filebeat --tail=50`

Scan output for these patterns:

| Pattern | Meaning |
|---------|---------|
| `Connecting to Logstash` | Attempting connection |
| `Events sent` or `Published` | Data flowing ✓ |
| `harvester` + `error` | File permission or path issue |
| `connection refused` | Logstash not ready yet |
| `strict.perms` | Filebeat config permission error |

Report:
- If "Published" found: "Filebeat OK — events flowing to Logstash ✓"
- If "connection refused": "Filebeat WARN — Logstash not ready. Wait 10s and re-run."
- If harvester error: "Filebeat ERROR — cannot read log file. Check file permissions on {{LOG_PATH}}."
- If none of above: "Filebeat status unclear — no events seen yet. File may not have new lines."

---

## Step 5: Check Logstash → Elasticsearch

Run: `docker compose -f elk/docker-compose.yml logs logstash --tail=50`

Scan for:
- "Pipeline started" → Logstash pipeline running
- "connection refused" or "Could not index" → ES not reachable from Logstash
- "JSON parsing" or "codec" error → log format mismatch

Run: `curl -s localhost:9600/_node/stats/events`

Parse `pipeline.events.in` and `pipeline.events.out` from JSON.
> "Logstash: received {{in}}, sent {{out}}"

If `out` < `in`:
> "Logstash WARN — {{in - out}} events dropped. Check logstash logs above for errors."

If curl fails (9600 not available):
> "Logstash stats API not reachable. Check: `docker compose -f elk/docker-compose.yml logs logstash`"

---

## Step 6: Check Elasticsearch index

Run: `curl -s "localhost:9200/logs-{{APP_NAME}}-*/_count"`

Parse `count` from JSON response.

If `count` > 0:
> "ES OK — {{count}} docs in index ✓"

If `count` = 0 but index exists:
> "ES index exists but EMPTY — logs not ingested yet."
> "Fix: check Steps 4-5 above."

If 404 (index not found):
> "ES index NOT FOUND — no logs have been ingested."
> "Fix: verify filebeat is connecting and logstash pipeline is running."

---

## Step 7: Summary report

Print:

```
=== Pipeline check ===
  Log file    [{{LOG_FILE status}}]
  Filebeat    [{{FILEBEAT status}}]
  Logstash    [{{LOGSTASH status}}]
  ES index    [{{ES status}}]

First failing hop: {{hop name or "none — all OK"}}
Fix: {{one specific command}}
```

If all OK:
> "Pipeline healthy. All logs flowing to ES ✓"
> "Open Kibana: http://localhost:{{KIBANA_PORT}}"

---

## Step 8: Live tail (optional)

Ask:
> "Tail live pipeline for 10s?
> 1. Yes
> 2. No"

If Yes: run with 10-second timeout:
```bash
timeout 10 docker compose -f elk/docker-compose.yml logs -f filebeat logstash --tail=5
```
Show output. After timeout: "Done."
```

- [ ] **Step 2: Verify file created**

```bash
head -5 .kiro/agents/elk-debugger.md
```

Expected:
```
---
name: elk-debugger
description: >
  Standalone ELK pipeline debugger. Checks each hop: log file → filebeat →
```

- [ ] **Step 3: Commit**

```bash
git add .kiro/agents/elk-debugger.md
git commit -m "feat(kiro): add elk-debugger agent"
```

---

### Task 5: `elk-commit` Hook

**Files:**
- Create: `.kiro/hooks/elk-commit.md`

- [ ] **Step 1: Create `.kiro/hooks/elk-commit.md`**

```markdown
---
name: elk-commit
description: >
  After elk-setup or kibana-agent writes files, prompt user to commit and
  push. Checks git status for ELK-related files only. Never auto-commits.
trigger: userMessage
condition: >
  Only activate if git status shows uncommitted changes in:
  elk/, .env, Makefile, ELK_README.md, kibana/, elk/demo-logs.sh
---

# elk-commit — Commit & Push Prompt

Runs silently unless ELK files have uncommitted changes. Never auto-commits.

## Rules
- Never commit without explicit user confirmation.
- Never use `git push --force`.
- If no ELK changes detected → do nothing, no output.

---

## Step 1: Check for ELK changes

Run: `git status --short`

Filter output for lines containing: `elk/`, `.env`, `Makefile`, `ELK_README.md`, `kibana/`, `demo-logs.sh`

If no matching lines → stop silently.

---

## Step 2: Show changed files and ask

List only the ELK-related changed files.

Ask:
> "Commit ELK config?
> {{list of changed files}}
> 1. Yes
> 2. No"

If No → stop.

---

## Step 3: Determine commit message

If changed files include `elk/`, `.env`, `Makefile`, or `ELK_README.md`:
  → `"chore(elk): add ELK stack config"`

If changed files include `kibana/*.ndjson` or `elk/demo-logs.sh`:
  → extract slug from ndjson filename
  → `"chore(elk): add kibana dashboard {{slug}}"`

If both sets changed:
  → `"chore(elk): add ELK stack config and dashboards"`

---

## Step 4: Commit

Run:
```bash
git add elk/ .env Makefile ELK_README.md kibana/ elk/demo-logs.sh 2>/dev/null; true
git commit -m "{{commit message}}"
```

Show the commit hash on success.

---

## Step 5: Ask about push

> "Push to remote?
> 1. Yes
> 2. No"

If No → stop.

If Yes:
Run: `git remote -v`
If no remote configured:
> "No remote configured. Skipping push."
Stop.

Run: `git push origin HEAD`
On success: show the remote URL.
On failure: show the error output from git.
```

- [ ] **Step 2: Verify file created**

```bash
head -5 .kiro/hooks/elk-commit.md
```

Expected:
```
---
name: elk-commit
description: >
  After elk-setup or kibana-agent writes files, prompt user to commit and
```

- [ ] **Step 3: Commit**

```bash
git add .kiro/hooks/elk-commit.md
git commit -m "feat(kiro): add elk-commit hook"
```

---

### Task 6: `.kiro/README.md`

**Files:**
- Create: `.kiro/README.md`

- [ ] **Step 1: Create `.kiro/README.md`**

```markdown
# Kiro ELK Agents

Three agents + one hook. Drop `.kiro/` into any repo with a log file.

## Agents

| Agent | Purpose | When to run |
|-------|---------|-------------|
| `elk-setup` | Install tools, configure + start ELK stack | First time |
| `kibana-agent` | Create dashboards from plain English | After stack is running |
| `elk-debugger` | Debug filebeat → logstash → ES pipeline | When logs aren't in Kibana |

## Hook

`elk-commit` — prompts commit + push after any ELK config files are written.

## Quick Start

1. Copy `.kiro/` folder into your project root
2. In Kiro, run agent: **elk-setup**
3. Answer ~4 questions → stack running in ~60s
4. Run agent: **kibana-agent** → describe your dashboard in plain English
5. `bash elk/demo-logs.sh` → see data in Kibana within 10s

## Requirements

- Docker Desktop
- Git repo
- A log file (JSON or plain text)

## Files Created

After elk-setup, your repo gets:
```
elk/
├── docker-compose.yml
├── filebeat/filebeat.yml
├── logstash/logstash.conf
└── kibana/kibana.yml
.env
Makefile
ELK_README.md
```

After kibana-agent:
```
kibana/<dashboard-slug>.ndjson
elk/demo-logs.sh
```
```

- [ ] **Step 2: Commit**

```bash
git add .kiro/README.md
git commit -m "docs(kiro): add README for kiro ELK agents"
```

---

## Self-Review

**Spec coverage:**
- [x] elk-setup: tool install, log discovery, config, stack start, README → Task 2
- [x] kibana-agent: plain English → dashboard, demo-logs.sh, user-invokable demo → Task 3
- [x] elk-debugger: filebeat → logstash → ES pipeline, read-only → Task 4
- [x] elk-commit hook: commit + push with confirmation, both inline + hook → Task 5
- [x] ELK config templates with `{{PLACEHOLDER}}` substitution → Task 1
- [x] Caveman style + one Q per message in all agents → every agent's Rules section
- [x] No customization at start (Step 6 opt-in) → Task 2 Step 6
- [x] macOS Docker Desktop file sharing note → Task 2 Step 7
- [x] elk-debugger is read-only → Task 4 rules
- [x] Demo script user-invokable, not auto-run → Task 3 Step 7
- [x] `.kiro/README.md` for drop-in copy instructions → Task 6

**Placeholder scan:** None found. All steps contain exact file content, exact commands, exact expected output.

**Type consistency:** `LOG_PATH`, `APP_NAME`, `LOG_FORMAT`, `KIBANA_PORT`, `ES_HEAP_SIZE`, `SLUG` used consistently across all tasks.
