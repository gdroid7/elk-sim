#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

DASH_ID="$1"

[ -z "$DASH_ID" ] && echo "Usage: $0 <dashboard-id>" && exit 1
[ -z "$KIBANA_URL" ] && echo "Error: KIBANA_URL not set" && exit 1

DASH_FILE=".kiro/data/kibana-agent/$DASH_ID.json"
VIZ_FILE=".kiro/data/kibana-agent/viz-${DASH_ID#dash-}.json"

[ ! -f "$DASH_FILE" ] && echo "Error: Dashboard file not found: $DASH_FILE" && exit 1
[ ! -f "$VIZ_FILE" ] && echo "Error: Visualization file not found: $VIZ_FILE" && exit 1

VIZ_ID="viz-${DASH_ID#dash-}"

VIZ_RESP=$(curl -s -X POST "$KIBANA_URL/api/saved_objects/visualization/$VIZ_ID" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -d @"$VIZ_FILE")

if echo "$VIZ_RESP" | grep -q "error"; then
  echo "Error creating visualization: $VIZ_RESP"
  exit 1
fi

DASH_RESP=$(curl -s -X POST "$KIBANA_URL/api/saved_objects/dashboard/$DASH_ID" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -d @"$DASH_FILE")

if echo "$DASH_RESP" | grep -q "error"; then
  echo "Error creating dashboard: $DASH_RESP"
  exit 1
fi

echo "$KIBANA_URL/app/dashboards#/view/$DASH_ID"
