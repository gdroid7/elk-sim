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
