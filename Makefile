SHELL := /bin/zsh

.PHONY: dev-doctor dev-build dev-check dev-test dev-schema dev-smoke lint compile render-validation-fee-payout check-validation-fee-payout compile-validation-fee-payout test-validation-fee-payout plan-validation-fee-deployment apply-validation-fee-deployment test-validation-fee-deployment plan-validation-fee-pool bootstrap-validation-fee-pool check-shell-syntax redact-generated-evidence simulate-build simulate-smoke simulate-full local-up local-down deploy-local smoke-local refresh-testnet-chain refresh-production-chain taira-preflight production-preflight deploy-testnet deploy-production maintain-public-deploy-latest maintain-testnet-deploy-latest maintain-production-deploy-latest publish-trader-api publish-production-trader-api smoke-testnet smoke-testnet-readonly smoke-testnet-trader smoke-testnet-trader-readonly smoke-production smoke-production-readonly smoke-production-trader smoke-production-trader-readonly public-nested-call-probe testnet-nested-call-probe production-nested-call-probe record-rwa-compliance record-testnet-rwa-compliance record-production-rwa-compliance taira-state-repair-plan test-public-env-helpers test-production-auth-config test-release-closeout test-production-cutover test-local test-local-isolated test-local-foundation-isolated contract-console trader-ui test-contract-console test-contract-console-ui test-contract-console-integration test-trader-ui test-contract-console-live test-contract-console-testnet test-contract-console-production soak-contract-console release-taira release-production release-checklist release-production-checklist

dev-doctor:
	zsh ./scripts/dev_iroha.sh doctor --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local)

dev-build:
	zsh ./scripts/dev_iroha.sh build --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local)

dev-check:
	zsh ./scripts/dev_iroha.sh check --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local)

dev-test:
	zsh ./scripts/dev_iroha.sh test --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local)

dev-schema:
	zsh ./scripts/dev_iroha.sh schema --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local) --out docs/interface_specs/generated.md

dev-smoke:
	zsh ./scripts/dev_iroha.sh smoke --manifest iroha.contracts.toml --profile $(or $(SORASWAP_PROFILE),local)

lint:
	zsh ./scripts/lint_contracts.sh

compile:
	zsh ./scripts/compile_contracts.sh

render-validation-fee-payout:
	zsh ./scripts/validation_fee_payout.sh render "$(SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG)"

check-validation-fee-payout:
	zsh ./scripts/validation_fee_payout.sh check "$(SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG)"

compile-validation-fee-payout:
	zsh ./scripts/validation_fee_payout.sh build "$(SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG)"

test-validation-fee-payout:
	zsh ./scripts/validation_fee_payout.sh test "$(SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG)"

plan-validation-fee-deployment:
	zsh ./scripts/apply_validation_fee_deployment.sh plan

apply-validation-fee-deployment:
	zsh ./scripts/apply_validation_fee_deployment.sh apply

test-validation-fee-deployment:
	python3 -m unittest tests/test_prepare_validation_fee_deployment.py
	python3 -m unittest tests/test_publish_immutable_json.py
	python3 -m unittest tests/test_validate_validation_fee_write_gate.py
	zsh ./tests/validation_fee_deployment_evidence_smoke.sh
	zsh ./tests/validation_fee_one_write_smoke.sh

plan-validation-fee-pool:
	zsh ./scripts/bootstrap_validation_fee_pool.sh plan

bootstrap-validation-fee-pool:
	zsh ./scripts/bootstrap_validation_fee_pool.sh apply

check-shell-syntax:
	zsh ./scripts/check_shell_syntax.sh

redact-generated-evidence:
	zsh ./scripts/redact_generated_evidence.sh

simulate-build:
	npm run build

simulate-smoke:
	npm run simulate:smoke

simulate-full:
	npm run simulate:full

local-up:
	zsh ./scripts/local_up.sh

local-down:
	zsh ./scripts/local_down.sh

deploy-local:
	zsh ./scripts/deploy_local.sh

smoke-local:
	zsh ./scripts/smoke_local.sh

refresh-testnet-chain:
	zsh ./scripts/refresh_testnet_chain_snapshot.sh

refresh-production-chain:
	zsh ./scripts/refresh_production_chain_snapshot.sh

taira-preflight:
	zsh ./scripts/taira_preflight.sh

production-preflight:
	zsh ./scripts/production_preflight.sh

deploy-testnet:
	zsh ./scripts/deploy_testnet.sh

deploy-production:
	zsh ./scripts/deploy_production.sh

maintain-public-deploy-latest:
	zsh ./scripts/maintain_public_deploy_latest.sh

maintain-testnet-deploy-latest:
	SORASWAP_PUBLIC_ENV=testnet zsh ./scripts/maintain_public_deploy_latest.sh

maintain-production-deploy-latest:
	SORASWAP_PUBLIC_ENV=production zsh ./scripts/maintain_public_deploy_latest.sh

publish-trader-api:
	zsh ./scripts/publish_trader_api_bundle.sh

publish-production-trader-api:
	zsh ./scripts/publish_production_trader_api_bundle.sh

smoke-testnet:
	zsh ./scripts/smoke_testnet_mutating.sh

smoke-testnet-readonly:
	zsh ./scripts/smoke_testnet.sh

smoke-testnet-trader:
	zsh ./scripts/trader_testnet_mutating.sh

smoke-testnet-trader-readonly:
	zsh ./scripts/trader_testnet_readonly.sh

smoke-production:
	zsh ./scripts/smoke_production.sh

smoke-production-readonly:
	zsh ./scripts/smoke_production_readonly.sh

smoke-production-trader:
	zsh ./scripts/trader_production_mutating.sh

smoke-production-trader-readonly:
	zsh ./scripts/trader_production_readonly.sh

public-nested-call-probe:
	zsh ./scripts/public_nested_call_probe.sh

testnet-nested-call-probe:
	zsh ./scripts/testnet_nested_call_probe.sh

production-nested-call-probe:
	zsh ./scripts/production_nested_call_probe.sh

record-rwa-compliance:
	zsh ./scripts/record_rwa_compliance.sh

record-testnet-rwa-compliance:
	zsh ./scripts/record_testnet_rwa_compliance.sh

record-production-rwa-compliance:
	zsh ./scripts/record_production_rwa_compliance.sh

taira-state-repair-plan:
	zsh ./scripts/taira_state_repair_plan.sh

test-public-env-helpers:
	zsh ./tests/public_env_helper_smoke.sh
	$(MAKE) test-production-auth-config

test-production-auth-config:
	python3 -m unittest -v tests.test_secure_client_config
	zsh ./tests/production_auth_config_smoke.sh

test-release-closeout:
	zsh ./tests/release_closeout_smoke.sh

test-production-cutover:
	python3 ./tests/test_production_cutover.py

test-local:
	zsh ./tests/local_e2e.sh

test-local-isolated:
	zsh ./tests/isolated_e2e.sh

test-local-foundation-isolated:
	zsh ./tests/isolated_foundation_e2e.sh

contract-console:
	python3 ./scripts/serve_contract_console.py $(CONTRACT_CONSOLE_ARGS)

trader-ui:
	python3 ./scripts/serve_trader_ui.py $(TRADER_UI_ARGS)

test-contract-console:
	python3 -m unittest discover -s tests -p 'test_contract_console.py'

test-contract-console-ui:
	npm run test:contract-console-ui

test-contract-console-integration:
	npm run test:contract-console-integration

test-trader-ui:
	python3 -m unittest discover -s tests -p 'test_trader_ui.py'
	npm run test:trader-ui

test-contract-console-live:
	zsh ./tests/contract_console_live_smoke.sh

test-contract-console-testnet:
	zsh ./scripts/contract_console_testnet_smoke.sh

test-contract-console-production:
	zsh ./scripts/contract_console_production_smoke.sh

soak-contract-console:
	zsh ./scripts/soak_contract_console.sh

release-taira:
	zsh ./scripts/release_taira.sh

release-production:
	zsh ./scripts/release_production.sh

release-checklist:
	zsh ./scripts/release_checklist.sh

release-production-checklist:
	zsh ./scripts/release_production_checklist.sh
