#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

echo "Validating Kibana Agent Configuration..."
echo

ERRORS=0

# Check environment variables
if [ -z "$ES_URL" ]; then
  echo "❌ ES_URL not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ ES_URL: $ES_URL"
fi

if [ -z "$ES_USER" ]; then
  echo "❌ ES_USER not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ ES_USER: $ES_USER"
fi

if [ -z "$ES_PASSWORD" ]; then
  echo "❌ ES_PASSWORD not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ ES_PASSWORD: [set]"
fi

if [ -z "$KIBANA_URL" ]; then
  echo "❌ KIBANA_URL not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ KIBANA_URL: $KIBANA_URL"
fi

if [ -z "$KIBANA_USER" ]; then
  echo "❌ KIBANA_USER not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ KIBANA_USER: $KIBANA_USER"
fi

if [ -z "$KIBANA_PASSWORD" ]; then
  echo "❌ KIBANA_PASSWORD not set"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ KIBANA_PASSWORD: [set]"
fi

if [ -z "$SLACK_WEBHOOK_URL" ]; then
  echo "⚠️  SLACK_WEBHOOK_URL not set (required for alerts)"
else
  echo "✓ SLACK_WEBHOOK_URL: [set]"
fi

echo

# Check dependencies
command -v curl >/dev/null 2>&1 || { echo "❌ curl not installed"; ERRORS=$((ERRORS + 1)); }
command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed"; ERRORS=$((ERRORS + 1)); }

echo

if [ $ERRORS -eq 0 ]; then
  echo "✅ Configuration valid"
  exit 0
else
  echo "❌ Found $ERRORS error(s)"
  exit 1
fi
