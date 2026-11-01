.DEFAULT_GOAL := help

.PHONY: help up down reset psql
help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- Local infrastructure (docker compose) ---

up: ## Start Postgres; returns only once it is healthy
	docker compose up -d --wait

down: ## Stop containers (data volume is kept)
	docker compose down

reset: ## Stop containers AND delete volumes (wipes the database)
	docker compose down -v

psql: ## Open psql inside the Postgres container
	docker compose exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'
