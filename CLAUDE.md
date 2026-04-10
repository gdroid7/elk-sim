# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **Go simulator sub-project** of `statucred-logs-example` — a hands-on demo of structured vs plain-text logging using an ELK stack. The Go simulator is a **multi-agent project in planning phase** (see `PLAN.md`). The parent repo (`../`) contains the reference Java implementation.

The simulator runs 5 incident scenarios, each as a standalone Go binary that emits structured JSON logs. A Go HTTP server executes binaries on demand and streams output to a browser via SSE. Logs flow: scenario binary → `logs/sim-<id>.log` → Filebeat → Logstash → Elasticsearch → Kibana.

## Commands

This project has no code yet — it is in the planning phase. Once the `core-builder` agent runs, these commands will be available:

```bash
# Development
make run                  # go run ./cmd/server (port 8080)
make build                # build server binary to bin/simulator
make build-scenarios      # build all 5 scenario binaries to bin/scenarios/
make build-all            # build server + all scenarios

# ELK stack
make docker-up            # docker compose up -d
make docker-down          # docker compose down
make logs                 # tail -f logs/sim-*.log
make clean                # rm -rf bin/ logs/

# Kibana setup/teardown
make setup-all            # bash scripts/setup-all.sh (waits for Kibana, creates indexes/dashboards/alerts)
make reset-all            # bash scripts/reset-all.sh (deletes all Kibana objects + ES indexes)

# Build individual scenario binary
go build ./scenarios/01-auth-brute-force
```

## Architecture

### Execution Model

The server does **not** import scenario code. Each scenario is a **separate Go binary** in `bin/scenarios/<id>`. The HTTP server `exec.Command`s the binary with flags, pipes its stdout as SSE to the browser, and tees to `logs/sim-<id>.log`. This keeps scenario binaries independently testable.

### Key Constraints

- **No external Go packages** — stdlib only (`net/http`, `os/exec`, `log/slog`, etc.)
- **No JS framework** — vanilla HTML/CSS/JS, no CDN
- **ELK locked at 8.12.0**
- **Max 8 fields per log line** in scenario binaries

### Time Compression

Scenarios support `--compress-time` which makes logs emit at 300ms intervals but with synthetic timestamps spread across a 30-minute window. This creates meaningful Kibana timelines from a ~6-second run. All timestamps are in IST (Asia/Kolkata, UTC+5:30) in RFC3339.

### Per-Scenario Index Routing

Each scenario writes to its own ES index (`sim-<scenario-id>`). Filebeat tags each log file with `log_type: sim-<id>`. Logstash routes to the correct index by matching `log_type`. Kibana has a separate data view + dashboard per scenario.

## Agent Ownership

This project uses specialized AI agents. **Do not touch files outside your agent's ownership:**

| Agent | Owns |
|-------|------|
| `core-builder` | `cmd/`, `internal/`, `web/`, `elk/`, `scripts/`, `docker-compose.yml`, `Dockerfile`, `Makefile`, `go.mod` |
| `scenario-implementor` | `scenarios/*/main.go`, `cmd/server/scenarios_init.go` |
| `kibana-expert` | `scenarios/*/setup.sh`, `scenarios/*/reset.sh`, `scenarios/*/dashboard.ndjson`, `scenarios/*/discover_url.md` |
| `demo-expert` | `scenarios/*/README.md`, `scenarios/*/verbal_script.md`, `scenarios/*/notebooklm_prompt.md` |
| `qa-agent` | `qa/report.md` (read-only everywhere else) |
| **All agents** | `agents/` — READ ONLY, never modify |

## Phase Order

Phases must run in order — each depends on the previous:

1. `core-builder` — server, logger, ELK config, UI, Makefile
2. `scenario-implementor` — 5 × `scenarios/0N-name/main.go` (commit+push after each)
3. `kibana-expert` + `demo-expert` — parallel
4. `qa-agent` — end-to-end validation

## Scenario Binaries

Each binary in `scenarios/0N-name/main.go` accepts:

```
--tz=Asia/Kolkata         timezone for timestamps
--compress-time           spread timestamps across --time-window
--time-window=30m         simulated duration (default 30m)
--log-file=<path>         write logs here in addition to stdout
```

Log output is **JSON on stdout**, one object per line, always including `time`, `level`, `msg`, `scenario` fields plus up to 4 scenario-specific fields.

## Worktree Protocol

**Every AI agent/tool works in its own worktree, never directly on `main`.**

### Naming: `.worktrees/<tool>-<role>[-NNN]`

```
<tool>  = claude | gemini | gpt | cursor | copilot | kiro | codex | ...
<role>  = core-builder | scenario-02 | scenario-03 | kibana-expert | demo-expert | qa
[-NNN]  = -002, -003 ... only if same tool+role runs more than once
```

Examples: `.worktrees/claude-scenario-02`, `.worktrees/gemini-kibana-expert`, `.worktrees/gpt-scenario-03-002`

### Create

```bash
git fetch origin main
git worktree add .worktrees/<tool>-<role> -b feat/<tool>-<role> origin/main
```

### Find latest code (picking up mid-project)

```bash
git worktree list                                       # active worktrees
git branch -a --sort=-committerdate | grep feat/       # branches, newest first
git log --oneline main..feat/<tool>-<role>             # what a branch added
```

### Merge & cleanup

```bash
# inside worktree: build passes → commit → push
git push origin feat/<tool>-<role>

# from repo root: merge → push main → cleanup
git checkout main && git pull origin main
git merge feat/<tool>-<role> --no-ff -m "feat(<role>): ..."
git push origin main
git worktree remove .worktrees/<tool>-<role>
git branch -d feat/<tool>-<role>
git push origin --delete feat/<tool>-<role>
```

`.worktrees/` is gitignored — never committed.

## ELK Services

- Elasticsearch: `http://localhost:9200`
- Kibana: `http://localhost:5601`
- Logstash: beats input on port 5044
- Filebeat: watches `./logs/sim-*.log`
