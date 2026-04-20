#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

ALERTS_FILE=".kiro/data/kibana-agent/alerts.json"
HISTORY_FILE=".kiro/data/kibana-agent/alert-history.log"

[ ! -f "$ALERTS_FILE" ] && echo "No alerts configured" && exit 0
[ -z "$ES_URL" ] && echo "Error: ES_URL not set" && exit 1
[ -z "$SLACK_WEBHOOK_URL" ] && echo "Error: SLACK_WEBHOOK_URL not set" && exit 1

ALERTS=$(jq -c '.[] | select(.enabled == true)' "$ALERTS_FILE")

[ -z "$ALERTS" ] && echo "No enabled alerts" && exit 0

echo "$ALERTS" | while IFS= read -r alert; do
  ID=$(echo "$alert" | jq -r '.id')
  NAME=$(echo "$alert" | jq -r '.name')
  METRIC=$(echo "$alert" | jq -r '.metric')
  THRESHOLD=$(echo "$alert" | jq -r '.threshold')
  OPERATOR=$(echo "$alert" | jq -r '.operator')
  INDEX=$(echo "$alert" | jq -r '.index')

  QUERY="{\"query\":{\"match_all\":{}},\"aggs\":{\"metric_value\":{\"sum\":{\"field\":\"$METRIC\"}}}}"
  
  RESULT=$(curl -s -u "$ES_USER:$ES_PASSWORD" \
    "$ES_URL/$INDEX/_search?size=0" \
    -H "Content-Type: application/json" \
    -d "$QUERY")

  VALUE=$(echo "$RESULT" | jq -r '.aggregations.metric_value.value // 0')

  TRIGGERED=false
  case "$OPERATOR" in
    gt) [ "$(echo "$VALUE > $THRESHOLD" | bc -l)" -eq 1 ] && TRIGGERED=true ;;
    lt) [ "$(echo "$VALUE < $THRESHOLD" | bc -l)" -eq 1 ] && TRIGGERED=true ;;
    gte) [ "$(echo "$VALUE >= $THRESHOLD" | bc -l)" -eq 1 ] && TRIGGERED=true ;;
    lte) [ "$(echo "$VALUE <= $THRESHOLD" | bc -l)" -eq 1 ] && TRIGGERED=true ;;
  esac

  if [ "$TRIGGERED" = true ]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    MESSAGE="🚨 Alert: $NAME\nMetric: $METRIC = $VALUE\nThreshold: $OPERATOR $THRESHOLD\nTime: $TIMESTAMP"
    
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"$MESSAGE\"}" > /dev/null

    echo "[$TIMESTAMP] Alert triggered: $NAME ($ID) - $METRIC=$VALUE $OPERATOR $THRESHOLD" >> "$HISTORY_FILE"
    echo "Alert triggered: $NAME"
  fi
done
