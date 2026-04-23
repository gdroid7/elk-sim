# Kibana Agent Runbook

Specialized agent for creating Kibana dashboards and Slack alerts from natural language.

## Usage

```bash
kiro chat --agent kibana-agent
```

## Capabilities

- Create Kibana dashboards from natural language
- Configure Slack metric alerts
- Discover available fields in indices
- Generate visualization configs

## Workflow

### Creating Dashboards

1. User describes what they want to visualize
2. Agent asks for:
   - Index pattern (e.g., `logs-*`, `metrics-*`)
   - Field to visualize
   - Visualization type (line/bar/pie/table)
   - Time range (default: 15m)
3. Agent generates and creates dashboard, returns URL

**Example:**
```
User: Show error count over time
Agent: What index pattern? (e.g., logs-*)
User: logs-app-*
Agent: [Creates line chart, returns Kibana URL]
```

### Creating Alerts

1. User describes alert condition
2. Agent asks for:
   - Index pattern
   - Metric field
   - Threshold value
   - Operator (gt/lt/gte/lte)
3. Agent creates alert rule

**Example:**
```
User: Alert when CPU > 80%
Agent: What index pattern?
User: metrics-system-*
Agent: [Creates alert with gt operator at 80]
```

## MCP Tools

The agent uses these MCP tools:

- `discover_fields` - List available fields in an index
- `generate_dashboard` - Generate dashboard config (returns dash-ID)
- `create_dashboard` - Create in Kibana, return URL
- `create_alert` - Configure metric alert
- `check_alerts` - Evaluate alerts and report triggered ones

## Tips

- Agent asks only essential questions
- Default time range is 15 minutes
- Provide index patterns with wildcards when needed
- Use standard operators: gt (>), lt (<), gte (≥), lte (≤)

## Requirements

- Running Kibana instance (default: http://localhost:5601)
- MCP server configured for Kibana operations
- Valid index patterns in Elasticsearch
