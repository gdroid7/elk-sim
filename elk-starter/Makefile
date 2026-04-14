include .env

.PHONY: up down logs status clean help

up: ## Start ELK stack
	docker compose up -d

down: ## Stop ELK stack
	docker compose down

logs: ## Tail all container logs
	docker compose logs -f

status: ## Show container status + Elasticsearch health
	@docker compose ps
	@echo ""
	@curl -s http://localhost:9200/_cluster/health?pretty 2>/dev/null || echo "Elasticsearch not reachable yet"

clean: ## Stop + remove volumes (deletes all indexed data)
	docker compose down -v

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
