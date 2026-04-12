# Verbal Script — Scenario 01: Auth Brute Force

Approximate duration: 3 minutes

---

## Opening (30 seconds)

"What you're looking at is the ELK-based log simulator running locally. We have five scenarios that each simulate a real production incident. Today we're starting with the one that shows up in basically every security post-mortem — a brute-force attack on user login.

The setup is simple: one user account, one IP address, five failed password attempts, and then an account lockout. It takes about six seconds in real time. Let's run it."

---

## Run Scenario (30 seconds)

Click **Run** on Scenario 01 in the browser UI at `http://localhost:8080`.

"Watch the log stream on the right. You can see each event as it arrives — warning, warning, warning, five of them, and then that final error: Account locked. Each line is a JSON object. Notice the fields: `user_id`, `ip_address`, `attempt_count`, `error_code`. These aren't buried in a message string — they're discrete, indexed values.

Now let's go to Kibana and see what that actually buys us."

---

## Kibana (60 seconds)

Open Kibana at `http://localhost:5601`. Navigate to Dashboards and open **[Scenario 01] Auth Brute Force**.

"Here's the dashboard that was set up automatically by the scenario's setup script. Top left — total failure count. The bar chart on the right breaks down by `error_code`, so you can see exactly how many `INVALID_PASSWORD` events there were versus the single `ACCOUNT_LOCKED` event. The data table at the bottom shows failures per user.

Now let's go to Discover and run a few queries live."

Switch to Discover, select the `sim-auth-brute-force` data view.

Type in the KQL bar:

```
attempt_count >= 3
```

"This returns every event where the attempt count was three or more. That's your threshold for alerting. With plain text you'd have to extract that number from the message string and hope the format never changes. Here it's just a field comparison."

Clear and type:

```
error_code: "ACCOUNT_LOCKED"
```

"One query, one result, zero ambiguity. No regex. No grep. Just a term filter on an indexed keyword field."

---

## Comparison (45 seconds)

Split the screen or show side by side.

"Here's the comparison that matters. Same event, two logging styles.

Structured log line:
```json
{
  \"level\": \"ERROR\",
  \"msg\": \"Account locked\",
  \"user_id\": \"USR-1042\",
  \"ip_address\": \"10.0.1.55\",
  \"attempt_count\": 5,
  \"error_code\": \"ACCOUNT_LOCKED\"
}
```

Plain text equivalent:
```
ERROR 2024-01-15 10:32:05 Account locked for user USR-1042 from 10.0.1.55 after 5 attempts
```

To find all lockouts in plain text logs: `grep 'Account locked'`. That works. But to count lockouts per IP, or alert when a single IP locks more than three accounts in five minutes — you're writing a sed pipeline or standing up a custom log parser. In Kibana with structured logs, that alert is a two-minute configuration task."

---

## Alert Demo (30 seconds)

Navigate to Kibana Stack Management > Alerts, or Observability > Alerts.

"Two alert rules were created when we ran setup: one fires when any `ACCOUNT_LOCKED` event appears in the last five minutes. The other fires when there are three or more `INVALID_PASSWORD` events in five minutes — that's the early warning before the lockout.

Both use exact term queries on indexed keyword fields. The plain-text equivalent would be a regex on the message body, which breaks the moment someone changes the log message wording."

---

## Close (15 seconds)

"The takeaway: structured logging doesn't just make logs prettier — it makes the security signals that are already in your logs actually queryable at scale, without a parsing pipeline between the event and the alert. Next scenario is payment decline spikes."

---

## Speaker Notes

- Pre-setup: run `make docker-up && make setup-all` at least 2 minutes before the demo starts. Kibana takes 60–90 seconds to initialize after first boot.
- Visual emphasis: when the log stream appears in the browser, pause on it for 3–4 seconds. Audiences need time to register that these are JSON objects, not plain text lines.
- If Kibana is slow to load the dashboard, switch to Discover first — queries respond faster than dashboard renders.
- The comparison section lands hardest if you physically type the grep command (`grep 'Account locked' sim-auth-brute-force.log | wc -l`) versus the KQL query side by side. Consider opening a terminal alongside the browser.
- For time-compressed demos, run the binary with `--compress-time` before the session so data is already in Elasticsearch when you open Kibana. The dashboard will show a proper 30-minute timeline instead of a 6-second spike.
