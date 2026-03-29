# Shared Contract Notes

The initial scaffold does not yet use Kotodama importable shared libraries.

Current policy:
- Keep shared math and helpers duplicated where necessary until the project
  settles on a reusable Kotodama module pattern that compiles cleanly with
  `../iroha` toolchain expectations.
- Track actual deduplication work in `docs/parity/migration_register.md`.
