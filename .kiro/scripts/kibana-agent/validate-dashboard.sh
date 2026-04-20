#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

DASH_ID="$1"

[ -z "$DASH_ID" ] && echo "Usage: $0 <dashboard-id>" && exit 1
[ -z "$KIBANA_URL" ] && echo "Error: KIBANA_URL not set" && exit 1

DASH_FILE=".kiro/data/kibana-agent/$DASH_ID.json"
[ ! -f "$DASH_FILE" ] && echo "Error: Dashboard file not found" && exit 1

INDEX=$(jq -r '.references[0].id' "$DASH_FILE" | xargs -I {} cat ".kiro/data/kibana-agent/{}.json" | jq -r '.attributes.kibanaSavedObjectMeta.searchSourceJSON' | jq -r '.index')

[ -z "$INDEX" ] && echo "Error: Could not extract index from dashboard" && exit 1

COUNT=$(curl -s -u "$ES_USER:$ES_PASSWORD" "$ES_URL/$INDEX/_count" | jq -r '.count // 0')

if [ "$COUNT" -eq 0 ]; then
  echo "⚠️  Warning: Index '$INDEX' has no documents"
  exit 1
fi

echo "✓ Dashboard validated: $COUNT documents in index '$INDEX'"
