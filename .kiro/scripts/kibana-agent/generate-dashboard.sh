#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

TITLE="$1"
INDEX="$2"
VIZ_TYPE="$3"
FIELD="$4"
TIME_RANGE="${5:-15m}"

[ -z "$TITLE" ] || [ -z "$INDEX" ] || [ -z "$VIZ_TYPE" ] || [ -z "$FIELD" ] && \
  echo "Usage: $0 <title> <index> <viz-type> <field> [time-range]" && exit 1

VIZ_ID="viz-$(date +%s)"
DASH_ID="dash-$(date +%s)"

case "$VIZ_TYPE" in
  line|bar)
    AGG_TYPE="date_histogram"
    ;;
  pie)
    AGG_TYPE="terms"
    ;;
  table)
    AGG_TYPE="terms"
    ;;
  *)
    echo "Error: Unsupported viz type. Use: line, bar, pie, table"
    exit 1
    ;;
esac

cat > ".kiro/data/kibana-agent/$DASH_ID.json" <<EOF
{
  "attributes": {
    "title": "$TITLE",
    "timeRestore": true,
    "timeFrom": "now-$TIME_RANGE",
    "timeTo": "now",
    "panelsJSON": "[{\"panelIndex\":\"1\",\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15},\"version\":\"7.0.0\",\"panelRefName\":\"panel_0\"}]",
    "optionsJSON": "{}",
    "version": 1,
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"
    }
  },
  "references": [{
    "name": "panel_0",
    "type": "visualization",
    "id": "$VIZ_ID"
  }]
}
EOF

cat > ".kiro/data/kibana-agent/$VIZ_ID.json" <<EOF
{
  "attributes": {
    "title": "$TITLE - Visualization",
    "visState": "{\"type\":\"$VIZ_TYPE\",\"params\":{},\"aggs\":[{\"id\":\"1\",\"type\":\"count\",\"schema\":\"metric\"},{\"id\":\"2\",\"type\":\"$AGG_TYPE\",\"schema\":\"segment\",\"params\":{\"field\":\"$FIELD\",\"size\":10,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
    "uiStateJSON": "{}",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"index\":\"$INDEX\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
    }
  }
}
EOF

echo "$DASH_ID"
