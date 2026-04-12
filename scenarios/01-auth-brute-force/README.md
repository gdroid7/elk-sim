# Scenario 01: Auth Brute Force

## What This Simulates

A single user account (`USR-1042`) receives five consecutive failed login attempts from the same IP address (`10.0.1.55`), each returning `INVALID_PASSWORD`. On the fifth failure the system escalates to `ACCOUNT_LOCKED`, ending the attack sequence. This mirrors real credential-stuffing attacks where an automated tool hammers a known username with a password list until the account locks.

## Why It Matters

With plain-text logs, detecting this pattern requires scanning free-form strings for partial matches like `"Login failed"` and manually counting occurrences per user. There is no reliable way to alert on `attempt_count >= 5` because attempt count lives inside the message text, not as a queryable field. Structured logging exposes `user_id`, `ip_address`, `attempt_count`, and `error_code` as discrete, indexed fields — making threshold alerts, per-user aggregations, and IP-based grouping trivially queryable in Kibana without log parsing.

## Log Fields

| Field | Type | Example | Meaning |
|-------|------|---------|---------|
| `time` | string (RFC3339) | `2024-01-15T10:32:01+05:30` | Log timestamp in IST (UTC+5:30) |
| `level` | string | `WARN`, `ERROR` | Go slog severity level |
| `msg` | string | `Login failed` | Human-readable event description |
| `scenario` | keyword | `auth-brute-force` | Scenario identifier, used for index routing |
| `user_id` | keyword | `USR-1042` | Targeted account identifier |
| `ip_address` | keyword | `10.0.1.55` | Source IP of the login attempt |
| `attempt_count` | integer | `1` – `5` | Cumulative failed attempts for this session |
| `error_code` | keyword | `INVALID_PASSWORD`, `ACCOUNT_LOCKED` | Machine-readable failure reason |

## Log Sequence

The scenario emits 6 log lines total:

1. Attempts 1–5: `level=WARN`, `msg="Login failed"`, `error_code=INVALID_PASSWORD`, `attempt_count` increments 1 → 5
2. Attempt 6: `level=ERROR`, `msg="Account locked"`, `error_code=ACCOUNT_LOCKED`, `attempt_count=5`

With `--compress-time`, all 6 events are spread across a synthetic 30-minute window so the Kibana timeline shows a meaningful escalation curve rather than a vertical spike.

## Running the Scenario

```bash
# Start ELK stack (first time only)
make docker-up
make setup-all

# Run the scenario (real-time, ~6 seconds)
make run
# then open http://localhost:8080 and click Run on Scenario 01

# Or run the binary directly with time compression
./bin/scenarios/01-auth-brute-force \
  --compress-time \
  --time-window=30m \
  --log-file=logs/sim-auth-brute-force.log
```

## Kibana

### 1. Dashboard

Open **[Scenario 01] Auth Brute Force** in Kibana Dashboards (`http://localhost:5601`). It shows:
- Total login failures over the time window (count metric)
- Failures broken down by `error_code` (bar chart)
- Per-user failure count (data table)
- Timeline of events by log level

### 2. Discover Queries

Open Discover, set the data view to `sim-auth-brute-force`, then try:

```
# All events for this scenario
scenario: "auth-brute-force"

# Only account lockout events
error_code: "ACCOUNT_LOCKED"

# High-frequency failures (attempt 3 or more)
attempt_count >= 3

# Full attack chain for one user
user_id: "USR-1042" AND error_code: "INVALID_PASSWORD"

# All failures from a specific IP
ip_address: "10.0.1.55"
```

### 3. Alerts

Two alert rules are created by `setup.sh`:

| Rule | Trigger | Condition |
|------|---------|-----------|
| `[Scenario 01] Auth Brute Force - Account Locked` | `error_code: "ACCOUNT_LOCKED"` | > 0 events in 5 min |
| `[Scenario 01] Auth Brute Force - Repeated Failures` | `error_code: "INVALID_PASSWORD"` | >= 3 events in 5 min |

Both fire to the server-log connector. In a production system these would page an on-call engineer or trigger an automated IP block.

## Structured vs Plain Text

| Capability | Structured Logging | Plain Text Logging |
|-----------|-------------------|-------------------|
| Count failures per user | `user_id: "USR-1042"` — instant aggregation | Grep + awk + count — fragile |
| Alert on attempt threshold | `attempt_count >= 3` in alert rule | Parse integer out of message string — unreliable |
| Group by source IP | `ip_address: "10.0.1.55"` — exact term query | Regex on log line — breaks on format changes |
| Distinguish lock vs failure | `error_code: "ACCOUNT_LOCKED"` term filter | String match on `"Account locked"` — case-sensitive, localizable |
| Correlate across services | Join on `user_id` field | Manual string extraction per service |
| Dashboard aggregation | Drop `error_code` into a Lens chart | Not possible without a parsing pipeline |

## Real-World Framing

This scenario maps directly to credential-stuffing attacks against SaaS login endpoints, where bot networks cycle through leaked username/password pairs and the only reliable early signal is the per-account failure rate — a number that only exists as a queryable value in structured logs.
