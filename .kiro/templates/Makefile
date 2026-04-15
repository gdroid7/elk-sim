.PHONY: up down logs status clean

up:
	docker compose -f elk/docker-compose.yml up -d

down:
	docker compose -f elk/docker-compose.yml down

logs:
	docker compose -f elk/docker-compose.yml logs -f

status:
	@docker compose -f elk/docker-compose.yml ps
	@echo ""
	@echo "=== Elasticsearch health ==="
	@curl -s localhost:9200/_cluster/health | python3 -m json.tool 2>/dev/null || echo "ES not ready yet"
	@echo ""
	@echo "=== Log index doc count ==="
	@curl -s "localhost:9200/logs-{{APP_NAME}}-*/_count" | python3 -m json.tool 2>/dev/null || echo "No index yet"

clean:
	docker compose -f elk/docker-compose.yml down -v
	@echo "Data volumes deleted."
