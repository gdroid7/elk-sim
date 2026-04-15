# /observe Skill — Design Spec

**Date:** 2026-04-14  
**Branch:** feat/claude-elk-starter  
**Scope:** `elk-starter/` folder only

---

## Overview

Two Claude Code skills shipped inside `elk-starter/`:

1. `/observe` — interactive onboarding: collects config, writes `.env`, guides stack startup
2. `/kibana-agent` — interactive Kibana artifact generator: dashboards, discover views, alerts, Slack webhooks via plain English

Both auto-discover as project-level skills when teammates copy `elk-starter/` into their project. No install step required.

---

## File Structure

```
elk-starter/
└── .claude/
    └── skills/
        └── observe/
            ├── SKILL.md                  # /observe orchestrator
            ├── kibana-agent.md           # /kibana-agent sub-skill
            └── templates/
                ├── dashboard.ndjson.tmpl
                ├── discover.ndjson.tmpl
                └── alert.ndjson.tmpl
```

Output artifacts written to:
```
elk-starter/
├── .env                        # written by /observe
└── kibana/
    └── <slug>.ndjson           # written by /kibana-agent
```

---

## Approach

**Skill + sub-skill files (Approach B)**

- `/observe` = orchestrator skill: Q&A → `.env` → startup guidance → hands off to `/kibana-agent`
- `/kibana-agent` = standalone sub-skill: loaded on demand, works independently
- Templates in `observe/templates/` are filled by `/kibana-agent` at generation time
- Clean separation: onboarding flow vs Kibana intelligence evolve independently

---

## `/observe` Flow

```
/observe
  ├── 1. Check .env exists?
  │       yes → "Stack already configured. Run make up or /kibana-agent?"
  │       no  → start Q&A
  ├── 2. Q: What is your app name?          → APP_NAME
  ├── 3. Q: Absolute path to your log file? → LOG_PATH (note if file not found)
  ├── 4. Q: Log format — json or text?      → LOG_FORMAT
  ├── 5. Q: Customize ELK config?
  │       yes →
  │         Q: Log retention days? (default: 7)     → RETENTION_DAYS
  │         Q: Elasticsearch heap MB? (default: 512) → ES_HEAP_SIZE
  │         Q: Kibana port? (default: 5601)           → KIBANA_PORT
  │       no  → use defaults
  ├── 6. Write elk-starter/.env
  ├── 7. Show:
  │       cd elk-starter && make up
  │       # then open http://localhost:<KIBANA_PORT>
  └── 8. Offer:
          "Want to create dashboards or alerts? Describe what you want to see,
           or type /kibana-agent"
          → if user describes inline, invoke kibana-agent directly
```

### Constraints
- All questions asked one at a time
- `.env` written only after all answers collected
- macOS Docker Desktop note shown if LOG_PATH is outside home dir

---

## `/kibana-agent` Flow

```
/kibana-agent
  ├── 1. Read APP_NAME from elk-starter/.env → derive ES index pattern
  ├── 2. User describes artifact in plain English
  │       e.g. "403 errors by endpoint and user-id on bar chart"
  │            "show slow queries over time"
  │            "alert me when error rate > 10/min"
  ├── 3. Follow-up Q&A (one at a time):
  │       - Time range? (15m / 1h / 24h / 7d / custom)
  │       - Filters? (e.g. level=ERROR, service=auth, status=403)
  │       - Chart type? (bar / line / pie / table / metric / data table)
  │       - Title for this artifact?
  ├── 4. Generate:
  │       - elk-starter/kibana/<slug>.ndjson  (Kibana saved object)
  │       - curl command to POST to Kibana API
  ├── 5. Q: "Want a Slack alert for this?"
  │       yes →
  │         Q: Slack webhook URL?
  │         Q: Alert condition? (e.g. "more than 10 errors in 5 minutes")
  │         Q: Alert frequency? (every occurrence / throttle Xm / once per hour)
  │         Q: Message format? (auto-generate or custom?)
  │         Generates:
  │           - Kibana connector ndjson (webhook action)
  │           - Kibana alerting rule ndjson
  │           - curl commands: create connector → create rule
  │           - Sample Slack message preview shown inline
  │       no → skip
  ├── 6. Show all artifacts. Ask: "Apply now or save for later?"
  │       "now"  → run curl commands sequentially
  │       "save" → keep ndjson files only
  └── 7. Offer: "Want another dashboard / alert / discover view?"
```

### Artifact types supported
| Type | Description |
|------|-------------|
| Dashboard | Kibana dashboard with one or more panels |
| Discover | Saved search with filters + columns |
| Alert | Threshold rule → webhook action |
| Slack alert | Kibana connector + alert rule → Slack webhook |

### Slack message format (auto-generated)
```
:rotating_light: *[APP_NAME] Alert: <condition>*
Time: <timestamp>
Details: <matched count> events in <window>
<link to Kibana Discover>
```

---

## ndjson Templates

Templates use `{{PLACEHOLDER}}` substitution filled at generation time:

- `dashboard.ndjson.tmpl` — dashboard + visualization saved objects
- `discover.ndjson.tmpl` — saved search with index pattern + filters
- `alert.ndjson.tmpl` — alerting rule + webhook connector

---

## Constraints

- Everything inside `elk-starter/` — no changes to parent project files
- Works in `feat/claude-elk-starter` worktree
- ELK locked at 8.12.0 (Kibana API v8.12)
- No external dependencies (no Python, no Node) — skill uses Claude + curl
- Skill file stays in `elk-starter/.claude/skills/observe/`

---

## Success Criteria

- Teammate copies `elk-starter/`, opens Claude Code, runs `/observe`
- Answers ~5 questions, gets `.env` + startup command
- Runs `/kibana-agent`, describes chart in plain English
- Gets importable ndjson + curl command ready to run
- Optional Slack alert configured interactively
