# NotebookLM Prompt — System Observability with ELK

Upload these sources first: `PLAN.md`, `DEMO.md`, `context/system-observability-plan.md`, `scenarios/01-auth-brute-force/README.md`, `scenarios/02-payment-decline/README.md`

---

Paste into NotebookLM:

Create a 16–18 slide presentation: **"System Observability using ELK — From Logs to Insight"**. A developer shares what they learned building a hands-on ELK simulator with 5 incident scenarios.

Design: muted professional palette — slate blue (#1e293b), soft sky (#7dd3fc), cool gray (#94a3b8), white (#f8fafc). Green (#4ade80) for success, muted red (#f87171) for errors. Clean sans-serif, monospace for code on dark (#0f172a) backgrounds. One idea per slide, generous whitespace.

Slides:

1. **Title**: "System Observability using ELK". Subtitle: structured logs → dashboards → alerts. Show: `App → Filebeat → Logstash → Elasticsearch → Kibana`.

2. **Why Observability**: Systems generate thousands of log lines/min. At 2 AM during an incident, the question is whether you find the signal in 2 minutes or 2 hours. Three pillars: Logs, Metrics, Traces. This talk focuses on the logging pillar.

3. **Plain-Text Problem**: Show `ERROR 2026-04-10 10:32:05 Account locked for user USR-1042 from 10.0.1.55 after 5 attempts`. You can't: count failures per user, alert on attempt_count >= 3, group by IP, aggregate across services, or build dashboards — without a parsing pipeline. The signal is trapped in a string.

4. **Structured Logging**: Same event as JSON: `{"level":"ERROR","msg":"Account locked","user_id":"USR-1042","ip_address":"10.0.1.55","attempt_count":5,"error_code":"ACCOUNT_LOCKED"}`. Every field is typed and indexed. `attempt_count` is an integer for comparisons. `error_code` is a keyword for exact matching. This makes the signal queryable.

5. **ELK Architecture**: Diagram: `Go App (slog/JSON) → log file → Filebeat (ships) → Logstash (parses/routes) → Elasticsearch (indexes) → Kibana (visualizes/alerts)`. One sentence per component.

6. **The Simulator**: Go-based project with 5 incident scenarios as standalone binaries. Web UI, time compression (30-min incidents in 6 seconds), per-scenario Kibana dashboards and alerts. Stack: Go 1.22, ELK 8.12.0, Docker Compose.

7. **Scenario: Auth Brute Force**: USR-1042 gets 5 failed logins from IP 10.0.1.55 (INVALID_PASSWORD), then ACCOUNT_LOCKED. Fields: `user_id`, `ip_address`, `attempt_count` (integer), `error_code` (keyword).

8. **Querying Auth Attack**: KQL: `error_code: "ACCOUNT_LOCKED"` (all lockouts), `attempt_count >= 3` (early warning — impossible in plain text), `ip_address: "10.0.1.55"` (attacker activity). Compare: grep can't do integer threshold checks.

9. **Scenario: Payment Decline**: Stripe times out, 6 declines across 6 orders — 5× GATEWAY_TIMEOUT (infra failure) + 1× INSUFFICIENT_FUNDS (normal). Retry exhausted, circuit breaker opens. Fields: `gateway`, `error_code`, `order_id`, `amount` (float for revenue aggregation).

10. **Querying Payment Incident**: KQL: `error_code: "GATEWAY_TIMEOUT"` (infra failures only), `gateway: "stripe" AND level: "ERROR"` (per-gateway triage), `order_id: "ORD-8801"` (full order lifecycle). `amount` as numeric enables revenue-at-risk sum — impossible in plain text.

11. **More Scenarios** (brief): DB Slow Query — `duration_ms` degrades 12ms → 5000ms → pool exhaustion; enables p95 latency and SLA breach alerts. Cache Stampede — cache miss triggers `db_calls` spike 1 → 200; `hit` boolean + `db_calls` integer reveal the pattern instantly. API Degradation — `latency_ms` climbs, `status_code` shifts 200 → 504 → 503, circuit breaker opens; enables per-endpoint error rate dashboards.

12. **ELK Pipeline Config**: Filebeat watches each log file, tags with `log_type`. Logstash parses JSON, extracts `time` as `@timestamp`, promotes fields, routes to per-scenario ES index. Elasticsearch stores with proper mappings (keywords for exact match, integers for ranges, floats for aggregation).

13. **Kibana Dashboards**: 6 panels per scenario: incident timeline (area chart by level), error rate (gauge), level distribution (donut), scenario metric (line chart — attempt_count/duration_ms/latency_ms), categorical breakdown (bar — error_code/gateway), recent events (data table). Created programmatically via setup scripts.

14. **Alerting**: Two rules per scenario — early warning + critical. Auth: INVALID_PASSWORD >= 3 / ACCOUNT_LOCKED > 0. Payment: GATEWAY_TIMEOUT >= 3 / CIRCUIT_BREAKER_OPEN > 0. All use keyword term queries that survive message wording changes, unlike regex alerts.

15. **Structured vs Plain Text Comparison**: Table — count per user: field query vs grep+awk. Numeric threshold: one-line rule vs parse integer from string. Infra vs user errors: exact filter vs string match that breaks. Revenue aggregation: Kibana sum vs parse float. Latency percentiles: histogram vs impossible. Dashboard: drop fields into Lens vs not possible.

16. **Learning Path**: 1) Structured logging fundamentals 2) Log management & rotation 3) Filebeat shipping 4) Logstash processing 5) Elasticsearch queries 6) Kibana visualization 7) Alerting rules 8) Production debugging workflow: Alert → Metrics → Logs.

17. **Getting Started**: Instrument 4 fields per domain (auth: user_id, ip, attempt_count, error_code; payments: gateway, error_code, order_id, amount). Set up ELK with Docker Compose. Create one Discover query per incident type. Add two alerts per service. Build one 6-panel dashboard.

18. **Takeaways**: Structured logging is the foundation — every capability depends on typed, indexed fields. ELK turns logs into a queryable system — the pipeline is configuration, not code. Start with your highest-incident domain — 4 fields, 2 alerts, 1 dashboard. "The signal is already in your logs. Structured logging is how you make it findable."

Tone: technical, direct, approachable. Use exact field names and KQL from the simulator. One idea per slide, max 6 bullets. Works standalone or alongside a live demo.
