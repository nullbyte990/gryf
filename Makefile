.PHONY: help build up stop down sh logs install lint phpstan cs-check cs-fix rector-check rector-fix check fix qa

DC = docker compose -f compose.yml

##@ Help

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Docker

build: ## Build Docker containers
	@$(DC) build

up: ## Start all services
	@$(DC) up -d

stop: ## Stop services
	@$(DC) stop

down: ## Stop and remove containers
	@$(DC) down

sh: ## Enter PHP container shell
	@$(DC) exec php zsh

logs: ## Show PHP container logs
	@$(DC) logs -f php

install: ## Install Composer dependencies in the PHP container
	@$(DC) exec php composer install

##@ Code Quality

lint: ## Lint Symfony configuration
	@$(DC) exec php composer lint

phpstan: ## Run PHPStan static analysis
	@$(DC) exec php composer phpstan

cs-check: ## Check code style with ECS
	@$(DC) exec php composer cs:check

cs-fix: ## Fix code style with ECS
	@$(DC) exec php composer cs:fix

rector-check: ## Run Rector in dry-run mode
	@$(DC) exec php composer rector:check

rector-fix: ## Apply Rector fixes
	@$(DC) exec php composer rector:fix

check: ## Run all checks
	@$(DC) exec php composer check

fix: ## Run automatic fixes
	@$(DC) exec php composer fix

qa: ## Run full QA suite
	@$(DC) exec php composer qa
