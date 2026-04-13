# Demo Guide — Structured vs Plain-Text Logging

End-to-end walkthrough for running each scenario, checking Kibana, and explaining the structured logging payoff to an audience.

---

## Prerequisites

- Docker Desktop running
- Go 1.22+
- Ports free: `8080` (simulator), `9200` (ES), `5601` (Kibana), `5044` (Logstash)

---

## Step 1 — Start ELK

```bash
make elk-up
```

Wait ~30 seconds for Elasticsearch to become healthy, then verify:

```bash
curl -s http://localhost:9200/_cluster/health | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"
# green or yellow = good
```

Kibana: http://localhost:5601

---

## Step 2 — Start the Simulator

```bash
make run
```

Open http://localhost:8080 — you'll see the scenario list.

---

## Step 3 — Run Scenario Setup (one-time per scenario)

Each scenario creates its ES index template, Kibana dashboard, and alert rules:

```bash
bash scenarios/01-auth-brute-force/setup.sh
bash scenarios/02-payment-decline/setup.sh
```

---

## Scenario 01 — Auth Brute Force

**What it shows:** An attacker hammers one account with wrong passwords until it locks.
**Teaching moment:** With plain text you can grep for "Login failed" but you cannot alert on `attempt_count >= 3` without parsing integers out of strings. With structured logs it's a one-line KQL rule.

### Run

In the UI at http://localhost:8080, click **Run** on **Auth Brute Force**.

Or from the terminal:

```bash
go run ./scenarios/01-auth-brute-force/ \
  --compress-time \
  --log-file=logs/sim-auth-brute-force.log
```

Expected output (6 lines):

```
{"level":"WARN","msg":"Login failed","scenario":"auth-brute-force","user_id":"USR-1042","ip_address":"10.0.1.55","attempt_count":1,"error_code":"INVALID_PASSWORD",...}
{"level":"WARN","msg":"Login failed",...,"attempt_count":2,...}
{"level":"WARN","msg":"Login failed",...,"attempt_count":3,...}
{"level":"WARN","msg":"Login failed",...,"attempt_count":4,...}
{"level":"WARN","msg":"Login failed",...,"attempt_count":5,...}
{"level":"ERROR","msg":"Account locked",...,"attempt_count":5,"error_code":"ACCOUNT_LOCKED",...}
```

### Kibana

Dashboard: **Sim: Auth Brute Force** → http://localhost:5601

Key Discover queries (data view: `sim-auth-brute-force`):

```
# All events
scenario: "auth-brute-force"

# Only the lockout event
error_code: "ACCOUNT_LOCKED"

# Attack threshold — 3+ failed attempts
attempt_count >= 3

# Full attack chain for one user
user_id: "USR-1042" AND error_code: "INVALID_PASSWORD"
```

### Alerts (already created by setup.sh)

| Rule | Fires when |
|------|-----------|
| Auth Brute Force - Account Locked | `error_code: "ACCOUNT_LOCKED"` > 0 in 5 min |
| Auth Brute Force - Repeated Failures | `error_code: "INVALID_PASSWORD"` >= 3 in 5 min |

### Plain text vs structured — show this side by side

| Question | Structured | Plain text |
|----------|-----------|------------|
| How many failures for USR-1042? | `user_id: "USR-1042"` → Kibana count | grep + awk + count |
| Alert when attempt_count >= 3 | One-line alert rule | Parse integer from string — fragile |
| Group failures by IP | `ip_address` term aggregation | Regex on log line |

---

## Scenario 02 — Payment Decline Spike

**What it shows:** A payment gateway starts timing out, six orders fail in a burst, retry limit is hit, circuit breaker opens.
**Teaching moment:** With structured logs you can instantly separate `GATEWAY_TIMEOUT` (infra emergency) from `INSUFFICIENT_FUNDS` (normal business event) — the same `error_code` field, two completely different responses. Plain text can't do that without brittle string matching.

### Run

In the UI at http://localhost:8080, click **Run** on **Payment Decline Spike**.

Or from the terminal:

```bash
go run ./scenarios/02-payment-decline/ \
  --compress-time \
  --log-file=logs/sim-payment-decline.log
```

Expected output (9 lines):

```
{"level":"INFO","msg":"Payment initiated","order_id":"ORD-8801","amount":149.99,"gateway":"stripe",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8801","gateway":"stripe","error_code":"GATEWAY_TIMEOUT",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8802","gateway":"stripe","error_code":"GATEWAY_TIMEOUT",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8803","gateway":"paypal","error_code":"INSUFFICIENT_FUNDS",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8804","gateway":"stripe","error_code":"GATEWAY_TIMEOUT",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8805","gateway":"stripe","error_code":"GATEWAY_TIMEOUT",...}
{"level":"ERROR","msg":"Payment declined","order_id":"ORD-8806","gateway":"paypal","error_code":"GATEWAY_TIMEOUT",...}
{"level":"WARN","msg":"Retry limit reached","order_id":"ORD-8801","error_code":"MAX_RETRIES_EXCEEDED",...}
{"level":"ERROR","msg":"Gateway circuit open","gateway":"stripe","error_code":"CIRCUIT_BREAKER_OPEN",...}
```

### Kibana

Dashboard: **Sim: Payment Decline** → http://localhost:5601

Key Discover queries (data view: `sim-payment-decline`):

```
# All declines
level: "ERROR" AND msg: "Payment declined"

# Infrastructure failures only (page on-call)
error_code: "GATEWAY_TIMEOUT"

# User-side failures only (not an incident)
error_code: "INSUFFICIENT_FUNDS"

# Stripe-only failures
gateway: "stripe" AND level: "ERROR"

# Circuit breaker + retry escalations
error_code: "CIRCUIT_BREAKER_OPEN" OR error_code: "MAX_RETRIES_EXCEEDED"

# Full lifecycle of one order
order_id: "ORD-8801"
```

### Alerts (already created by setup.sh)

| Rule | Fires when |
|------|-----------|
| Gateway Timeout Spike | `error_code: "GATEWAY_TIMEOUT"` >= 3 in 5 min |
| Circuit Breaker Open | `error_code: "CIRCUIT_BREAKER_OPEN"` > 0 in 5 min |

### Plain text vs structured — show this side by side

| Question | Structured | Plain text |
|----------|-----------|------------|
| Is this an infra failure or a user issue? | `error_code` field — exact filter | Parse message string — breaks on wording change |
| Which gateway is failing? | `gateway` term aggregation | Awk on log line |
| Alert on circuit breaker | `error_code: "CIRCUIT_BREAKER_OPEN"` > 0 | Regex on message body |
| Revenue at risk | Sum `amount` field in Kibana Lens | No native aggregation without parse pipeline |

---

## Teardown

```bash
# Delete Kibana objects + ES indexes for each scenario
bash scenarios/01-auth-brute-force/reset.sh
bash scenarios/02-payment-decline/reset.sh

# Stop ELK
make elk-down

# Wipe log files
make clean
```

---

## Quick Reference

| Command | What it does |
|---------|-------------|
| `make elk-up` | Start ES + Kibana + Logstash + Filebeat |
| `make run` | Start simulator UI on :8080 |
| `make logs` | Tail all scenario log files |
| `make elk-down` | Stop ELK stack |
| `make clean` | Delete logs/ |
| `bash scenarios/0N-*/setup.sh` | Create ES template + Kibana dashboard + alerts |
| `bash scenarios/0N-*/reset.sh` | Delete all Kibana objects + ES index for a scenario |
| `go run ./scenarios/0N-*/` | Run a scenario binary directly |
