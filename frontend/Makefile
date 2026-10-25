.PHONY: help lint format build deploy

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

lint: ## Lint frontend code and check formatting
	npm run lint && npx prettier --check .

format: ## Format frontend code with prettier
	npm run format

build: ## Build frontend production bundle
	npm run build

deploy: ## Deploy frontend to S3 + CloudFront
	../infra/deploy-frontend.sh
