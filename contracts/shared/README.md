# Shared Contract Notes

SoraSwap keeps contract helpers local to each Kotodama source unless a shared
module compiles cleanly through the sibling `../iroha` toolchain and preserves
the ABI v1 manifest surface.

Current policy:
- Duplicate small math and state helpers where that keeps contract entrypoints
  explicit and avoids hidden ABI drift.
- Add a shared Kotodama module only after it is covered by the normal
  `scripts/lint_contracts.sh`, `scripts/compile_contracts.sh`, and local smoke
  paths.
- Track production-surface scope in `docs/parity/migration_register.md`; helper
  deduplication alone is not release evidence.
