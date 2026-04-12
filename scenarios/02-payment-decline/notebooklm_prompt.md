# NotebookLM Prompt — Payment Decline Spike

Upload these as sources before pasting the prompt below:
- `scenarios/02-payment-decline/README.md`
- `PLAN.md`

---

Paste into NotebookLM:

Create a 6–8 slide technical presentation about the "Payment Decline Spike" observability scenario from this structured logging simulator project.

Slides:

1. **The incident**: A Stripe payment gateway begins timing out during an active checkout window. Six consecutive payment declines hit across six different orders — five with `GATEWAY_TIMEOUT` (infrastructure failure) and one with `INSUFFICIENT_FUNDS` (normal business event). The system exhausts retries on the original order and the circuit breaker opens. Explain why plain-text logs make it impossible to distinguish a gateway infrastructure failure from a user-side decline at query time, without a parsing pipeline.

2. **Log sequence**: Show the actual field names and values emitted by the simulation in order:
   - `level=INFO msg="Payment initiated" user_id=USR-2011 order_id=ORD-8801 amount=149.99 gateway=stripe`
   - `level=ERROR msg="Payment declined" order_id=ORD-8801 amount=149.99 gateway=stripe error_code=GATEWAY_TIMEOUT` (and five more decline events)
   - `level=WARN msg="Retry limit reached" user_id=USR-2011 order_id=ORD-8801 gateway=stripe error_code=MAX_RETRIES_EXCEEDED`
   - `level=ERROR msg="Gateway circuit open" gateway=stripe error_code=CIRCUIT_BREAKER_OPEN`
   Explain what each field type (keyword vs float) enables in Elasticsearch — particularly why `amount` as a numeric field enables revenue-impact aggregation that is impossible with plain text.

3. **Kibana queries that surface the signal immediately**: Include these exact KQL queries with explanations of what each returns:
   - `error_code: "GATEWAY_TIMEOUT"` — all infrastructure failures, distinguished from user-side declines
   - `gateway: "stripe" AND level: "ERROR"` — Stripe-specific failures for gateway triage
   - `error_code: "CIRCUIT_BREAKER_OPEN" OR error_code: "MAX_RETRIES_EXCEEDED"` — escalation signals
   - `order_id: "ORD-8801"` — full lifecycle of one order from initiation through retry failure

4. **Structured vs plain text — same event, two queries**: Show the structured JSON log line for `ORD-8804` alongside its plain-text equivalent. Contrast the KQL query `error_code: "GATEWAY_TIMEOUT"` against `grep 'GATEWAY_TIMEOUT'`. Then show what breaks: splitting failure counts by gateway, summing revenue at risk across declined transactions, and alerting on circuit-breaker state — all require field extraction from plain text, all are trivial with structured fields.

5. **Alert rules**: Two rules run on this scenario. First: fires when `error_code: "GATEWAY_TIMEOUT"` count >= 3 in 5 minutes — this is the early-warning signal that a gateway is degrading before the circuit breaker opens. Second: fires when `error_code: "CIRCUIT_BREAKER_OPEN"` count > 0 — this is the severity-one trigger for immediate escalation. Explain why exact term queries on keyword fields survive message wording changes and localization, while regex-on-message-body alerts do not.

6. **Key lesson**: Two payments can fail for completely different reasons — gateway infrastructure failure and user-side decline — and produce log lines that are indistinguishable in plain text. Structured logging is not about making logs prettier. It is about whether the triage query `error_code: "GATEWAY_TIMEOUT"` takes two seconds or twenty minutes. The `error_code` field is the difference between an alert that fires correctly and a regex that silently breaks when a developer renames a log message.

7. **Recommendation** (optional): For teams adding payment observability, instrument four fields first: `gateway`, `error_code`, `order_id`, and `amount`. These four fields enable gateway failure rate by provider, revenue impact aggregation, per-order lifecycle tracing, and circuit-breaker alerting — the complete set of triage capabilities needed to respond to a gateway outage — with no additional parsing infrastructure.

Tone: technical and direct. Use the exact field names and KQL queries from the simulation. Assume the audience knows Elasticsearch and distributed systems but may not have used Kibana alerting for payments observability before.
