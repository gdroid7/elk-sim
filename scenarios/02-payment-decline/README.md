# Scenario 02: Payment Decline Spike

## What This Simulates

An e-commerce platform processes orders normally until a Stripe gateway begins timing out. Six consecutive payment declines follow in rapid succession across multiple orders — three through Stripe with `GATEWAY_TIMEOUT`, one through PayPal with `INSUFFICIENT_FUNDS`, then two more Stripe timeouts — before the system hits its retry limit on the original order and the circuit breaker opens. This mirrors real gateway outages during peak traffic periods where a single upstream failure cascades into a visible revenue impact event.

## Why It Matters

With plain-text logs, identifying that most declines share a common `gateway` and `error_code` requires grep pipelines and manual counting. There is no way to distinguish a user's `INSUFFICIENT_FUNDS` (normal business event) from a `GATEWAY_TIMEOUT` (infrastructure emergency) without parsing the message string. Structured logging exposes `gateway`, `error_code`, `order_id`, and `amount` as discrete, indexed fields — enabling instant aggregation by failure type, per-gateway error rates, and circuit-breaker alerts without a custom parsing pipeline.

## Log Fields

| Field | Type | Example | Meaning |
|-------|------|---------|---------|
| `time` | string (RFC3339) | `2024-01-15T14:05:01+05:30` | Log timestamp in IST (UTC+5:30) |
| `level` | string | `INFO`, `WARN`, `ERROR` | Go slog severity level |
| `msg` | string | `Payment declined` | Human-readable event description |
| `scenario` | keyword | `payment-decline` | Scenario identifier, used for index routing |
| `order_id` | keyword | `ORD-8801` | Unique order being processed |
| `amount` | float | `149.99` | Transaction amount in USD |
| `gateway` | keyword | `stripe`, `paypal` | Payment gateway that processed the request |
| `error_code` | keyword | `GATEWAY_TIMEOUT`, `INSUFFICIENT_FUNDS`, `MAX_RETRIES_EXCEEDED`, `CIRCUIT_BREAKER_OPEN` | Machine-readable failure reason |
| `user_id` | keyword | `USR-2011` | Customer account (present on initiation and retry events) |

## Log Sequence

The scenario emits 9 log lines total:

1. Line 1: `level=INFO`, `msg="Payment initiated"`, `user_id=USR-2011`, `order_id=ORD-8801`, `amount=149.99`, `gateway=stripe` — normal transaction start
2. Lines 2–7: `level=ERROR`, `msg="Payment declined"` — six consecutive declines across orders ORD-8801 through ORD-8806; four via Stripe with `GATEWAY_TIMEOUT`, one via PayPal with `INSUFFICIENT_FUNDS`, one via PayPal with `GATEWAY_TIMEOUT`
3. Line 8: `level=WARN`, `msg="Retry limit reached"`, `error_code=MAX_RETRIES_EXCEEDED` — original order ORD-8801 exhausts retries
4. Line 9: `level=ERROR`, `msg="Gateway circuit open"`, `gateway=stripe`, `error_code=CIRCUIT_BREAKER_OPEN` — circuit breaker trips, blocking further Stripe requests

With `--compress-time`, all 9 events are spread across a synthetic 30-minute window so the Kibana timeline shows a meaningful escalation curve from normal operation through full circuit-breaker open.

## Running the Scenario

```bash
# Start ELK stack (first time only)
make docker-up
make setup-all

# Run the scenario (real-time, ~8 seconds)
make run
# then open http://localhost:8080 and click Run on Scenario 02

# Or run the binary directly with time compression
./bin/scenarios/02-payment-decline \
  --compress-time \
  --time-window=30m \
  --log-file=logs/sim-payment-decline.log
```

## Kibana

### 1. Dashboard

Open **[Scenario 02] Payment Decline Spike** in Kibana Dashboards (`http://localhost:5601`). It shows:
- Total payment failures over the time window (count metric)
- Failures broken down by `error_code` (bar chart distinguishing gateway failures from user-side declines)
- Failures broken down by `gateway` (pie or bar chart)
- Timeline of events by log level (INFO → ERROR escalation visible)

### 2. Discover Queries

Open Discover, set the data view to `sim-payment-decline`, then try:

```
# All events for this scenario
scenario: "payment-decline"

# All payment declines (any gateway, any error)
level: "ERROR" AND msg: "Payment declined"

# Only gateway timeout failures (infrastructure issue)
error_code: "GATEWAY_TIMEOUT"

# Stripe-specific failures only
gateway: "stripe" AND level: "ERROR"

# Distinguish user-side from infrastructure failures
error_code: "INSUFFICIENT_FUNDS"

# Circuit breaker and retry escalations
error_code: "CIRCUIT_BREAKER_OPEN" OR error_code: "MAX_RETRIES_EXCEEDED"

# Full lifecycle of one order
order_id: "ORD-8801"
```

### 3. Alerts

Two alert rules are created by `setup.sh`:

| Rule | Trigger | Condition |
|------|---------|-----------|
| `[Scenario 02] Payment Decline - Gateway Timeout` | `error_code: "GATEWAY_TIMEOUT"` | >= 3 events in 5 min |
| `[Scenario 02] Payment Decline - Circuit Breaker Open` | `error_code: "CIRCUIT_BREAKER_OPEN"` | > 0 events in 5 min |

Both fire to the server-log connector. In production, the circuit-breaker alert would page on-call immediately and trigger automated failover to a backup gateway.

## Structured vs Plain Text

| Capability | Structured Logging | Plain Text Logging |
|-----------|-------------------|-------------------|
| Separate gateway errors from user declines | `error_code: "GATEWAY_TIMEOUT"` vs `error_code: "INSUFFICIENT_FUNDS"` — exact term filter | Grep for message substrings, manually categorize — fragile |
| Count failures per gateway | `gateway: "stripe"` — instant aggregation in Kibana Lens | Awk pipeline on log lines — breaks on format changes |
| Alert on circuit breaker trip | `error_code: "CIRCUIT_BREAKER_OPEN"` > 0 in alert rule | Regex on message body — breaks if message wording changes |
| Track total revenue at risk | Aggregate `amount` field — Kibana sum metric | Parse float from message string — no native aggregation |
| Trace one order's full lifecycle | `order_id: "ORD-8801"` — exact term, instant | Grep for order ID in free-form string — depends on consistent formatting |
| Dashboard aggregation by error type | Drop `error_code` into Lens, split by `gateway` | Requires a parsing pipeline before any aggregation |

## Real-World Framing

This scenario maps directly to payment gateway outages during peak traffic events like Black Friday, where a single provider's timeout cascades into thousands of failed checkouts and the only way to distinguish a gateway infrastructure failure from a spike in user-side declines is the `error_code` field — a value that only exists as a queryable signal in structured logs.
