# ELK Starter Kit

Zero-config ELK stack for any application. Point at a log file, get Kibana.

## Requirements

- Docker + Docker Compose
- A log file (JSON or plain text)

## Quick Start

```bash
# 1. Copy this folder into your project
cp -r elk-starter/ your-project/
cd your-project/elk-starter/

# 2. Configure
cp .env.example .env
# Edit .env: set LOG_PATH, APP_NAME, LOG_FORMAT

# 3. Start
make up

# 4. Open Kibana (takes ~30s to be ready)
open http://localhost:5601
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_PATH` | `/var/log/myapp/app.log` | Absolute path to your log file |
| `APP_NAME` | `myapp` | Tags logs; ES index name becomes `logs-<APP_NAME>-YYYY.MM.dd` |
| `LOG_FORMAT` | `json` | `json` = parse each line as JSON · `text` = store raw line as `message` |

## In Kibana

1. Go to **Stack Management → Index Patterns**
2. Create pattern: `logs-<APP_NAME>-*`
3. Set time field: `@timestamp` (JSON logs with a `time`/`timestamp` field) or leave blank
4. Go to **Discover** → explore your logs

## JSON Log Format

Any newline-delimited JSON works. All top-level keys become searchable Kibana fields.

```json
{"time":"2026-04-14T10:30:00+05:30","level":"INFO","msg":"server started","port":8080}
{"time":"2026-04-14T10:30:05+05:30","level":"ERROR","msg":"db connection failed","error":"timeout"}
```

## Plain Text Logs

Set `LOG_FORMAT=text`. Each line stored as `message` field. Use Kibana's full-text search.

```
2026-04-14 10:30:00 INFO  server started on port 8080
2026-04-14 10:30:05 ERROR db connection failed: timeout
```

## Multiline (Stack Traces)

Filebeat joins lines starting with whitespace to the previous line automatically. Java, Python, Go stack traces work out of the box.

## Commands

```
make up      start stack
make down    stop stack
make logs    tail container logs
make status  container status + ES health check
make clean   stop + delete all data volumes
```

## Ports

| Service | Port |
|---------|------|
| Elasticsearch | 9200 |
| Kibana | 5601 |
| Logstash (beats input) | 5044 |

## Troubleshooting

**Logs not appearing in Kibana?**
- Check filebeat is running: `docker compose ps`
- Tail filebeat logs: `docker compose logs filebeat`
- Verify `LOG_PATH` in `.env` points to an existing, readable file
- On macOS: the file must be under a directory shared with Docker Desktop (check Docker → Preferences → Resources → File Sharing)
