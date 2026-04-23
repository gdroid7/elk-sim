#!/usr/bin/env node

const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { CallToolRequestSchema, ListToolsRequestSchema } = require('@modelcontextprotocol/sdk/types.js');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

const execAsync = promisify(exec);

const ROOT_DIR = process.env.ROOT_DIR || process.cwd();
const DATA_DIR = path.join(ROOT_DIR, '.kiro/data/kibana-agent');

const ES_URL = process.env.ES_URL;
const ES_USER = process.env.ES_USER;
const ES_PASSWORD = process.env.ES_PASSWORD;
const KIBANA_URL = process.env.KIBANA_URL;
const KIBANA_USER = process.env.KIBANA_USER;
const KIBANA_PASSWORD = process.env.KIBANA_PASSWORD;

async function discoverFields(indexPattern = '*') {
  const url = `${ES_URL}/${indexPattern}/_mapping`;
  const auth = Buffer.from(`${ES_USER}:${ES_PASSWORD}`).toString('base64');
  
  const { stdout } = await execAsync(
    `curl -s -H "Authorization: Basic ${auth}" "${url}" | jq -r 'to_entries[] | .value.mappings.properties // {} | to_entries[] | "- \\(.key) (\\(.value.type // \\"object\\"))"' | sort -u`
  );
  
  return stdout.trim();
}

async function generateDashboard(title, index, vizType, field, timeRange = '15m') {
  const dashId = `dash-${Date.now()}`;
  const vizId = `viz-${Date.now()}`;
  
  const vizConfig = {
    attributes: {
      title: `${title} Visualization`,
      visState: JSON.stringify({
        type: vizType,
        params: { field },
        aggs: [{ type: 'count', schema: 'metric' }]
      }),
      kibanaSavedObjectMeta: {
        searchSourceJSON: JSON.stringify({ index, query: '*', filter: [] })
      }
    }
  };
  
  const dashConfig = {
    attributes: {
      title,
      panelsJSON: JSON.stringify([{ panelIndex: '1', gridData: { x: 0, y: 0, w: 12, h: 8 }, id: vizId }]),
      timeRestore: true,
      timeFrom: `now-${timeRange}`,
      timeTo: 'now'
    }
  };
  
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.writeFile(path.join(DATA_DIR, `${vizId}.json`), JSON.stringify(vizConfig, null, 2));
  await fs.writeFile(path.join(DATA_DIR, `${dashId}.json`), JSON.stringify(dashConfig, null, 2));
  
  return dashId;
}

async function createDashboard(dashId) {
  const vizId = `viz-${dashId.replace('dash-', '')}`;
  const vizFile = path.join(DATA_DIR, `${vizId}.json`);
  const dashFile = path.join(DATA_DIR, `${dashId}.json`);
  
  const auth = Buffer.from(`${KIBANA_USER}:${KIBANA_PASSWORD}`).toString('base64');
  
  await execAsync(
    `curl -s -X POST "${KIBANA_URL}/api/saved_objects/visualization/${vizId}" -H "kbn-xsrf: true" -H "Content-Type: application/json" -H "Authorization: Basic ${auth}" -d @"${vizFile}"`
  );
  
  await execAsync(
    `curl -s -X POST "${KIBANA_URL}/api/saved_objects/dashboard/${dashId}" -H "kbn-xsrf: true" -H "Content-Type: application/json" -H "Authorization: Basic ${auth}" -d @"${dashFile}"`
  );
  
  return `${KIBANA_URL}/app/dashboards#/view/${dashId}`;
}

async function createAlert(name, metric, threshold, operator = 'gt', index) {
  const alertsFile = path.join(DATA_DIR, 'alerts.json');
  
  let alerts = [];
  try {
    const data = await fs.readFile(alertsFile, 'utf8');
    alerts = JSON.parse(data);
  } catch (e) {
    await fs.mkdir(DATA_DIR, { recursive: true });
  }
  
  const alertId = `alert-${Date.now()}`;
  alerts.push({
    id: alertId,
    name,
    metric,
    threshold: parseFloat(threshold),
    operator,
    index,
    enabled: true
  });
  
  await fs.writeFile(alertsFile, JSON.stringify(alerts, null, 2));
  
  return `Alert configured: ${name} (ID: ${alertId})\nMetric: ${metric} ${operator} ${threshold} on index ${index}`;
}

async function checkAlerts() {
  const alertsFile = path.join(DATA_DIR, 'alerts.json');
  
  try {
    const data = await fs.readFile(alertsFile, 'utf8');
    const alerts = JSON.parse(data);
    
    const results = [];
    for (const alert of alerts.filter(a => a.enabled)) {
      const auth = Buffer.from(`${ES_USER}:${ES_PASSWORD}`).toString('base64');
      const query = {
        size: 0,
        aggs: {
          metric_value: {
            avg: { field: alert.metric }
          }
        }
      };
      
      const { stdout } = await execAsync(
        `curl -s -H "Authorization: Basic ${auth}" -H "Content-Type: application/json" "${ES_URL}/${alert.index}/_search" -d '${JSON.stringify(query)}'`
      );
      
      const response = JSON.parse(stdout);
      const value = response.aggregations?.metric_value?.value || 0;
      
      let triggered = false;
      switch (alert.operator) {
        case 'gt': triggered = value > alert.threshold; break;
        case 'lt': triggered = value < alert.threshold; break;
        case 'gte': triggered = value >= alert.threshold; break;
        case 'lte': triggered = value <= alert.threshold; break;
      }
      
      if (triggered) {
        results.push(`🚨 ALERT: ${alert.name} - ${alert.metric}=${value} ${alert.operator} ${alert.threshold}`);
      }
    }
    
    return results.length > 0 ? results.join('\n') : 'No alerts triggered';
  } catch (e) {
    return 'No alerts configured';
  }
}

const server = new Server(
  { name: 'kibana-server', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'discover_fields',
      description: 'List available fields in an Elasticsearch index',
      inputSchema: {
        type: 'object',
        properties: {
          index_pattern: { type: 'string', description: 'Index pattern (default: *)' }
        }
      }
    },
    {
      name: 'generate_dashboard',
      description: 'Generate dashboard configuration files',
      inputSchema: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Dashboard title' },
          index: { type: 'string', description: 'Index pattern' },
          viz_type: { type: 'string', description: 'Visualization type (line/bar/pie/table)' },
          field: { type: 'string', description: 'Field to visualize' },
          time_range: { type: 'string', description: 'Time range (default: 15m)' }
        },
        required: ['title', 'index', 'viz_type', 'field']
      }
    },
    {
      name: 'create_dashboard',
      description: 'Create dashboard in Kibana and return URL',
      inputSchema: {
        type: 'object',
        properties: {
          dash_id: { type: 'string', description: 'Dashboard ID from generate_dashboard' }
        },
        required: ['dash_id']
      }
    },
    {
      name: 'create_alert',
      description: 'Configure a metric alert',
      inputSchema: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Alert name' },
          metric: { type: 'string', description: 'Metric field to monitor' },
          threshold: { type: 'number', description: 'Threshold value' },
          operator: { type: 'string', description: 'Comparison operator (gt/lt/gte/lte)', default: 'gt' },
          index: { type: 'string', description: 'Index pattern' }
        },
        required: ['name', 'metric', 'threshold', 'index']
      }
    },
    {
      name: 'check_alerts',
      description: 'Evaluate all enabled alerts and return triggered alerts',
      inputSchema: { type: 'object', properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    const { name, arguments: args } = request.params;
    
    let result;
    switch (name) {
      case 'discover_fields':
        result = await discoverFields(args.index_pattern);
        break;
      case 'generate_dashboard':
        result = await generateDashboard(args.title, args.index, args.viz_type, args.field, args.time_range);
        break;
      case 'create_dashboard':
        result = await createDashboard(args.dash_id);
        break;
      case 'create_alert':
        result = await createAlert(args.name, args.metric, args.threshold, args.operator, args.index);
        break;
      case 'check_alerts':
        result = await checkAlerts();
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
    
    return { content: [{ type: 'text', text: String(result) }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
