# Kumone — macOS developer entry points.
.DEFAULT_GOAL := help
.PHONY: help build test app clean

help: ## Show this help
	@echo "Kumone make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

build: ## Build the macOS app with SwiftPM
	@swift build

test: ## Run the macOS SwiftPM test suite
	@swift test

app: ## Build and bundle the macOS .app
	@Scripts/build-app.sh $(CONFIG)

clean: ## Move build artifacts to .tmp/trash
	@mkdir -p .tmp/trash
	@if [ -d .build ]; then mv .build "$$(mktemp -d .tmp/trash/build.XXXXXX)/"; fi
