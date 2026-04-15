# /observe Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two auto-discovering Claude Code skills inside `elk-starter/` — `/observe` (interactive ELK onboarding) and `/kibana-agent` (plain-English Kibana artifact generator with Slack alerts).

**Architecture:** Project-level skills in `elk-starter/.claude/skills/observe/` auto-discover when teammates copy the folder. `/observe` collects config and writes `.env`. `/kibana-agent` generates ndjson saved objects and curl commands for dashboards, discover views, and Slack-connected alerting rules. Everything stays inside `elk-starter/`.

**Tech Stack:** Claude Code skills (Markdown + YAML frontmatter), Kibana 8.12 saved objects API, Kibana 8.12 alerting REST API, curl

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `elk-starter/.claude/skills/observe/SKILL.md` | `/observe` skill — Q&A, `.env` writer, startup guide |
| Create | `elk-starter/.claude/skills/observe/kibana-agent.md` | `/kibana-agent` sub-skill — ndjson generator + Slack alerts |
| Create | `elk-starter/.claude/skills/observe/templates/dashboard.ndjson.tmpl` | Reference template: Lens viz + dashboard saved objects |
| Create | `elk-starter/.claude/skills/observe/templates/discover.ndjson.tmpl` | Reference template: saved search saved object |
| Create | `elk-starter/.claude/skills/observe/templates/alert.ndjson.tmpl` | Reference template: alerting rule + webhook connector |
| Create | `elk-starter/kibana/.gitkeep` | Output dir for generated ndjson artifacts |
| Modify | `elk-starter/docker-compose.yml` | Parameterise KIBANA_PORT and ES_HEAP_SIZE via env vars |
| Modify | `elk-starter/.env.example` (create) | Document all supported `.env` variables |

---

## Task 1: Parameterise docker-compose.yml

**Files:**
- Modify: `elk-starter/docker-compose.yml`

- [ ] **Step 1: Read current docker-compose.yml**

```bash
cat elk-starter/docker-compose.yml
```

- [ ] **Step 2: Replace hardcoded ES heap and Kibana port**

In `elk-starter/docker-compose.yml`, change:

```yaml
# elasticsearch service — before
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
# elasticsearch service — after
      - ES_JAVA_OPTS=-Xms${ES_HEAP_SIZE:-512}m -Xmx${ES_HEAP_SIZE:-512}m
```

```yaml
# kibana service ports — before
    ports:
      - "5601:5601"
# kibana service ports — after
    ports:
      - "${KIBANA_PORT:-5601}:5601"
```

- [ ] **Step 3: Verify compose file is valid**

```bash
cd elk-starter && docker compose config --quiet && echo "OK"
```

Expected: `OK` (no errors)

- [ ] **Step 4: Commit**

```bash
cd elk-starter && git add docker-compose.yml
git commit -m "feat(observe): parameterise ES heap and Kibana port in docker-compose"
```

---

## Task 2: Create .env.example

**Files:**
- Create: `elk-starter/.env.example`

- [ ] **Step 1: Write .env.example**

Create `elk-starter/.env.example`:

```bash
# Required
APP_NAME=myapp
LOG_PATH=/absolute/path/to/your/app.log
LOG_FORMAT=json

# Optional (uncomment to override defaults)
# RETENTION_DAYS=7
# ES_HEAP_SIZE=512
# KIBANA_PORT=5601
```

- [ ] **Step 2: Verify README quick-start matches**

```bash
grep "env.example" elk-starter/README.md
```

Expected: one match (`cp .env.example .env`)

- [ ] **Step 3: Commit**

```bash
git add elk-starter/.env.example
git commit -m "feat(observe): add .env.example with all supported variables"
```

---

## Task 3: Create output directory

**Files:**
- Create: `elk-starter/kibana/.gitkeep`

- [ ] **Step 1: Create dir + gitkeep**

```bash
mkdir -p elk-starter/kibana
touch elk-starter/kibana/.gitkeep
```

- [ ] **Step 2: Commit**

```bash
git add elk-starter/kibana/.gitkeep
git commit -m "feat(observe): add elk-starter/kibana/ output dir for generated artifacts"
```

---

## Task 4: Write /observe SKILL.md

**Files:**
- Create: `elk-starter/.claude/skills/observe/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p elk-starter/.claude/skills/observe/templates
```

- [ ] **Step 2: Write SKILL.md**

Create `elk-starter/.claude/skills/observe/SKILL.md` with exact content:

```markdown
---
name: observe
description: >
  Interactive ELK stack onboarding for any application. Collects app name,
  log path, and format; writes .env; gives make up startup command; then
  offers /kibana-agent for dashboards and Slack alerts.
---

# /observe — ELK Onboarding

You are an interactive ELK stack setup assistant. Guide the user step by step through configuring `elk-starter/`.

## Rules
- Ask exactly ONE question per message. Wait for answer before continuing.
- Never write `.env` until ALL questions are answered.
- All file writes stay inside `elk-starter/`. Never touch parent project files.
- Use the Write tool to create files — do not output file content and ask user to paste it.

## Step 1: Check existing config

Read `elk-starter/.env`.

If it exists and APP_NAME is set, respond:
> "Stack already configured for **{APP_NAME}**.
>
> What would you like to do?
> 1. Reconfigure — overwrite .env with new settings
> 2. Create dashboards — type `/kibana-agent` or describe what you want to see
> 3. Just start the stack: `cd elk-starter && make up`"

Wait for choice. If 1, proceed to Step 2. If 2, invoke kibana-agent skill. If 3, show make up command and stop.

If `.env` missing or APP_NAME not set, proceed to Step 2.

## Step 2: App name

Ask:
> "What's your **app name**?
>
> This becomes your Elasticsearch index prefix. Example: `myapp` → index `logs-myapp-YYYY.MM.dd`
>
> Rules: lowercase letters, numbers, hyphens only. No spaces."

Validate: must match `^[a-z0-9][a-z0-9-]*$`. If invalid, explain and re-ask.
Store answer as `APP_NAME`.

## Step 3: Log file path

Ask:
> "What's the **absolute path** to your log file?
>
> Example: `/Users/you/projects/myapp/logs/app.log`"

Rules:
- Must start with `/`
- On macOS: Docker Desktop only mounts directories shared in Docker → Preferences → Resources → File Sharing

If path doesn't start with `/`, explain and re-ask.
Store answer as `LOG_PATH`.

## Step 4: Log format

Ask:
> "What **format** are your logs?
>
> 1. **json** — each line is a JSON object (recommended — gives searchable fields in Kibana)
>    `{"time":"2026-04-14T10:00:00Z","level":"ERROR","msg":"db failed"}`
>
> 2. **text** — plain text lines (stored as `message` field, full-text search only)
>    `2026-04-14 10:00:00 ERROR db failed`"

Store `1` → `json`, `2` → `text` as `LOG_FORMAT`.

## Step 5: Customize ELK settings

Ask:
> "Want to customize ELK settings?
>
> 1. **Yes** — set retention period, memory, and Kibana port
> 2. **No** — use defaults: 7-day retention, 512MB ES heap, Kibana on port 5601"

If **Yes**, ask these three questions one at a time:

**5a:** "Log **retention** in days? (default: 7)"
Store as `RETENTION_DAYS`. Default: `7`.

**5b:** "Elasticsearch **heap size** in MB? (default: 512 — use 1024 or more for production)"
Store as `ES_HEAP_SIZE`. Default: `512`.

**5c:** "**Kibana port**? (default: 5601)"
Store as `KIBANA_PORT`. Default: `5601`.

If **No**, use defaults: RETENTION_DAYS=7, ES_HEAP_SIZE=512, KIBANA_PORT=5601.

## Step 6: Write .env

Use the Write tool to create `elk-starter/.env` with this exact content (substituting collected values):

```
APP_NAME=<APP_NAME>
LOG_PATH=<LOG_PATH>
LOG_FORMAT=<LOG_FORMAT>
RETENTION_DAYS=<RETENTION_DAYS>
ES_HEAP_SIZE=<ES_HEAP_SIZE>
KIBANA_PORT=<KIBANA_PORT>
```

Then confirm to the user:
> ".env written. Your configuration:
> - App: `<APP_NAME>`
> - Logs: `<LOG_PATH>` (<LOG_FORMAT> format)
> - Kibana: http://localhost:<KIBANA_PORT>
> - Retention: <RETENTION_DAYS> days | ES heap: <ES_HEAP_SIZE>MB"

## Step 7: Start the stack

Show:
> "**Start your ELK stack:**
> ```bash
> cd elk-starter
> make up
> ```
> Then open: **http://localhost:<KIBANA_PORT>**
>
> Takes ~30 seconds to be ready. Check health: `make status`
>
> Trouble? See `elk-starter/README.md` troubleshooting section."

## Step 8: Offer Kibana setup

Ask:
> "Want to create dashboards, saved searches, or Slack alerts for your logs?
>
> Describe what you want to see — for example:
> - '403 errors by endpoint and user-id on a bar chart'
> - 'slow queries over time as a line chart'
> - 'alert me when error rate exceeds 10 per minute with a Slack notification'
>
> Or type `/kibana-agent` to start the Kibana assistant."

If the user describes something (not just "yes" or "/kibana-agent"), invoke the kibana-agent skill immediately with their description as the opening context — skip kibana-agent's Step 2 re-prompt.
```

- [ ] **Step 3: Verify file exists and frontmatter is valid YAML**

```bash
head -10 elk-starter/.claude/skills/observe/SKILL.md
```

Expected: shows `---`, `name: observe`, `description:` lines.

- [ ] **Step 4: Verify skill is discoverable**

```bash
ls -la elk-starter/.claude/skills/observe/
```

Expected: `SKILL.md` present.

- [ ] **Step 5: Commit**

```bash
git add elk-starter/.claude/skills/observe/SKILL.md
git commit -m "feat(observe): add /observe skill — interactive ELK onboarding"
```

---

## Task 5: Write /kibana-agent skill

**Files:**
- Create: `elk-starter/.claude/skills/observe/kibana-agent.md`

- [ ] **Step 1: Write kibana-agent.md**

Create `elk-starter/.claude/skills/observe/kibana-agent.md` with exact content:

````markdown
---
name: kibana-agent
description: >
  Interactive Kibana 8.12 artifact generator. Creates dashboards, discover saved
  searches, and Slack-connected alert rules from plain English. Generates importable
  .ndjson files and curl commands. Run /observe first to configure elk-starter/.env.
---

# /kibana-agent — Kibana Artifact Generator

You create Kibana 8.12 saved objects from plain English descriptions. You ask follow-up questions one at a time, generate `.ndjson` files in `elk-starter/kibana/`, and provide curl commands to apply them.

## Rules
- Ask ONE question per message. Wait for answer.
- All output files go in `elk-starter/kibana/`. Create the directory if it doesn't exist.
- ELK version: 8.12.0. Use only API features available in this version.
- xpack.security is disabled — no auth headers needed.
- Use the Write tool for all file creation.

## Step 1: Read config

Read `elk-starter/.env`. Extract:
- `APP_NAME` → index pattern: `logs-<APP_NAME>-*`
- `KIBANA_PORT` → default `5601` if missing

If `.env` missing or APP_NAME not set:
> "Please run `/observe` first to configure your ELK stack, then come back here."
Stop.

## Step 2: Understand the request

If the user already described what they want (arrived from `/observe`), use that as the description and skip this prompt.

Otherwise ask:
> "What would you like to see in Kibana?
>
> Examples:
> - '403 errors by endpoint and user-id on a bar chart'
> - 'slow queries over time as a line chart'
> - 'table of ERROR logs with timestamp, message, and service name'
> - 'alert me when error rate exceeds 10 per minute'
> - 'alert with Slack when any CRITICAL log appears'"

Classify intent:
- Contains chart / graph / histogram / pie / metric → **dashboard**
- Contains table / list / search / show / find / display → **discover**
- Contains alert / notify / when / trigger / ping → **alert**
- Contains Slack + alert → **alert** (pre-select Slack in Step 5)

## Step 3: Follow-up questions (one at a time)

**3a. Time range** (always ask unless user specified one):
> "Default time range for this view?
> 1. Last 15 minutes (`now-15m`)
> 2. Last 1 hour (`now-1h`)
> 3. Last 24 hours (`now-24h`)
> 4. Last 7 days (`now-7d`)
> 5. Custom — specify (e.g. `now-30m`)"

**3b. Filters** (ask unless description makes them completely clear):
> "Any specific filters to apply?
> Use KQL syntax — examples:
> - `level:ERROR`
> - `http.status:403`
> - `service:auth AND response_time_ms > 500`
>
> Type 'none' to skip."

**3c. Chart type** (dashboard only — skip for discover/alert):
> "Chart type?
> 1. Bar — grouped counts (e.g. errors per endpoint)
> 2. Line — trend over time
> 3. Pie — proportion breakdown
> 4. Metric — single number (e.g. total error count)
> 5. Data table — counts per category"

**3d. Title**:
> "Title for this artifact?"

Derive `SLUG` from title: lowercase, replace spaces with hyphens, strip non-alphanumeric except hyphens.
Generate `SHORT_ID`: 4 random hex chars (e.g. `a3f2`).
Set `VIZ_ID = <SLUG>-viz-<SHORT_ID>`, `DASH_ID = <SLUG>-dash-<SHORT_ID>`, `SEARCH_ID = <SLUG>-<SHORT_ID>`.
Set `INDEX_PATTERN_ID = logs-<APP_NAME>`.
Set `NOW_ISO` = current UTC time in ISO 8601 format.

## Step 4: Generate ndjson artifact

Create `elk-starter/kibana/` directory if it doesn't exist.

### Dashboard artifact

Write `elk-starter/kibana/<SLUG>.ndjson` with two JSON lines:

**Line 1 — Lens visualization:**

```json
{"id":"<VIZ_ID>","type":"lens","attributes":{"title":"<TITLE>","visualizationType":"<VIZ_TYPE>","state":{"datasourceStates":{"formBased":{"layers":{"layer1":{"columnOrder":["col1","col2"],"columns":{"col1":{"label":"<X_FIELD>","dataType":"string","operationType":"terms","sourceField":"<X_FIELD>.keyword","params":{"size":10,"orderBy":{"type":"column","columnId":"col2"},"orderDirection":"desc"}},"col2":{"label":"Count","dataType":"number","operationType":"count","isBucketed":false}}}}}},"filters":[],"query":{"query":"<KQL_QUERY>","language":"kuery"},"visualization":{"legend":{"isVisible":true,"position":"right"},"preferredSeriesType":"<SERIES_TYPE>","layers":[{"layerId":"layer1","accessors":["col2"],"position":"top","seriesType":"<SERIES_TYPE>","xAccessor":"col1"}]}}},"references":[{"type":"index-pattern","id":"<INDEX_PATTERN_ID>","name":"indexpattern-datasource-current-indexpattern"},{"type":"index-pattern","id":"<INDEX_PATTERN_ID>","name":"indexpattern-datasource-layer-layer1"}],"coreMigrationVersion":"8.12.0","updated_at":"<NOW_ISO>","version":"1","namespaces":["default"]}
```

**Line 2 — Dashboard:**

```json
{"id":"<DASH_ID>","type":"dashboard","attributes":{"title":"<TITLE>","description":"Generated by /kibana-agent","panelsJSON":"[{\"version\":\"8.12.0\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":15,\"i\":\"panel1\"},\"panelIndex\":\"panel1\",\"embeddableConfig\":{\"enhancements\":{}},\"panelRefName\":\"panel_panel1\"}]","optionsJSON":"{\"useMargins\":true,\"syncColors\":false,\"hidePanelTitles\":false}","timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"name":"panel_panel1","type":"lens","id":"<VIZ_ID>"}],"coreMigrationVersion":"8.12.0","updated_at":"<NOW_ISO>","version":"1","namespaces":["default"]}
```

Chart type → Kibana values:

| User choice | VIZ_TYPE | SERIES_TYPE |
|-------------|----------|-------------|
| bar | lnsXY | bar_stacked |
| line | lnsXY | line |
| pie | lnsPie | — |
| metric | lnsMetric | — |
| data table | lnsDatatable | — |

For pie/metric/data table, the `visualization` block differs from XY — omit `preferredSeriesType` and `layers` with seriesType; use the Lens-appropriate visualization config instead (the state schema for those types uses simpler structures).

Derive `X_FIELD` from user description:
- "by endpoint" → `url.path` or `endpoint`
- "by user-id" → `user_id`
- "by service" → `service`
- "by status" → `http.status`
- "over time" → use date histogram with `@timestamp` as X axis instead of terms

`KQL_QUERY`: build from filters collected in 3b. Empty string if none.

### Discover artifact

Write `elk-starter/kibana/<SLUG>.ndjson` with one JSON line:

```json
{"id":"<SEARCH_ID>","type":"search","attributes":{"title":"<TITLE>","description":"Generated by /kibana-agent","hits":0,"columns":<COLUMNS_JSON>,"sort":[["@timestamp","desc"]],"version":1,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"highlightAll\":true,\"version\":true,\"query\":{\"query\":\"<KQL_QUERY>\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"}},"references":[{"name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern","id":"<INDEX_PATTERN_ID>"}],"coreMigrationVersion":"8.12.0","updated_at":"<NOW_ISO>","version":"1","namespaces":["default"]}
```

`COLUMNS_JSON`: JSON array. Always start with `["@timestamp","level","message"]`, then append any fields mentioned in the description (e.g. `"service"`, `"user_id"`, `"response_time_ms"`).

### Alert artifact

Write `elk-starter/kibana/<SLUG>-alert.json` (plain JSON for REST API):

```json
{
  "name": "<TITLE>",
  "rule_type_id": ".es-query",
  "consumer": "alerts",
  "enabled": true,
  "tags": ["<APP_NAME>", "observe"],
  "schedule": {"interval": "<CHECK_INTERVAL>"},
  "actions": [],
  "params": {
    "index": ["logs-<APP_NAME>-*"],
    "timeField": "@timestamp",
    "esQuery": "{\"query\":{\"bool\":{\"filter\":[<QUERY_FILTERS_JSON>]}}}",
    "timeWindowSize": <TIME_WINDOW_SIZE>,
    "timeWindowUnit": "<TIME_WINDOW_UNIT>",
    "thresholdComparator": "<COMPARATOR>",
    "threshold": [<THRESHOLD>],
    "size": 100
  }
}
```

Parse alert condition from user description:
- "more than 10 errors in 5 minutes" → threshold=10, comparator=">", timeWindowSize=5, timeWindowUnit="m", checkInterval="1m"
- "any CRITICAL log" → threshold=0, comparator=">=", timeWindowSize=5, timeWindowUnit="m", checkInterval="1m"
- "exceeds 100 per hour" → threshold=100, comparator=">", timeWindowSize=60, timeWindowUnit="m", checkInterval="5m"

`QUERY_FILTERS_JSON`: ES filter clauses. Example for `level:ERROR`:
`{"term":{"level":"ERROR"}}`

Also write `elk-starter/kibana/<SLUG>-alert.ndjson` (saved-object format, for version control reference) alongside the REST API JSON.

## Step 5: Slack alert

Ask (skip this question if user already mentioned Slack in their description — go straight to 5a):
> "Want a Slack alert for this?
> 1. Yes — set up a Slack webhook notification
> 2. No — skip"

If **Yes**:

**5a:** "Paste your **Slack webhook URL** (from api.slack.com → Your Apps → Incoming Webhooks):"

**5b:** "What should trigger the alert? For example:
- 'more than 10 errors in 5 minutes'
- 'any CRITICAL log'
- 'more than 100 requests with status 503 in 1 hour'"

**5c:** "How often can this alert fire?
1. Every time the condition is met
2. At most once every 30 minutes
3. At most once per hour"

**5d:** "Slack message format?
1. Auto-generate (app name, condition, timestamp, Kibana link)
2. Custom — I'll provide it"

If custom: "Type your message. Use `{{count}}` for event count, `{{timestamp}}` for trigger time, `{{kibana_url}}` for Kibana link."

**Show Slack message preview** (auto format):
```
:rotating_light: *[<APP_NAME>] Alert: <TITLE>*
Triggered: {{timestamp}}
Events: {{count}} matches in the last <window>
View in Kibana: http://localhost:<KIBANA_PORT>/app/discover
```

**Write connector** `elk-starter/kibana/<SLUG>-slack-connector.json`:

```json
{
  "name": "Slack - <APP_NAME>",
  "connector_type_id": ".webhook",
  "config": {
    "method": "POST",
    "url": "<SLACK_WEBHOOK_URL>",
    "headers": {"Content-Type": "application/json"},
    "hasAuth": false
  },
  "secrets": {}
}
```

**Update alert JSON** — add Slack action to the `actions` array in `<SLUG>-alert.json`:

```json
{
  "group": "query matched",
  "id": "{{connector_id}}",
  "params": {
    "subAction": "run",
    "subActionParams": {
      "body": "{\"text\":\"<SLACK_MESSAGE_ESCAPED>\"}"
    }
  }
}
```

Note: `{{connector_id}}` is filled after the connector is created via the API. Show the user: "After creating the connector (Step 6 curl), copy the returned `id` and update the alert JSON before creating the rule."

Set throttle based on 5c:
- Every time → omit `throttle`
- 30 min → `"throttle": "30m"`
- 1 hour → `"throttle": "1h"`

## Step 6: Generate curl commands

Show all curl commands that apply:

**Import dashboard or discover (saved objects):**
```bash
curl -X POST "http://localhost:<KIBANA_PORT>/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" \
  -F file=@elk-starter/kibana/<SLUG>.ndjson
```

**Create Slack connector (returns connector id):**
```bash
curl -X POST "http://localhost:<KIBANA_PORT>/api/actions/connector" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @elk-starter/kibana/<SLUG>-slack-connector.json
```

**Create alert rule:**
```bash
curl -X POST "http://localhost:<KIBANA_PORT>/api/alerting/rule" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @elk-starter/kibana/<SLUG>-alert.json
```

## Step 7: Apply or save

Ask:
> "Apply now or save for later?
> 1. **Apply now** — run the curl commands above automatically
> 2. **Save** — keep files in elk-starter/kibana/ and import manually later"

If **Apply now**, run each curl command via the Bash tool in order. Show response. If connector creation succeeded, extract the `id` from the response JSON and update `<SLUG>-alert.json` with it before running the alert rule curl.

## Step 8: Offer more

Ask:
> "Want another dashboard, saved search, or alert?
> Describe it or type 'done'."

If user describes more, loop back to Step 2 (skip Step 1 — config already loaded).
````

- [ ] **Step 2: Verify file exists**

```bash
head -8 elk-starter/.claude/skills/observe/kibana-agent.md
```

Expected: shows `---`, `name: kibana-agent`, `description:` lines.

- [ ] **Step 3: Commit**

```bash
git add elk-starter/.claude/skills/observe/kibana-agent.md
git commit -m "feat(observe): add /kibana-agent skill — Kibana artifact generator with Slack alerts"
```

---

## Task 6: Write ndjson reference templates

**Files:**
- Create: `elk-starter/.claude/skills/observe/templates/dashboard.ndjson.tmpl`
- Create: `elk-starter/.claude/skills/observe/templates/discover.ndjson.tmpl`
- Create: `elk-starter/.claude/skills/observe/templates/alert.ndjson.tmpl`

These are human-readable reference templates teammates can inspect. `{{PLACEHOLDER}}` vars are substituted by `/kibana-agent` at generation time.

- [ ] **Step 1: Write dashboard.ndjson.tmpl**

Create `elk-starter/.claude/skills/observe/templates/dashboard.ndjson.tmpl`:

```
# Dashboard template — Kibana 8.12
# Variables: VIZ_ID, DASH_ID, TITLE, VIZ_TYPE, X_FIELD, SERIES_TYPE, KQL_QUERY, INDEX_PATTERN_ID, NOW_ISO
# VIZ_TYPE options: lnsXY (bar/line), lnsPie, lnsMetric, lnsDatatable
# SERIES_TYPE options (lnsXY only): bar_stacked, line
#
# Line 1: Lens visualization saved object
{"id":"{{VIZ_ID}}","type":"lens","attributes":{"title":"{{TITLE}}","visualizationType":"{{VIZ_TYPE}}","state":{"datasourceStates":{"formBased":{"layers":{"layer1":{"columnOrder":["col1","col2"],"columns":{"col1":{"label":"{{X_FIELD}}","dataType":"string","operationType":"terms","sourceField":"{{X_FIELD}}.keyword","params":{"size":10,"orderBy":{"type":"column","columnId":"col2"},"orderDirection":"desc"}},"col2":{"label":"Count","dataType":"number","operationType":"count","isBucketed":false}}}}}},"filters":[],"query":{"query":"{{KQL_QUERY}}","language":"kuery"},"visualization":{"legend":{"isVisible":true,"position":"right"},"preferredSeriesType":"{{SERIES_TYPE}}","layers":[{"layerId":"layer1","accessors":["col2"],"position":"top","seriesType":"{{SERIES_TYPE}}","xAccessor":"col1"}]}}},"references":[{"type":"index-pattern","id":"{{INDEX_PATTERN_ID}}","name":"indexpattern-datasource-current-indexpattern"},{"type":"index-pattern","id":"{{INDEX_PATTERN_ID}}","name":"indexpattern-datasource-layer-layer1"}],"coreMigrationVersion":"8.12.0","updated_at":"{{NOW_ISO}}","version":"1","namespaces":["default"]}
#
# Line 2: Dashboard saved object
{"id":"{{DASH_ID}}","type":"dashboard","attributes":{"title":"{{TITLE}}","description":"Generated by /kibana-agent","panelsJSON":"[{\"version\":\"8.12.0\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":15,\"i\":\"panel1\"},\"panelIndex\":\"panel1\",\"embeddableConfig\":{\"enhancements\":{}},\"panelRefName\":\"panel_panel1\"}]","optionsJSON":"{\"useMargins\":true,\"syncColors\":false,\"hidePanelTitles\":false}","timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"name":"panel_panel1","type":"lens","id":"{{VIZ_ID}}"}],"coreMigrationVersion":"8.12.0","updated_at":"{{NOW_ISO}}","version":"1","namespaces":["default"]}
```

- [ ] **Step 2: Write discover.ndjson.tmpl**

Create `elk-starter/.claude/skills/observe/templates/discover.ndjson.tmpl`:

```
# Discover (saved search) template — Kibana 8.12
# Variables: SEARCH_ID, TITLE, COLUMNS_JSON, KQL_QUERY, INDEX_PATTERN_ID, NOW_ISO
# COLUMNS_JSON example: ["@timestamp","level","message","service"]
#
{"id":"{{SEARCH_ID}}","type":"search","attributes":{"title":"{{TITLE}}","description":"Generated by /kibana-agent","hits":0,"columns":{{COLUMNS_JSON}},"sort":[["@timestamp","desc"]],"version":1,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"highlightAll\":true,\"version\":true,\"query\":{\"query\":\"{{KQL_QUERY}}\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"}},"references":[{"name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern","id":"{{INDEX_PATTERN_ID}}"}],"coreMigrationVersion":"8.12.0","updated_at":"{{NOW_ISO}}","version":"1","namespaces":["default"]}
```

- [ ] **Step 3: Write alert.ndjson.tmpl**

Create `elk-starter/.claude/skills/observe/templates/alert.ndjson.tmpl`:

```
# Alert rule template — Kibana 8.12 REST API format (POST /api/alerting/rule)
# Variables: TITLE, APP_NAME, CHECK_INTERVAL, QUERY_FILTERS_JSON, TIME_WINDOW_SIZE,
#            TIME_WINDOW_UNIT, COMPARATOR, THRESHOLD, CONNECTOR_ID, SLACK_MESSAGE_ESCAPED
# COMPARATOR options: >, >=, <, <=, ==
# TIME_WINDOW_UNIT options: s, m, h
# CHECK_INTERVAL examples: "1m", "5m"
#
# File: <slug>-alert.json (used with curl -d @file)
{
  "name": "{{TITLE}}",
  "rule_type_id": ".es-query",
  "consumer": "alerts",
  "enabled": true,
  "tags": ["{{APP_NAME}}", "observe"],
  "schedule": {"interval": "{{CHECK_INTERVAL}}"},
  "actions": [
    {
      "group": "query matched",
      "id": "{{CONNECTOR_ID}}",
      "params": {
        "subAction": "run",
        "subActionParams": {
          "body": "{\"text\":\"{{SLACK_MESSAGE_ESCAPED}}\"}"
        }
      }
    }
  ],
  "params": {
    "index": ["logs-{{APP_NAME}}-*"],
    "timeField": "@timestamp",
    "esQuery": "{\"query\":{\"bool\":{\"filter\":[{{QUERY_FILTERS_JSON}}]}}}",
    "timeWindowSize": {{TIME_WINDOW_SIZE}},
    "timeWindowUnit": "{{TIME_WINDOW_UNIT}}",
    "thresholdComparator": "{{COMPARATOR}}",
    "threshold": [{{THRESHOLD}}],
    "size": 100
  }
}

# Slack webhook connector template — Kibana 8.12 REST API format
# (POST /api/actions/connector — returns {id} used as CONNECTOR_ID above)
# File: <slug>-slack-connector.json
{
  "name": "Slack - {{APP_NAME}}",
  "connector_type_id": ".webhook",
  "config": {
    "method": "POST",
    "url": "{{SLACK_WEBHOOK_URL}}",
    "headers": {"Content-Type": "application/json"},
    "hasAuth": false
  },
  "secrets": {}
}
```

- [ ] **Step 4: Verify all three templates exist**

```bash
ls elk-starter/.claude/skills/observe/templates/
```

Expected: `alert.ndjson.tmpl  dashboard.ndjson.tmpl  discover.ndjson.tmpl`

- [ ] **Step 5: Commit**

```bash
git add elk-starter/.claude/skills/observe/templates/
git commit -m "feat(observe): add ndjson reference templates for dashboard, discover, alert"
```

---

## Task 7: Smoke test /observe skill

No unit tests for skill files — verify structure and content manually.

- [ ] **Step 1: Verify skill file structure**

```bash
find elk-starter/.claude -type f | sort
```

Expected output:
```
elk-starter/.claude/skills/observe/SKILL.md
elk-starter/.claude/skills/observe/kibana-agent.md
elk-starter/.claude/skills/observe/templates/alert.ndjson.tmpl
elk-starter/.claude/skills/observe/templates/dashboard.ndjson.tmpl
elk-starter/.claude/skills/observe/templates/discover.ndjson.tmpl
```

- [ ] **Step 2: Verify SKILL.md frontmatter**

```bash
python3 -c "
import sys
content = open('elk-starter/.claude/skills/observe/SKILL.md').read()
assert content.startswith('---'), 'Missing opening ---'
end = content.index('---', 3)
frontmatter = content[3:end]
assert 'name: observe' in frontmatter, 'Missing name field'
assert 'description:' in frontmatter, 'Missing description field'
print('SKILL.md frontmatter OK')
"
```

Expected: `SKILL.md frontmatter OK`

- [ ] **Step 3: Verify kibana-agent.md frontmatter**

```bash
python3 -c "
content = open('elk-starter/.claude/skills/observe/kibana-agent.md').read()
assert content.startswith('---'), 'Missing opening ---'
end = content.index('---', 3)
frontmatter = content[3:end]
assert 'name: kibana-agent' in frontmatter
assert 'description:' in frontmatter
print('kibana-agent.md frontmatter OK')
"
```

Expected: `kibana-agent.md frontmatter OK`

- [ ] **Step 4: Verify required sections present in SKILL.md**

```bash
python3 -c "
content = open('elk-starter/.claude/skills/observe/SKILL.md').read()
required = ['Step 1', 'Step 2', 'Step 3', 'Step 4', 'Step 5', 'Step 6', 'Step 7', 'Step 8', 'APP_NAME', 'LOG_PATH', 'LOG_FORMAT', '.env', 'make up']
for r in required:
    assert r in content, f'Missing: {r}'
print('All required sections present')
"
```

Expected: `All required sections present`

- [ ] **Step 5: Verify required sections present in kibana-agent.md**

```bash
python3 -c "
content = open('elk-starter/.claude/skills/observe/kibana-agent.md').read()
required = ['Step 1', 'Step 2', 'Step 3', 'Step 4', 'Step 5', 'Step 6', 'Step 7', 'Step 8', 'lnsXY', 'bar_stacked', 'kbn-xsrf', 'Slack', '/api/alerting/rule', '/api/actions/connector', 'APP_NAME', 'ndjson']
for r in required:
    assert r in content, f'Missing: {r}'
print('All required sections present')
"
```

Expected: `All required sections present`

- [ ] **Step 6: Verify docker-compose.yml parameterisation**

```bash
grep "ES_HEAP_SIZE\|KIBANA_PORT" elk-starter/docker-compose.yml
```

Expected:
```
      - ES_JAVA_OPTS=-Xms${ES_HEAP_SIZE:-512}m -Xmx${ES_HEAP_SIZE:-512}m
      - "${KIBANA_PORT:-5601}:5601"
```

- [ ] **Step 7: Commit verification results**

No commit needed — read-only verification step.

---

## Task 8: Final commit and push

- [ ] **Step 1: Check all files staged**

```bash
cd /Users/gauravshewale/Development/go/elk-test/.worktrees/claude-elk-starter && git status
```

Expected: clean working tree (all committed in prior tasks).

- [ ] **Step 2: Review commit log**

```bash
git log --oneline main..HEAD
```

Expected: 6+ commits from this feature.

- [ ] **Step 3: Push branch**

```bash
git push origin feat/claude-elk-starter
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task covering it |
|-----------------|-----------------|
| `/observe` skill with Q&A | Task 4 |
| Ask for app name, log path, log format | Task 4 — Steps 2-4 |
| Ask for ELK customization | Task 4 — Step 5 |
| Write .env | Task 4 — Step 6 |
| Show make up + open Kibana | Task 4 — Step 7 |
| Offer /kibana-agent inline | Task 4 — Step 8 |
| /kibana-agent standalone | Task 5 |
| Plain English → dashboard ndjson + curl | Task 5 — Steps 3-4 |
| Plain English → discover ndjson + curl | Task 5 — Steps 3-4 |
| Slack alert interactive Q&A | Task 5 — Step 5 |
| Slack connector + rule ndjson | Task 5 — Steps 5-6 |
| Apply now vs save | Task 5 — Step 7 |
| Loop for more artifacts | Task 5 — Step 8 |
| ndjson reference templates | Task 6 |
| Output dir elk-starter/kibana/ | Task 3 |
| docker-compose KIBANA_PORT param | Task 1 |
| .env.example | Task 2 |
| Everything inside elk-starter/ | All tasks — constraint explicit |
| ELK 8.12 API only | Task 5 — stated in rules |

All spec requirements covered. No placeholders in tasks. Type/field names consistent across tasks.
