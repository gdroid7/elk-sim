# NotebookLM Prompt — Auth Brute Force

Upload these as sources before pasting the prompt below:
- `scenarios/01-auth-brute-force/README.md`
- `PLAN.md`

---

Paste into NotebookLM:

Create a 6–8 slide technical presentation about the "Auth Brute Force" observability scenario from this structured logging simulator project.

Slides:

1. **The incident**: A single user account (`USR-1042`) receives five consecutive failed login attempts from IP `10.0.1.55`, each returning `INVALID_PASSWORD`, followed by an `ACCOUNT_LOCKED` escalation. Explain why plain-text logs make this pattern hard to detect at scale — specifically, why counting attempts per user requires string parsing when logs are unstructured.

2. **Log sequence**: Show the actual field names and values emitted by the simulation in order: `level=WARN msg="Login failed" user_id=USR-1042 ip_address=10.0.1.55 attempt_count=1 error_code=INVALID_PASSWORD` through attempt 5, then `level=ERROR msg="Account locked" attempt_count=5 error_code=ACCOUNT_LOCKED`. Explain what each field type (keyword vs integer) enables in Elasticsearch.

3. **Kibana queries that surface the signal immediately**: Include these exact KQL queries with explanations of what each returns:
   - `error_code: "ACCOUNT_LOCKED"` — all lockout events, zero parsing
   - `attempt_count >= 3` — early warning threshold
   - `user_id: "USR-1042" AND error_code: "INVALID_PASSWORD"` — full attack chain for one account
   - `ip_address: "10.0.1.55"` — all activity from attacker IP

4. **Structured vs plain text — same event, two queries**: Show the structured JSON log line alongside its plain-text equivalent. Contrast the KQL query `error_code: "ACCOUNT_LOCKED"` against the grep equivalent `grep 'Account locked'`. Then show what breaks: counting per-IP lockouts, alerting on attempt thresholds, and correlating across services — all require field extraction from plain text, all are trivial with structured fields.

5. **Alert rules**: Two rules run on this scenario. First: fires when `error_code: "ACCOUNT_LOCKED"` count > 0 in 5 minutes — this is the lockout detection alert. Second: fires when `error_code: "INVALID_PASSWORD"` count >= 3 in 5 minutes — this is the brute-force early warning. Explain why exact term queries on keyword fields are more reliable than regex on message bodies (format changes, localization, case sensitivity).

6. **Key lesson**: The security signal — that one IP is hammering one account — already exists in the logs. Structured logging determines whether that signal is a queryable field or a string fragment you have to parse. The difference is whether your alerting is a two-minute Kibana configuration or a bespoke log-parsing pipeline that breaks on every message format change.

7. **Recommendation** (optional): For teams migrating from plain-text to structured logging, start with authentication events. `user_id`, `ip_address`, `attempt_count`, and `error_code` are the four fields that enable the most security use cases with the least instrumentation effort.

Tone: technical and direct. Use the exact field names and KQL queries from the simulation. Assume the audience knows Elasticsearch and distributed systems but may not have used Kibana alerting before.
