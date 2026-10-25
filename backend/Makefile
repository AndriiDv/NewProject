.PHONY: help lint format test build deploy

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

lint: ## Lint backend with ruff
	uv run ruff check . && uv run ruff format --check .

format: ## Format backend code with ruff
	uv run ruff check --fix . && uv run ruff format .

test: ## Run backend unit/integration tests with pytest
	uv run pytest -v

TAG ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

build: ## Build backend docker image tagged with Git commit SHA
	docker build -t backend:$(TAG) .

deploy: ## Deploy backend to AWS ECS Fargate
	../infra/deploy-backend.sh
