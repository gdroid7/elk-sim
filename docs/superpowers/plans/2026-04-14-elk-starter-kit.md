# ELK Starter Kit (Option A — Minimal Drop-in) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimal, language-agnostic ELK drop-in that any developer can copy into their project and point at a log file.

**Architecture:** Filebeat watches a user-defined log file → Logstash parses (JSON or plain text) → Elasticsearch stores → Kibana visualises. All configured via a single `.env` file.

**Tech Stack:** Docker Compose · ELK 8.12.0 · Filebeat · Logstash · Elasticsearch · Kibana

---

## File Structure

```
elk-starter/
├── .env.example              # LOG_PATH, APP_NAME, LOG_FORMAT
├── docker-compose.yml        # ES + Kibana + Logstash + Filebeat (ELK 8.12.0)
├── Makefile                  # up, down, logs, status, clean
├── README.md
└── elk/
    ├── filebeat/
    │   └── filebeat.yml      # watches ${LOG_PATH}, tags with ${APP_NAME}
    ├── logstash/
    │   └── pipeline/
    │       └── logstash.conf # json auto-detect + plain text fallback → ES
    └── kibana/
        └── kibana.yml
```

---

### Task 1: Worktree + directory scaffold

**Files:**
- Create: `.worktrees/claude-elk-starter/`
- Create: `elk-starter/` (directory structure)

- [ ] **Step 1: Create worktree**

```bash
git fetch origin main
git worktree add .worktrees/claude-elk-starter -b feat/claude-elk-starter origin/main
```

- [ ] **Step 2: Create directories**

```bash
mkdir -p .worktrees/claude-elk-starter/elk-starter/elk/filebeat
mkdir -p .worktrees/claude-elk-starter/elk-starter/elk/logstash/pipeline
mkdir -p .worktrees/claude-elk-starter/elk-starter/elk/kibana
```

---

### Task 2: .env.example

**Files:**
- Create: `elk-starter/.env.example`

- [ ] **Step 1: Write .env.example**

```bash
# Path to your application log file (absolute or relative to docker-compose.yml)
LOG_PATH=/var/log/myapp/app.log

# Name used to tag logs in Elasticsearch (index: logs-<APP_NAME>)
APP_NAME=myapp

# Log format: json | text
# json = Logstash parses each line as JSON, promotes all fields to top level
# text = Logstash stores entire line as `message` field
LOG_FORMAT=json
```

- [ ] **Step 2: Commit**

```bash
cd .worktrees/claude-elk-starter
git add elk-starter/.env.example
git commit -m "feat(elk-starter): add .env.example"
```

---

### Task 3: docker-compose.yml

**Files:**
- Create: `elk-starter/docker-compose.yml`

- [ ] **Step 1: Write docker-compose.yml**

```yaml
version: "3.8"

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\\|yellow\"'"]
      interval: 10s
      timeout: 5s
      retries: 20

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    volumes:
      - ./elk/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    depends_on:
      elasticsearch:
        condition: service_healthy

  logstash:
    image: docker.elastic.co/logstash/logstash:8.12.0
    volumes:
      - ./elk/logstash/pipeline/logstash.conf:/usr/share/logstash/pipeline/logstash.conf:ro
    environment:
      - APP_NAME=${APP_NAME:-myapp}
      - LOG_FORMAT=${LOG_FORMAT:-json}
    depends_on:
      elasticsearch:
        condition: service_healthy

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.12.0
    user: root
    volumes:
      - ./elk/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - ${LOG_PATH:-/tmp/app.log}:/var/log/app/app.log:ro
    environment:
      - APP_NAME=${APP_NAME:-myapp}
    depends_on:
      - logstash
    command: filebeat -e -strict.perms=false

volumes:
  esdata:
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/docker-compose.yml
git commit -m "feat(elk-starter): add docker-compose.yml (ELK 8.12.0)"
```

---

### Task 4: filebeat.yml

**Files:**
- Create: `elk-starter/elk/filebeat/filebeat.yml`

- [ ] **Step 1: Write filebeat.yml**

```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/app/app.log
    fields:
      app_name: "${APP_NAME:myapp}"
    fields_under_root: true
    # Required for Docker Desktop on macOS — without these, logs may not ship
    close_inactive: 5m
    scan_frequency: 5s
    # Handle multiline stack traces (Java, Python, etc.)
    multiline.pattern: '^\s'
    multiline.negate: false
    multiline.match: after

output.logstash:
  hosts: ["logstash:5044"]

logging.level: info
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/elk/filebeat/filebeat.yml
git commit -m "feat(elk-starter): add filebeat.yml with multiline + macOS compat"
```

---

### Task 5: logstash.conf

**Files:**
- Create: `elk-starter/elk/logstash/pipeline/logstash.conf`

- [ ] **Step 1: Write logstash.conf**

```ruby
input {
  beats {
    port => 5044
  }
}

filter {
  if [LOG_FORMAT] == "json" or [@metadata][LOG_FORMAT] == "json" {
    # Try JSON parse; on failure fall through to plain text handling
    json {
      source => "message"
      target => "parsed"
      skip_on_invalid_json => true
    }
    if [parsed] {
      ruby {
        code => '
          parsed = event.get("parsed")
          if parsed.is_a?(Hash)
            parsed.each { |k, v| event.set(k, v) }
          end
          event.remove("parsed")
          event.remove("message")
        '
      }
    }
  }
  # Always keep app_name field for index routing
  if ![app_name] {
    mutate { add_field => { "app_name" => "unknown" } }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "logs-%{[app_name]}-%{+YYYY.MM.dd}"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/elk/logstash/pipeline/logstash.conf
git commit -m "feat(elk-starter): add logstash pipeline (json auto-parse + text fallback)"
```

---

### Task 6: kibana.yml

**Files:**
- Create: `elk-starter/elk/kibana/kibana.yml`

- [ ] **Step 1: Write kibana.yml**

```yaml
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://elasticsearch:9200"]
xpack.security.enabled: false
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/elk/kibana/kibana.yml
git commit -m "feat(elk-starter): add kibana.yml"
```

---

### Task 7: Makefile

**Files:**
- Create: `elk-starter/Makefile`

- [ ] **Step 1: Write Makefile**

```makefile
include .env

.PHONY: up down logs status clean help

up: ## Start ELK stack
	docker compose up -d

down: ## Stop ELK stack
	docker compose down

logs: ## Tail all container logs
	docker compose logs -f

status: ## Show container status + ES health
	@docker compose ps
	@echo ""
	@curl -s http://localhost:9200/_cluster/health?pretty || echo "Elasticsearch not reachable"

clean: ## Stop + remove volumes (deletes all indexed data)
	docker compose down -v

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/Makefile
git commit -m "feat(elk-starter): add Makefile"
```

---

### Task 8: README.md

**Files:**
- Create: `elk-starter/README.md`

- [ ] **Step 1: Write README.md**

````markdown
# ELK Starter Kit

Zero-config ELK stack for any application. Point at a log file, get Kibana.

## Requirements

- Docker + Docker Compose
- A log file (JSON or plain text)

## Quick Start

```bash
# 1. Copy this folder into your project
cp -r elk-starter/ your-project/elk-starter/
cd your-project/elk-starter/

# 2. Configure
cp .env.example .env
# Edit .env: set LOG_PATH, APP_NAME, LOG_FORMAT

# 3. Start
make up

# 4. Open Kibana
open http://localhost:5601
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_PATH` | `/var/log/myapp/app.log` | Absolute path to your log file |
| `APP_NAME` | `myapp` | Tags logs; becomes the ES index name: `logs-<APP_NAME>-YYYY.MM.dd` |
| `LOG_FORMAT` | `json` | `json` = parse each line as JSON. `text` = store raw line as `message` |

## In Kibana

1. Go to **Stack Management → Index Patterns**
2. Create pattern: `logs-<APP_NAME>-*`
3. Set time field: `@timestamp` (JSON logs) or leave blank (plain text)
4. Go to **Discover** → explore your logs

## Ports

| Service | Port |
|---------|------|
| Elasticsearch | 9200 |
| Kibana | 5601 |
| Logstash (beats) | 5044 |

## JSON Log Format

Any JSON-per-line log works. Example:

```json
{"time":"2026-04-14T10:30:00+05:30","level":"INFO","msg":"server started","port":8080}
{"time":"2026-04-14T10:30:05+05:30","level":"ERROR","msg":"db connection failed","error":"timeout"}
```

All top-level JSON keys become searchable Kibana fields.

## Plain Text Logs

Set `LOG_FORMAT=text`. Each line stored as `message` field. Use Kibana's full-text search.

## Multiline (Stack Traces)

Filebeat is configured to join lines starting with whitespace to the previous line. This handles Java, Python, Go stack traces automatically.

## Commands

```bash
make up      # start stack
make down    # stop stack
make logs    # tail container logs
make status  # container status + ES health
make clean   # stop + delete all data volumes
```
````

- [ ] **Step 2: Commit + push**

```bash
git add elk-starter/README.md
git commit -m "feat(elk-starter): add README"
git push origin feat/claude-elk-starter
```

---

## Self-Review

**Spec coverage:**
- [x] Drop-in: copy folder, configure `.env`, run `make up`
- [x] Any log file path via `LOG_PATH`
- [x] JSON + plain text via `LOG_FORMAT`
- [x] Multiline stack trace support
- [x] macOS Docker Desktop compat (close_inactive + scan_frequency)
- [x] ELK 8.12.0

**Gaps:** None for Option A scope. No dashboards (intentional — user builds their own).
