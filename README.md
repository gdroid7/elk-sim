# Go Log Simulator

A Go-based log simulation system with ELK stack integration for demonstrating observability scenarios.

## Overview

Simulates realistic application scenarios (auth failures, payment declines, slow queries) that generate structured logs, stream them through the ELK stack, and visualize them in Kibana dashboards.

## Stack

- Go 1.22 (stdlib only)
- Elasticsearch 8.12.0
- Logstash 8.12.0
- Kibana 8.12.0
- Filebeat 8.12.0
- Docker Compose

## Quick Start

```bash
# Start ELK stack
docker-compose up -d

# Wait for services to be healthy
docker-compose ps

# Run a scenario
cd scenarios/01-auth-brute-force
./setup.sh
go run main.go
```

## Scenarios

- `01-auth-brute-force` - Authentication brute force attack simulation
- `02-payment-decline` - Payment processing failures
- `03-db-slow-query` - Database performance degradation
- `04-cache-stampede` - Cache invalidation issues
- `05-api-degradation` - API performance degradation

Each scenario includes:
- `main.go` - Standalone log generator
- `setup.sh` - Kibana dashboard setup
- `reset.sh` - Cleanup script
- `dashboard.ndjson` - Pre-configured Kibana dashboard

## Architecture

```
Scenario → JSON logs → Filebeat → Logstash → Elasticsearch → Kibana
```

## Access

- Kibana: http://localhost:5601
- Elasticsearch: http://localhost:9200

## Development

See `PLAN.md` for detailed architecture and `agents/` for specialized agent instructions.
