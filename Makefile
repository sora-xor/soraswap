SHELL := /bin/zsh

.PHONY: lint compile local-up local-down deploy-local smoke-local deploy-testnet smoke-testnet test-local test-local-isolated test-local-foundation-isolated

lint:
	./scripts/lint_contracts.sh

compile:
	./scripts/compile_contracts.sh

local-up:
	./scripts/local_up.sh

local-down:
	./scripts/local_down.sh

deploy-local:
	./scripts/deploy_local.sh

smoke-local:
	./scripts/smoke_local.sh

deploy-testnet:
	./scripts/deploy_testnet.sh

smoke-testnet:
	./scripts/smoke_testnet.sh

test-local:
	./tests/local_e2e.sh

test-local-isolated:
	./tests/isolated_e2e.sh

test-local-foundation-isolated:
	./tests/isolated_foundation_e2e.sh
