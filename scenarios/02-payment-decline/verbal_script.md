# Verbal Script — Scenario 02: Payment Decline Spike

Approximate duration: 3 minutes

---

## Opening (30 seconds)

"We're still on the same simulator. This time the scenario is a payment gateway failure — specifically what happens when Stripe starts timing out during an active checkout window.

What makes this interesting from an observability standpoint is that there are two completely different reasons a payment can decline: infrastructure failure — the gateway is down — and a user-side decline like insufficient funds. Those look identical in plain-text logs. In structured logs they're two separate keyword values on the same field. Let's run it and see."

---

## Run Scenario (30 seconds)

Click **Run** on Scenario 02 in the browser UI at `http://localhost:8080`.

"Watch the stream. First event is INFO — payment initiated, order ORD-8801, 149 dollars, going to Stripe. Then errors start rolling in. Six payment declines across six different orders. Notice the `gateway` field alternates between `stripe` and `paypal`. Notice the `error_code` field: most are `GATEWAY_TIMEOUT` — that's an infrastructure problem — but one is `INSUFFICIENT_FUNDS`, which is a completely normal business event. Then at the end: `MAX_RETRIES_EXCEEDED` on the original order, and finally `CIRCUIT_BREAKER_OPEN` on Stripe.

Now let's see how Kibana surfaces that pattern."

---

## Kibana (60 seconds)

Open Kibana at `http://localhost:5601`. Navigate to Dashboards and open **[Scenario 02] Payment Decline Spike**.

"The dashboard was set up by the scenario's setup script. The top metric shows total failures. The bar chart on the right breaks down by `error_code` — so you can immediately see that the `GATEWAY_TIMEOUT` count is five, the `INSUFFICIENT_FUNDS` is one. That distinction matters: five timeouts on a payment gateway is an incident. One insufficient funds is not.

Let's go to Discover."

Switch to Discover, select the `sim-payment-decline` data view.

Type in the KQL bar:

```
error_code: "GATEWAY_TIMEOUT"
```

"Five results. Every Stripe and PayPal timeout in one query. No grep. No parsing."

Clear and type:

```
gateway: "stripe" AND level: "ERROR"
```

"Now we're scoped to Stripe failures only. This is how you triage: start broad with `error_code`, then narrow by `gateway` to confirm which provider is degraded."

Clear and type:

```
error_code: "CIRCUIT_BREAKER_OPEN" OR error_code: "MAX_RETRIES_EXCEEDED"
```

"These are your escalation signals. Circuit breaker open means the system has stopped trying Stripe entirely. In plain text you'd grep for the message string. If an engineer ever changes `'Gateway circuit open'` to `'Circuit breaker tripped'`, your alert silently breaks. With a keyword field, the value is controlled."

---

## Comparison (45 seconds)

Split the screen or show side by side.

"Same event, two logging styles.

Structured log line:
```json
{
  \"level\": \"ERROR\",
  \"msg\": \"Payment declined\",
  \"order_id\": \"ORD-8804\",
  \"amount\": 899.00,
  \"gateway\": \"stripe\",
  \"error_code\": \"GATEWAY_TIMEOUT\"
}
```

Plain text equivalent:
```
ERROR 2024-01-15 14:09:01 Payment declined for order ORD-8804 amount=899.00 via stripe: GATEWAY_TIMEOUT
```

With plain text: `grep 'GATEWAY_TIMEOUT'` gets you a count. But to split that count by gateway — stripe versus paypal — you're writing awk. To sum the `amount` field across all declined transactions — the revenue at risk — you're parsing floats out of a message string. In Kibana with structured logs, `amount` is a numeric field. You drop it into a sum aggregation and you have revenue impact in seconds."

---

## Alert Demo (30 seconds)

Navigate to Kibana Stack Management > Alerts, or Observability > Alerts.

"Two alert rules. The first fires when `GATEWAY_TIMEOUT` count reaches three in five minutes — that's the early warning that a gateway is degrading, before the circuit breaker opens. The second fires on any `CIRCUIT_BREAKER_OPEN` event — that's the severity-one trigger.

Both use exact term queries on indexed keyword fields. Compare that to a regex on `'Gateway circuit open'` — the structured version survives refactoring, localization, and copy changes. The regex version doesn't."

---

## Close (15 seconds)

"The takeaway: when a payment gateway fails, the difference between a two-minute triage and a twenty-minute one is whether `error_code` is a queryable field or a substring you're grepping for. Next scenario is slow database queries."

---

## Speaker Notes

- Pre-setup: run `make docker-up && make setup-all` at least 2 minutes before the demo starts. Kibana takes 60–90 seconds to initialize after first boot.
- For time-compressed demos, run `./bin/scenarios/02-payment-decline --compress-time --log-file=logs/sim-payment-decline.log` before the session. The dashboard will show a 30-minute escalation arc rather than an 8-second spike.
- Visual emphasis: when the log stream appears, pause at the `CIRCUIT_BREAKER_OPEN` line. It's the most visually distinct moment — the only line without an `order_id`. Let the audience notice that before you move on.
- The `amount` field is the strongest structured-vs-plain-text comparison for a payments audience. Emphasize that summing revenue at risk is a Lens metric in Kibana and a sed pipeline in plain text.
- If Kibana is slow to render the dashboard, jump directly to Discover — KQL queries respond faster and the comparison section plays better in Discover anyway.
- The `INSUFFICIENT_FUNDS` vs `GATEWAY_TIMEOUT` distinction is the core concept for this scenario. Return to it in the comparison section even if the audience seems to have grasped it early.
