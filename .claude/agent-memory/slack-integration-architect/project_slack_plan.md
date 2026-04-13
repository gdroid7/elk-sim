---
name: Slack Alert Integration Plan
description: Planned Slack alert integration for go-elk-test project — Option C (Kibana connector) chosen, with Option B Go layer as secondary
type: project
---

Option C (Kibana Slack connector wired to existing alert rules) is the recommended approach for go-elk-test. All 5 scenarios already have Kibana alert rules created by their setup.sh scripts using .es-query rule type. Adding a Slack connector requires only a curl call per setup.sh and one connector creation step — no Go code changes, no Logstash changes.

**Why:** This is a local demo tool, not production. Logstash HTTP output (Option A) runs inside Docker with no env var injection path and cannot reach the host Slack webhook without network bridging config. The Go server layer (Option B) adds a polling goroutine and ES client logic that conflicts with the stdlib-only constraint.

**How to apply:** When implementing, add a `create_slack_connector` step to each `scenarios/0N-name/setup.sh` and update each alert rule's `actions` array to reference the connector. Dedup is handled by Kibana's `notify_when: onThrottleInterval` with a 10-minute throttle.

**License requirement — CRITICAL:** `.webhook`, `.slack`, and `.slack_api` connector types are ALL disabled on ELK Basic license. Must activate 30-day trial first:
```bash
curl -X POST "http://localhost:9200/_license/start_trial?acknowledge=true"
```
Trial activation propagates to Kibana within ~3 seconds. scenario 01 setup.sh handles this gracefully — if `SLACK_INCOMING_WEBHOOK_URL` is unset OR connector creation returns a non-id response, it falls back to server-log-only without failing.

**Implemented for scenario 01:** Connector ID `8a5db4d0-6291-4c72-8e06-39d93d4cc87e` (live on current docker stack). Both rules `f5af65c9` and `bd29dbae` now have 2 actions each + `onThrottleInterval/10m`. End-to-end verified — Account Locked rule fired and sent Slack message (active:1, new:1 confirmed at 2026-04-13T16:47:43).
