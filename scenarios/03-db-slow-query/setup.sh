#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

KB="${KIBANA_URL:-http://localhost:5601}"
ES="${ES_URL:-http://localhost:9200}"
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="db-slow-query"
INDEX="sim-${ID}"

echo "[${ID}] Starting setup..."

# ── 1. ES index template ─────────────────────────────────────────────────────
echo "[${ID}] Creating ES index template..."
curl -sf -X PUT "${ES}/_index_template/${INDEX}-template" \
  -H "Content-Type: application/json" \
  -d "{
  \"index_patterns\": [\"${INDEX}\"],
  \"template\": {
    \"mappings\": {
      \"properties\": {
        \"@timestamp\":   {\"type\": \"date\"},
        \"app_level\":    {\"type\": \"keyword\"},
        \"app_message\":  {\"type\": \"text\"},
        \"scenario\":     {\"type\": \"keyword\"},
        \"query_type\":   {\"type\": \"keyword\"},
        \"table\":        {\"type\": \"keyword\"},
        \"duration_ms\":  {\"type\": \"integer\"},
        \"error_code\":   {\"type\": \"keyword\"}
      }
    }
  }
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  acknowledged:', r.get('acknowledged'))"

# ── 2. Import Kibana dashboard ────────────────────────────────────────────────
if [ -f "${SCENARIO_DIR}/dashboard.ndjson" ] && [ -s "${SCENARIO_DIR}/dashboard.ndjson" ]; then
  echo "[${ID}] Importing dashboard..."
  curl -sf -X POST "${KB}/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" \
    --form file=@"${SCENARIO_DIR}/dashboard.ndjson" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('  success:', r.get('success'), '| errors:', r.get('errors', []))"
else
  echo "[${ID}] Skipping dashboard import (dashboard.ndjson not found)"
fi

# ── 3. Ensure server-log connector exists ─────────────────────────────────────
echo "[${ID}] Resolving server-log connector ID..."
SERVER_LOG_CONNECTOR_ID=$(curl -sf "${KB}/api/actions/connectors" \
  -H "kbn-xsrf: true" \
  | python3 -c "
import sys, json
connectors = json.load(sys.stdin)
sl = [c for c in connectors if c.get('connector_type_id') == '.server-log']
if sl:
    print(sl[0]['id'])
else:
    print('')
")

if [ -z "${SERVER_LOG_CONNECTOR_ID}" ]; then
  echo "[${ID}] No server-log connector found — creating one..."
  SERVER_LOG_CONNECTOR_ID=$(curl -sf -X POST "${KB}/api/actions/connector" \
    -H "kbn-xsrf: true" -H "Content-Type: application/json" \
    -d '{
      "name": "Sim Server Log",
      "connector_type_id": ".server-log",
      "config": {}
    }' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
fi
echo "  server-log connector id: ${SERVER_LOG_CONNECTOR_ID}"

# ── 4. Ensure Slack webhook connector exists ──────────────────────────────────
echo "[${ID}] Resolving Slack connector..."
SLACK_CONNECTOR_ID=""

if [ -n "${SLACK_INCOMING_WEBHOOK_URL:-}" ]; then
  SLACK_CONNECTOR_ID=$(curl -sf "${KB}/api/actions/connectors" \
    -H "kbn-xsrf: true" \
    | python3 -c "
import sys, json
connectors = json.load(sys.stdin)
sl = [c for c in connectors if c.get('name') == 'slack-webhook' and c.get('connector_type_id') == '.slack']
if sl:
    print(sl[0]['id'])
else:
    print('')
")

  if [ -z "${SLACK_CONNECTOR_ID}" ]; then
    echo "[${ID}] Creating Slack connector..."
    SLACK_CONNECTOR_ID=$(curl -sf -X POST "${KB}/api/actions/connector" \
      -H "kbn-xsrf: true" -H "Content-Type: application/json" \
      -d "{
        \"name\": \"slack-webhook\",
        \"connector_type_id\": \".slack\",
        \"secrets\": {
          \"webhookUrl\": \"${SLACK_INCOMING_WEBHOOK_URL}\"
        }
      }" | python3 -c "
import sys, json
r = json.load(sys.stdin)
if 'id' in r:
    print(r['id'])
else:
    import sys; print('', file=sys.stderr); print('ERROR creating connector:', r, file=sys.stderr); print('')
")
  fi

  if [ -n "${SLACK_CONNECTOR_ID}" ]; then
    echo "  Slack connector id: ${SLACK_CONNECTOR_ID}"
  else
    echo "  WARNING: Could not create Slack connector (license may be Basic). Falling back to server-log only."
  fi
else
  echo "  SLACK_INCOMING_WEBHOOK_URL not set — skipping Slack connector"
fi

# ── 5. Build actions JSON for alert rules ─────────────────────────────────────
build_actions() {
  local SL_MSG="$1"
  local SLACK_MSG="$2"

  if [ -n "${SLACK_CONNECTOR_ID}" ]; then
    python3 -c "
import json
actions = [
  {'id': '${SERVER_LOG_CONNECTOR_ID}', 'group': 'query matched', 'params': {'level': 'warn', 'message': '''${SL_MSG}'''}},
  {'id': '${SLACK_CONNECTOR_ID}', 'group': 'query matched', 'params': {'message': '''${SLACK_MSG}'''}}
]
print(json.dumps(actions))
"
  else
    python3 -c "
import json
actions = [{'id': '${SERVER_LOG_CONNECTOR_ID}', 'group': 'query matched', 'params': {'level': 'warn', 'message': '''${SL_MSG}'''}}]
print(json.dumps(actions))
"
  fi
}

SLA_BREACH_SLACK_MSG='🚨 *Incident | DB Slow Query — SLA Breach*\n\n*Severity:* HIGH\n*Trigger:* {{context.value}} queries exceeded 200ms SLA in 1 min\n*Table:* {{context.hits.0._source.table}}\n*Query Type:* {{context.hits.0._source.query_type}}\n*Duration:* {{context.hits.0._source.duration_ms}}ms\n*Pattern:* Missing index causing full table scans\n*Risk:* DB overload, connection pool exhaustion\n\n*Action:* Add index to {{context.hits.0._source.table}} table.\n\nIndex: \`sim-db-slow-query\` | Scenario: db-slow-query | Window: 1m'

QUERY_TIMEOUT_SLACK_MSG='🚨 *Incident | DB Slow Query — Query Timeout*\n\n*Severity:* CRITICAL\n*Trigger:* {{context.value}} queries timed out in 1 min\n*Table:* {{context.hits.0._source.table}}\n*Query Type:* {{context.hits.0._source.query_type}}\n*Duration:* {{context.hits.0._source.duration_ms}}ms\n*Pattern:* Query timeout or connection pool exhausted\n*Risk:* Service degradation, cascading failures\n\n*Action:* Immediate investigation required.\n\nIndex: \`sim-db-slow-query\` | Scenario: db-slow-query | Window: 1m'

SLA_BREACH_SL_MSG="[Scenario 03] SLA BREACH: {{context.value}} queries exceeded 200ms SLA in the last 1 minute. Index: ${INDEX}."
QUERY_TIMEOUT_SL_MSG="[Scenario 03] QUERY TIMEOUT: {{context.value}} queries timed out in the last 1 minute. Index: ${INDEX}."

SLA_BREACH_ACTIONS=$(build_actions "${SLA_BREACH_SL_MSG}" "${SLA_BREACH_SLACK_MSG}")
QUERY_TIMEOUT_ACTIONS=$(build_actions "${QUERY_TIMEOUT_SL_MSG}" "${QUERY_TIMEOUT_SLACK_MSG}")

NOTIFY_WHEN='"onActiveAlert"'
THROTTLE_FIELD='"throttle": null,'

# ── 6. Alert rule: SLA Breach ─────────────────────────────────────────────────
echo "[${ID}] Creating alert rule: [Scenario 03] DB Slow Query - SLA Breach..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 03] DB Slow Query - SLA Breach\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"10s\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"term\\\":{\\\"error_code\\\":\\\"SLA_BREACH\\\"}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [0],
    \"thresholdComparator\": \">\",
    \"timeWindowSize\": 1,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": ${SLA_BREACH_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

# ── 7. Alert rule: Query Timeout ──────────────────────────────────────────────
echo "[${ID}] Creating alert rule: [Scenario 03] DB Slow Query - Query Timeout..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 03] DB Slow Query - Query Timeout\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"10s\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"terms\\\":{\\\"error_code\\\":[\\\"QUERY_TIMEOUT\\\",\\\"POOL_EXHAUSTED\\\"]}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [0],
    \"thresholdComparator\": \">\",
    \"timeWindowSize\": 1,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": ${QUERY_TIMEOUT_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

echo "[${ID}] Setup complete."
