SHELL := /bin/zsh

.PHONY: lint compile simulate-smoke simulate-full local-up local-down deploy-local smoke-local deploy-testnet deploy-production smoke-testnet smoke-testnet-readonly smoke-production smoke-production-readonly public-nested-call-probe testnet-nested-call-probe production-nested-call-probe test-public-env-helpers test-local test-local-isolated test-local-foundation-isolated contract-console test-contract-console test-contract-console-ui test-contract-console-integration test-contract-console-live test-contract-console-testnet test-contract-console-production soak-contract-console release-checklist

lint:
	./scripts/lint_contracts.sh

compile:
	./scripts/compile_contracts.sh

simulate-smoke:
	npm run simulate:smoke

simulate-full:
	npm run simulate:full

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

deploy-production:
	./scripts/deploy_production.sh

smoke-testnet:
	./scripts/smoke_testnet_mutating.sh

smoke-testnet-readonly:
	./scripts/smoke_testnet.sh

smoke-production:
	./scripts/smoke_production.sh

smoke-production-readonly:
	./scripts/smoke_production_readonly.sh

public-nested-call-probe:
	./scripts/public_nested_call_probe.sh

testnet-nested-call-probe:
	./scripts/testnet_nested_call_probe.sh

production-nested-call-probe:
	./scripts/production_nested_call_probe.sh

test-public-env-helpers:
	./tests/public_env_helper_smoke.sh

test-local:
	./tests/local_e2e.sh

test-local-isolated:
	./tests/isolated_e2e.sh

test-local-foundation-isolated:
	./tests/isolated_foundation_e2e.sh

contract-console:
	python3 ./scripts/serve_contract_console.py $(CONTRACT_CONSOLE_ARGS)

test-contract-console:
	python3 -m unittest discover -s tests -p 'test_contract_console.py'

test-contract-console-ui:
	npm run test:contract-console-ui

test-contract-console-integration:
	npm run test:contract-console-integration

test-contract-console-live:
	./tests/contract_console_live_smoke.sh

test-contract-console-testnet:
	./scripts/contract_console_testnet_smoke.sh

test-contract-console-production:
	./scripts/contract_console_production_smoke.sh

soak-contract-console:
	./scripts/soak_contract_console.sh

release-checklist:
	./scripts/release_checklist.sh
