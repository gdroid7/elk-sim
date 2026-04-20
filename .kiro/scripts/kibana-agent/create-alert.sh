#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

NAME="$1"
METRIC="$2"
THRESHOLD="$3"
OPERATOR="${4:-gt}"
INDEX="$5"

[ -z "$NAME" ] || [ -z "$METRIC" ] || [ -z "$THRESHOLD" ] || [ -z "$INDEX" ] && \
  echo "Usage: $0 <name> <metric> <threshold> [operator] <index>" && exit 1

ALERTS_FILE=".kiro/data/kibana-agent/alerts.json"

[ ! -f "$ALERTS_FILE" ] && echo "[]" > "$ALERTS_FILE"

ALERT_ID="alert-$(date +%s)"

jq --arg id "$ALERT_ID" \
   --arg name "$NAME" \
   --arg metric "$METRIC" \
   --arg threshold "$THRESHOLD" \
   --arg operator "$OPERATOR" \
   --arg index "$INDEX" \
   '. += [{
     "id": $id,
     "name": $name,
     "metric": $metric,
     "threshold": ($threshold | tonumber),
     "operator": $operator,
     "index": $index,
     "enabled": true
   }]' "$ALERTS_FILE" > "$ALERTS_FILE.tmp" && mv "$ALERTS_FILE.tmp" "$ALERTS_FILE"

echo "Alert configured: $NAME (ID: $ALERT_ID)"
echo "Metric: $METRIC $OPERATOR $THRESHOLD on index $INDEX"
