# Kibana MCP Server

MCP (Model Context Protocol) server for Kibana dashboard and alert operations.

## Setup

1. Install dependencies:
```bash
cd .kiro/mcp-servers
npm install
```

2. Configure environment variables in `.env`:
```bash
ES_URL=http://localhost:9200
ES_USER=elastic
ES_PASSWORD=your_password
KIBANA_URL=http://localhost:5601
KIBANA_USER=elastic
KIBANA_PASSWORD=your_password
```

3. Add to Kiro CLI MCP configuration (`~/.kiro/config.json`):
```json
{
  "mcpServers": {
    "kibana": {
      "command": "node",
      "args": ["/path/to/project/.kiro/mcp-servers/kibana-server.js"],
      "env": {
        "ROOT_DIR": "/path/to/project"
      }
    }
  }
}
```

## Available Tools

### discover_fields
List available fields in an Elasticsearch index.

**Parameters:**
- `index_pattern` (optional): Index pattern, defaults to `*`

**Example:**
```
discover_fields({ index_pattern: "logs-*" })
```

### generate_dashboard
Generate dashboard configuration files.

**Parameters:**
- `title` (required): Dashboard title
- `index` (required): Index pattern
- `viz_type` (required): Visualization type (line/bar/pie/table)
- `field` (required): Field to visualize
- `time_range` (optional): Time range, defaults to `15m`

**Returns:** Dashboard ID for use with `create_dashboard`

**Example:**
```
generate_dashboard({
  title: "Error Count",
  index: "logs-*",
  viz_type: "line",
  field: "error",
  time_range: "1h"
})
```

### create_dashboard
Create dashboard in Kibana and return URL.

**Parameters:**
- `dash_id` (required): Dashboard ID from `generate_dashboard`

**Returns:** Kibana dashboard URL

**Example:**
```
create_dashboard({ dash_id: "dash-1234567890" })
```

### create_alert
Configure a metric alert.

**Parameters:**
- `name` (required): Alert name
- `metric` (required): Metric field to monitor
- `threshold` (required): Threshold value
- `operator` (optional): Comparison operator (gt/lt/gte/lte), defaults to `gt`
- `index` (required): Index pattern

**Example:**
```
create_alert({
  name: "High CPU Alert",
  metric: "cpu_usage",
  threshold: 80,
  operator: "gt",
  index: "metrics-*"
})
```

### check_alerts
Evaluate all enabled alerts and return triggered alerts.

**Example:**
```
check_alerts()
```

## Usage with kibana-agent

The `kibana-agent` is configured to use these MCP tools automatically. Simply interact with the agent using natural language:

```bash
kiro-cli chat --agent kibana-agent
```

Examples:
- "Show error count over time for logs-* index"
- "Create an alert when CPU usage exceeds 80%"
- "Check if any alerts are triggered"

## Data Storage

Dashboard configurations and alert definitions are stored in `.kiro/data/kibana-agent/`:
- `dash-*.json`: Dashboard configurations
- `viz-*.json`: Visualization configurations
- `alerts.json`: Alert definitions
- `alert-history.log`: Alert evaluation history
