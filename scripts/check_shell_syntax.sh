#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${SORASWAP_ROOT:-$SCRIPT_ROOT}"
release_status_doc_freshness_deferred=0
while (( $# > 0 )); do
  case "$1" in
    --prepare-status-doc-closeout)
      if [[ "$release_status_doc_freshness_deferred" == "1" ]]; then
        echo "shell syntax check failed: duplicate --prepare-status-doc-closeout" >&2
        exit 1
      fi
      release_status_doc_freshness_deferred=1
      ;;
    *)
      echo "shell syntax check failed: unsupported argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-shell-syntax.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

typeset -a search_dirs missing_dirs
search_dirs=("$ROOT/scripts" "$ROOT/tests")
missing_dirs=()
for dir in "${search_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    missing_dirs+=("${dir#$ROOT/}/")
  fi
done

if (( ${#missing_dirs[@]} != 0 )); then
  echo "shell syntax check failed: missing required directories: ${(j:, :)missing_dirs}" >&2
  exit 1
fi

typeset -a stale_root_temp_files
stale_root_temp_files=("${(@f)$(find "$ROOT" -maxdepth 1 -type f \( \
  -name '.soraswap-foundation-manifest.*' \
  -o -name '.soraswap-contract-app-chunk-*' \
\) | LC_ALL=C sort)}")
stale_root_temp_failed=0
for temp_path in "${stale_root_temp_files[@]}"; do
  [[ -n "$temp_path" ]] || continue
  stale_root_temp_failed=1
  echo "repo temporary file check failed: stale deploy manifest ${temp_path#$ROOT/}" >&2
done

if (( stale_root_temp_failed != 0 )); then
  exit 1
fi

contract_source_checked=0
contract_source_failed=0
if [[ -d "$ROOT/contracts" ]]; then
  while IFS= read -r -d '' contract_path; do
    [[ -n "$contract_path" ]] || continue
    rel_contract_path="${contract_path#$ROOT/}"
    contract_source_checked=$(( contract_source_checked + 1 ))

    if [[ "$contract_path" == *.ko ]]; then
      continue
    fi
    if [[ "$rel_contract_path" == "contracts/shared/README.md" ]]; then
      continue
    fi

    contract_source_failed=1
    echo "contract source hygiene failed: $rel_contract_path is not a Kotodama .ko source" >&2
  done < <(find "$ROOT/contracts" -type f -print0 | LC_ALL=C sort -z)
fi

if (( contract_source_failed != 0 )); then
  exit 1
fi

migration_register_checked=0
migration_register_failed=0
migration_register_path="$ROOT/docs/parity/migration_register.md"
if [[ -d "$ROOT/docs/parity" || -f "$migration_register_path" ]]; then
  if [[ ! -s "$migration_register_path" ]]; then
    echo "migration register check failed: docs/parity/migration_register.md is missing or empty" >&2
    exit 1
  fi

  migration_ported_count=0
  migration_reference_only_count=0
  while IFS= read -r migration_line || [[ -n "$migration_line" ]]; do
    [[ "$migration_line" == \|* ]] || continue
    [[ "$migration_line" == *"| Status |"* ]] && continue
    [[ "$migration_line" == *"| --- |"* ]] && continue

    IFS='|' read -r _ _ _ migration_status _ <<<"$migration_line"
    migration_status="${migration_status#"${migration_status%%[![:space:]]*}"}"
    migration_status="${migration_status%"${migration_status##*[![:space:]]}"}"
    migration_register_checked=$(( migration_register_checked + 1 ))

    case "$migration_status" in
      ported)
        migration_ported_count=$(( migration_ported_count + 1 ))
        ;;
      reference-only)
        migration_reference_only_count=$(( migration_reference_only_count + 1 ))
        ;;
      *)
        migration_register_failed=1
        echo "migration register check failed: docs/parity/migration_register.md contains non-ported production row: $migration_line" >&2
        ;;
    esac
  done < "$migration_register_path"

  if (( migration_register_checked == 0 )); then
    migration_register_failed=1
    echo "migration register check failed: docs/parity/migration_register.md contains no table rows" >&2
  fi
  if (( migration_ported_count == 0 )); then
    migration_register_failed=1
    echo "migration register check failed: docs/parity/migration_register.md must contain at least one ported production row" >&2
  fi
fi

if (( migration_register_failed != 0 )); then
  exit 1
fi

typeset -a shell_scripts
shell_scripts=("${(@f)$(find "${search_dirs[@]}" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)}")

if (( ${#shell_scripts[@]} == 0 )); then
  echo "shell syntax check failed: no shell scripts found under scripts/ or tests/" >&2
  exit 1
fi

zsh_noexec_stderr_is_environment_warning() {
  local stderr_path="$1"
  local line saw_line=0

  [[ -s "$stderr_path" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    saw_line=1
    case "$line" in
      *": nice(5) failed: operation not permitted")
        ;;
      *)
        return 1
        ;;
    esac
  done < "$stderr_path"

  (( saw_line != 0 ))
}

failed=0
checked=0
for script_path in "${shell_scripts[@]}"; do
  stderr_path="$tmp_dir/${script_path:t}.stderr"
  checked=$(( checked + 1 ))

  if zsh -n "$script_path" >/dev/null 2>"$stderr_path"; then
    continue
  fi

  # zsh no-exec can return a nonzero status for assertion-heavy scripts with
  # top-level negated commands even when parsing reaches EOF cleanly.
  if [[ ! -s "$stderr_path" ]]; then
    continue
  fi
  if zsh_noexec_stderr_is_environment_warning "$stderr_path"; then
    continue
  fi

  failed=1
  echo "shell syntax check failed: ${script_path#$ROOT/}" >&2
  cat "$stderr_path" >&2
done

if (( failed != 0 )); then
  exit 1
fi

typeset -a python_files javascript_files
python_files=("${(@f)$(find "${search_dirs[@]}" -maxdepth 1 -type f -name '*.py' | LC_ALL=C sort)}")
javascript_files=("${(@f)$(find "$ROOT" -maxdepth 1 -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' \) | LC_ALL=C sort)}")
javascript_files+=("${(@f)$(find "$ROOT/tests" -maxdepth 1 -type f -name '*.js' | LC_ALL=C sort)}")
if [[ -d "$ROOT/ui" ]]; then
  javascript_files+=("${(@f)$(find "$ROOT/ui" -type f -name '*.js' | LC_ALL=C sort)}")
fi

python_failed=0
python_checked=0
for python_path in "${python_files[@]}"; do
  [[ -n "$python_path" ]] || continue
  stderr_path="$tmp_dir/${python_path:t}.python.stderr"
  python_checked=$(( python_checked + 1 ))

  if python3 - "$python_path" >/dev/null 2>"$stderr_path" <<'PY'
import ast
import sys
import tokenize

path = sys.argv[1]
with tokenize.open(path) as handle:
    source = handle.read()
ast.parse(source, filename=path)
PY
  then
    continue
  fi

  python_failed=1
  echo "python syntax check failed: ${python_path#$ROOT/}" >&2
  cat "$stderr_path" >&2
done

if (( python_failed != 0 )); then
  exit 1
fi

javascript_failed=0
javascript_checked=0
if (( ${#javascript_files[@]} != 0 )) && ! command -v node >/dev/null 2>&1; then
  javascript_failed=1
  echo "javascript syntax check failed: node is required to parse JavaScript files" >&2
fi
if (( javascript_failed == 0 )); then
  for javascript_path in "${javascript_files[@]}"; do
    [[ -n "$javascript_path" ]] || continue
    stderr_path="$tmp_dir/${javascript_path:t}.javascript.stderr"
    javascript_checked=$(( javascript_checked + 1 ))

    if node --check "$javascript_path" >/dev/null 2>"$stderr_path"; then
      continue
    fi

    javascript_failed=1
    echo "javascript syntax check failed: ${javascript_path#$ROOT/}" >&2
    cat "$stderr_path" >&2
  done
fi

if (( javascript_failed != 0 )); then
  exit 1
fi

typeset -a make_shell_refs make_repo_file_refs
if [[ -f "$ROOT/Makefile" ]]; then
  make_shell_refs=("${(@f)$(awk '
    {
      line = $0
      while (match(line, /\.\/(scripts|tests)\/[A-Za-z0-9_.\/-]+\.sh/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$ROOT/Makefile" | LC_ALL=C sort -u)}")
  make_repo_file_refs=("${(@f)$(awk '
    {
      line = $0
      while (match(line, /\.\/(scripts|tests)\/[A-Za-z0-9_.\/-]+\.(py|js)/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$ROOT/Makefile" | LC_ALL=C sort -u)}")
else
  make_shell_refs=()
  make_repo_file_refs=()
fi

surface_failed=0
surface_checked=0
for ref in "${make_shell_refs[@]}"; do
  [[ -n "$ref" ]] || continue
  ref_path="$ROOT/${ref#./}"
  surface_checked=$(( surface_checked + 1 ))

  if [[ ! -f "$ref_path" ]]; then
    surface_failed=1
    echo "shell surface check failed: Makefile references missing $ref" >&2
    continue
  fi

  if [[ ! -x "$ref_path" ]]; then
    surface_failed=1
    echo "shell surface check failed: Makefile references non-executable $ref" >&2
  fi
done

if (( surface_failed != 0 )); then
  exit 1
fi

make_repo_ref_failed=0
make_repo_ref_checked=0
for ref in "${make_repo_file_refs[@]}"; do
  [[ -n "$ref" ]] || continue
  ref_path="$ROOT/${ref#./}"
  make_repo_ref_checked=$(( make_repo_ref_checked + 1 ))

  if [[ ! -f "$ref_path" ]]; then
    make_repo_ref_failed=1
    echo "makefile repo path check failed: Makefile references missing $ref" >&2
  fi
done

if (( make_repo_ref_failed != 0 )); then
  exit 1
fi

typeset -a make_unittest_discover_refs
make_unittest_discover_refs=()
if [[ -f "$ROOT/Makefile" ]]; then
  make_unittest_discover_output="$tmp_dir/make-unittest-discover.out"
  make_unittest_discover_stderr="$tmp_dir/make-unittest-discover.stderr"
  if python3 - "$ROOT/Makefile" >"$make_unittest_discover_output" 2>"$make_unittest_discover_stderr" <<'PY'
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    for line_no, raw_line in enumerate(handle, 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            tokens = shlex.split(line)
        except ValueError:
            continue

        for index in range(0, max(0, len(tokens) - 3)):
            if tokens[index:index + 4] != ["python3", "-m", "unittest", "discover"]:
                continue

            search_dir = "."
            pattern = "test*.py"
            cursor = index + 4
            while cursor < len(tokens):
                token = tokens[cursor]
                if token == "-s" and cursor + 1 < len(tokens):
                    search_dir = tokens[cursor + 1]
                    cursor += 2
                    continue
                if token.startswith("-s") and len(token) > 2:
                    search_dir = token[2:]
                    cursor += 1
                    continue
                if token == "-p" and cursor + 1 < len(tokens):
                    pattern = tokens[cursor + 1]
                    cursor += 2
                    continue
                if token.startswith("-p") and len(token) > 2:
                    pattern = token[2:]
                    cursor += 1
                    continue
                cursor += 1

            print(f"{line_no}\t{search_dir}\t{pattern}")
PY
  then
    make_unittest_discover_refs=("${(@f)$(cat "$make_unittest_discover_output")}")
  else
    echo "unittest discovery check failed: Makefile could not be parsed" >&2
    cat "$make_unittest_discover_stderr" >&2
    exit 1
  fi
fi

unittest_discover_failed=0
unittest_discover_checked=0
for ref_pair in "${make_unittest_discover_refs[@]}"; do
  [[ -n "$ref_pair" ]] || continue
  line_no="${ref_pair%%$'\t'*}"
  rest="${ref_pair#*$'\t'}"
  search_dir="${rest%%$'\t'*}"
  pattern="${rest#*$'\t'}"
  unittest_discover_checked=$(( unittest_discover_checked + 1 ))

  if [[ "$search_dir" == /* || "$search_dir" == *'$'* || "$search_dir" == *'*'* || "$search_dir" == *'?'* ]]; then
    unittest_discover_failed=1
    echo "unittest discovery check failed: Makefile:$line_no uses unsupported unittest search directory $search_dir" >&2
    continue
  fi

  if [[ "$pattern" == */* || "$pattern" == *'$'* ]]; then
    unittest_discover_failed=1
    echo "unittest discovery check failed: Makefile:$line_no uses unsupported unittest pattern $pattern" >&2
    continue
  fi

  if [[ ! -d "$ROOT/$search_dir" ]]; then
    unittest_discover_failed=1
    echo "unittest discovery check failed: Makefile:$line_no references missing test directory $search_dir" >&2
    continue
  fi

  if ! find "$ROOT/$search_dir" -maxdepth 1 -type f -name "$pattern" -print -quit | grep -q .; then
    unittest_discover_failed=1
    echo "unittest discovery check failed: Makefile:$line_no discover pattern $search_dir/$pattern matches no files" >&2
  fi
done

if (( unittest_discover_failed != 0 )); then
  exit 1
fi

typeset -A package_scripts
typeset -a package_script_names make_npm_run_refs package_npm_run_refs package_script_file_refs
package_script_names=()
make_npm_run_refs=()
package_npm_run_refs=()
package_script_file_refs=()
package_script_command_checked=0
package_lock_checked=0
if [[ -f "$ROOT/package.json" ]]; then
  package_script_output="$tmp_dir/package-scripts.out"
  package_script_refs_output="$tmp_dir/package-script-refs.out"
  package_script_file_refs_output="$tmp_dir/package-script-file-refs.out"
  package_script_command_output="$tmp_dir/package-script-commands.out"
  package_script_stderr="$tmp_dir/package-scripts.stderr"
  if python3 - "$ROOT/package.json" >"$package_script_output" 2>"$package_script_stderr" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    package = json.load(handle)

scripts = package.get("scripts", {})
if not isinstance(scripts, dict):
    raise SystemExit("package.json scripts must be an object")

for script_name in sorted(scripts):
    print(script_name)
PY
  then
    package_script_names=("${(@f)$(cat "$package_script_output")}")
  else
    echo "npm script reference check failed: package.json scripts could not be parsed" >&2
    cat "$package_script_stderr" >&2
    exit 1
  fi
  if python3 - "$ROOT/package.json" >"$package_script_refs_output" 2>"$package_script_stderr" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    package = json.load(handle)

scripts = package.get("scripts", {})
if not isinstance(scripts, dict):
    raise SystemExit("package.json scripts must be an object")

npm_run_pattern = re.compile(r"(?<![A-Za-z0-9_./-])npm\s+run\s+([A-Za-z0-9:_-]+)")
for owner_name in sorted(scripts):
    command = scripts[owner_name]
    if not isinstance(command, str):
        continue
    for match in npm_run_pattern.finditer(command):
        print(f"{owner_name}\t{match.group(1)}")
PY
  then
    package_npm_run_refs=("${(@f)$(cat "$package_script_refs_output")}")
  else
    echo "npm script reference check failed: package.json scripts could not be parsed" >&2
    cat "$package_script_stderr" >&2
    exit 1
  fi
  if python3 - "$ROOT/package.json" >"$package_script_file_refs_output" 2>"$package_script_stderr" <<'PY'
import json
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    package = json.load(handle)

scripts = package.get("scripts", {})
if not isinstance(scripts, dict):
    raise SystemExit("package.json scripts must be an object")

file_suffixes = (".js", ".cjs", ".mjs", ".ts", ".tsx")

def candidate_path(token):
    if not token or "$" in token or "*" in token or "?" in token:
        return None
    if token.startswith(("http://", "https://", "/", "~")):
        return None
    if token.startswith("--") and "=" in token:
        token = token.split("=", 1)[1]
    elif token.startswith("-"):
        return None
    token = token.lstrip("./")
    if token.endswith(file_suffixes):
        return token
    return None

for owner_name in sorted(scripts):
    command = scripts[owner_name]
    if not isinstance(command, str):
        continue
    try:
        tokens = shlex.split(command)
    except ValueError as error:
        raise SystemExit(f"could not parse package script {owner_name}: {error}") from error
    for token in tokens:
        path = candidate_path(token)
        if path is not None:
            print(f"{owner_name}\t{path}")
PY
  then
    package_script_file_refs=("${(@f)$(cat "$package_script_file_refs_output")}")
  else
    echo "package script path check failed: package.json scripts could not be parsed" >&2
    cat "$package_script_stderr" >&2
    exit 1
  fi
  if python3 - "$ROOT/package.json" >"$package_script_command_output" 2>"$package_script_stderr" <<'PY'
import json
import re
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    package = json.load(handle)

scripts = package.get("scripts", {})
if not isinstance(scripts, dict):
    raise SystemExit("package.json scripts must be an object")

dependencies = set()
for dependency_key in ("dependencies", "devDependencies", "optionalDependencies"):
    dependency_group = package.get(dependency_key, {})
    if isinstance(dependency_group, dict):
        dependencies.update(dependency_group)

allowed_commands = {
    "bash",
    "cd",
    "echo",
    "env",
    "false",
    "mkdir",
    "node",
    "npm",
    "npx",
    "python3",
    "rm",
    "sh",
    "true",
    "zsh",
}
dependency_backed_commands = {
    "jest": ("jest",),
    "playwright": ("@playwright/test", "playwright"),
    "tsc": ("typescript",),
}
operators = {"&&", "||", ";", "|"}
env_assignment_pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*")

def command_tokens(command):
    normalized = (
        command.replace("&&", " && ")
        .replace("||", " || ")
        .replace(";", " ; ")
        .replace("|", " | ")
    )
    tokens = shlex.split(normalized)
    expect_command = True
    for token in tokens:
        if token in operators:
            expect_command = True
            continue
        if not expect_command:
            continue
        if env_assignment_pattern.match(token):
            continue
        yield token
        expect_command = False

errors = []
checked = 0
for owner_name in sorted(scripts):
    command = scripts[owner_name]
    if not isinstance(command, str):
        continue
    try:
        commands = list(command_tokens(command))
    except ValueError as error:
        raise SystemExit(f"could not parse package script {owner_name}: {error}") from error
    for command_name in commands:
        checked += 1
        if command_name.startswith(("./", "../", "/")):
            continue
        required_dependencies = dependency_backed_commands.get(command_name)
        if required_dependencies is not None:
            if not any(required in dependencies for required in required_dependencies):
                errors.append(
                    "package script command check failed: "
                    f"package script {owner_name} command {command_name} requires dependency "
                    f"{' or '.join(required_dependencies)}"
                )
            continue
        if command_name not in allowed_commands:
            errors.append(
                "package script command check failed: "
                f"package script {owner_name} uses unsupported command {command_name}"
            )

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    package_script_command_checked="$(cat "$package_script_command_output")"
  else
    cat "$package_script_stderr" >&2
    exit 1
  fi
fi

if [[ -f "$ROOT/package.json" && -f "$ROOT/package-lock.json" ]]; then
  package_lock_output="$tmp_dir/package-lock.out"
  package_lock_stderr="$tmp_dir/package-lock.stderr"
  if python3 - "$ROOT/package.json" "$ROOT/package-lock.json" >"$package_lock_output" 2>"$package_lock_stderr" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    package = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    package_lock = json.load(handle)

root_package = package_lock.get("packages", {}).get("")
if not isinstance(root_package, dict):
    print("package lock check failed: package-lock.json is missing packages[\"\"] root metadata", file=sys.stderr)
    raise SystemExit(1)

errors = []
for scalar_key in ("name", "version"):
    if package.get(scalar_key) != root_package.get(scalar_key):
        errors.append(
            "package lock check failed: "
            f"package-lock.json root {scalar_key} does not match package.json"
        )

for dependency_key in ("dependencies", "devDependencies", "optionalDependencies"):
    package_dependencies = package.get(dependency_key, {})
    lock_dependencies = root_package.get(dependency_key, {})
    if package_dependencies is None:
        package_dependencies = {}
    if lock_dependencies is None:
        lock_dependencies = {}
    if not isinstance(package_dependencies, dict):
        errors.append(f"package lock check failed: package.json {dependency_key} must be an object")
        continue
    if not isinstance(lock_dependencies, dict):
        errors.append(f"package lock check failed: package-lock.json root {dependency_key} must be an object")
        continue
    if package_dependencies != lock_dependencies:
        errors.append(
            "package lock check failed: "
            f"package-lock.json root {dependency_key} does not match package.json"
        )

print(1)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    package_lock_checked="$(cat "$package_lock_output")"
  else
    cat "$package_lock_stderr" >&2
    exit 1
  fi
fi

root_config_checked=0
root_config_output="$tmp_dir/root-config.out"
root_config_stderr="$tmp_dir/root-config.stderr"
if python3 - "$ROOT" "$SCRIPT_ROOT" >"$root_config_output" 2>"$root_config_stderr" <<'PY'
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
script_root = Path(sys.argv[2]).resolve()
root_is_real_checkout = root.resolve() == script_root
checked = 0
errors = []

def repo_path(label, raw):
    if not isinstance(raw, str) or not raw:
        errors.append(f"root config check failed: {label} must be a non-empty string")
        return None
    if raw.startswith(("/", "~")) or "$" in raw:
        errors.append(f"root config check failed: {label} uses unsupported path {raw}")
        return None
    normalized = raw.replace("<rootDir>", ".").lstrip("./")
    return root / normalized

def path_matches(base, pattern):
    if pattern.startswith(("/", "~")) or "$" in pattern:
        return []
    matches = []
    for candidate in base.rglob("*"):
        if not candidate.is_file():
            continue
        rel = candidate.relative_to(base).as_posix()
        alternate_pattern = pattern[3:] if pattern.startswith("**/") else pattern
        if (
            fnmatch.fnmatch(rel, pattern)
            or fnmatch.fnmatch(rel, alternate_pattern)
            or fnmatch.fnmatch(candidate.name, pattern)
            or fnmatch.fnmatch(candidate.name, alternate_pattern)
        ):
            matches.append(candidate)
    return matches

def parse_js_string_array(source, key):
    match = re.search(rf"\b{re.escape(key)}\s*:\s*\[([^\]]*)\]", source, re.S)
    if not match:
        return []
    return re.findall(r"""["']([^"']+)["']""", match.group(1))

def parse_js_string_value(source, key):
    match = re.search(rf"""\b{re.escape(key)}\s*:\s*["']([^"']+)["']""", source)
    if match:
        return match.group(1)
    return None

def git_ignores(path):
    result = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "--no-index", "-q", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0

tsconfig_path = root / "tsconfig.json"
if tsconfig_path.exists():
    checked += 1
    try:
        tsconfig = json.loads(tsconfig_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        errors.append(f"root config check failed: tsconfig.json could not be parsed: {error}")
    else:
        includes = tsconfig.get("include", [])
        if not isinstance(includes, list) or not includes:
            errors.append("root config check failed: tsconfig.json include must be a non-empty array")
        for include in includes:
            if not isinstance(include, str):
                errors.append("root config check failed: tsconfig.json include entries must be strings")
                continue
            if include.startswith(("/", "~")) or "$" in include:
                errors.append(f"root config check failed: tsconfig.json include uses unsupported path {include}")
                continue
            if not list(root.glob(include)):
                errors.append(f"root config check failed: tsconfig.json include {include} matches no files")

jest_config_path = root / "jest.config.cjs"
if jest_config_path.exists():
    checked += 1
    source = jest_config_path.read_text(encoding="utf-8")
    roots = parse_js_string_array(source, "roots")
    test_matches = parse_js_string_array(source, "testMatch")
    if not roots:
        errors.append("root config check failed: jest.config.cjs roots must be a non-empty string array")
    if not test_matches:
        errors.append("root config check failed: jest.config.cjs testMatch must be a non-empty string array")
    for root_entry in roots:
        root_path = repo_path("jest.config.cjs roots entry", root_entry)
        if root_path is None:
            continue
        if not root_path.is_dir():
            errors.append(f"root config check failed: jest.config.cjs roots entry {root_entry} is missing")
            continue
        for pattern in test_matches:
            if not path_matches(root_path, pattern):
                errors.append(
                    "root config check failed: "
                    f"jest.config.cjs testMatch {pattern} matches no files under {root_entry}"
                )

playwright_config_path = root / "playwright.config.cjs"
if playwright_config_path.exists():
    checked += 1
    source = playwright_config_path.read_text(encoding="utf-8")
    test_dir = parse_js_string_value(source, "testDir")
    test_matches = parse_js_string_array(source, "testMatch")
    if test_dir is None:
        errors.append("root config check failed: playwright.config.cjs testDir must be a string")
    if not test_matches:
        errors.append("root config check failed: playwright.config.cjs testMatch must be a non-empty string array")
    test_dir_path = repo_path("playwright.config.cjs testDir", test_dir) if test_dir is not None else None
    if test_dir_path is not None:
        if not test_dir_path.is_dir():
            errors.append(f"root config check failed: playwright.config.cjs testDir {test_dir} is missing")
        else:
            for pattern in test_matches:
                if not path_matches(test_dir_path, pattern):
                    errors.append(
                        "root config check failed: "
                        f"playwright.config.cjs testMatch {pattern} matches no files under {test_dir}"
                    )

gitignore_path = root / ".gitignore"
if gitignore_path.exists():
    checked += 1
    gitignore_lines = {
        line.strip()
        for line in gitignore_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    for environment in ("local", "staging", "testnet", "production"):
        ignore_pattern = f"deployments/{environment}/**"
        keep_pattern = f"!deployments/{environment}/.gitkeep"
        if ignore_pattern not in gitignore_lines:
            errors.append(f"root config check failed: .gitignore must ignore {ignore_pattern}")
        if keep_pattern not in gitignore_lines:
            errors.append(f"root config check failed: .gitignore must keep {keep_pattern}")
        keep_path = root / "deployments" / environment / ".gitkeep"
        if not keep_path.is_file():
            errors.append(f"root config check failed: missing deployments/{environment}/.gitkeep")
        if not git_ignores(f"deployments/{environment}/check-ignore-probe.latest.json"):
            errors.append(f"root config check failed: .gitignore must ignore generated deployments/{environment} JSON")
        if git_ignores(f"deployments/{environment}/.gitkeep"):
            errors.append(f"root config check failed: .gitignore must not ignore deployments/{environment}/.gitkeep")
    for environment in ("testnet", "production"):
        ignore_pattern = f"config/{environment}/*.toml"
        example_pattern = f"!config/{environment}/*.toml.example"
        if ignore_pattern not in gitignore_lines:
            errors.append(f"root config check failed: .gitignore must ignore {ignore_pattern}")
        if example_pattern not in gitignore_lines:
            errors.append(f"root config check failed: .gitignore must keep {example_pattern}")
        example_dir = root / "config" / environment
        if not any(example_dir.glob("*.toml.example")):
            errors.append(f"root config check failed: missing config/{environment}/*.toml.example")
        if not git_ignores(f"config/{environment}/check-ignore-probe.toml"):
            errors.append(f"root config check failed: .gitignore must ignore config/{environment}/*.toml")
        if git_ignores(f"config/{environment}/check-ignore-probe.toml.example"):
            errors.append(f"root config check failed: .gitignore must not ignore config/{environment}/*.toml.example")
    if "config/*.local.toml" not in gitignore_lines:
        errors.append("root config check failed: .gitignore must ignore config/*.local.toml")
    if not git_ignores("config/check-ignore-probe.local.toml"):
        errors.append("root config check failed: .gitignore must ignore config/*.local.toml")
else:
    if root_is_real_checkout:
        errors.append("root config check failed: .gitignore is missing")

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  root_config_checked="$(cat "$root_config_output")"
else
  cat "$root_config_stderr" >&2
  exit 1
fi

ui_asset_ref_checked=0
if [[ -d "$ROOT/ui" ]]; then
  ui_asset_output="$tmp_dir/ui-assets.out"
  ui_asset_stderr="$tmp_dir/ui-assets.stderr"
  if python3 - "$ROOT" >"$ui_asset_output" 2>"$ui_asset_stderr" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

root = Path(sys.argv[1]).resolve()
ui_root = root / "ui"
errors = []
checked = 0

external_prefixes = (
    "#",
    "data:",
    "http://",
    "https://",
    "javascript:",
    "mailto:",
    "tel:",
    "//",
)
asset_attrs = {
    "audio": {"src"},
    "embed": {"src"},
    "iframe": {"src"},
    "img": {"src"},
    "input": {"src"},
    "link": {"href"},
    "script": {"src"},
    "source": {"src", "srcset"},
    "track": {"src"},
    "video": {"poster", "src"},
}

class AssetParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        expected_attrs = asset_attrs.get(tag.lower(), set())
        for name, value in attrs:
            if value is not None and name.lower() in expected_attrs:
                self.refs.append((tag.lower(), name.lower(), value))

def app_root_for(html_path):
    try:
        rel = html_path.relative_to(ui_root)
    except ValueError:
        return html_path.parent
    return ui_root / rel.parts[0] if rel.parts else html_path.parent

def is_external(raw):
    lowered = raw.strip().lower()
    return not lowered or lowered.startswith(external_prefixes)

def candidate_paths(source_path, raw):
    split = urlsplit(raw.strip())
    raw_path = unquote(split.path)
    if not raw_path:
        return []
    if Path(raw_path).is_absolute():
        return [app_root_for(source_path) / raw_path.lstrip("/")]
    if raw_path.endswith(","):
        raw_path = raw_path[:-1]
    return [source_path.parent / raw_path]

def check_ui_ref(source_path, rel_source, ref):
    global checked
    if is_external(ref):
        return
    for candidate in candidate_paths(source_path, ref):
        checked += 1
        resolved = candidate.resolve(strict=False)
        try:
            resolved.relative_to(ui_root)
        except ValueError:
            errors.append(
                "ui asset reference check failed: "
                f"{rel_source} references UI-external asset {ref}"
            )
            continue
        if not resolved.is_file():
            errors.append(
                "ui asset reference check failed: "
                f"{rel_source} references missing {ref}"
            )

for html_path in sorted(ui_root.rglob("*.html")):
    parser = AssetParser()
    rel_html = html_path.relative_to(root).as_posix()
    try:
        parser.feed(html_path.read_text(encoding="utf-8"))
    except UnicodeDecodeError as error:
        errors.append(f"ui asset reference check failed: {rel_html} could not be read as UTF-8: {error}")
        continue

    for _tag, attr, raw in parser.refs:
        if is_external(raw):
            continue
        if attr == "srcset":
            refs = [part.strip().split()[0] for part in raw.split(",") if part.strip()]
        else:
            refs = [raw]
        for ref in refs:
            check_ui_ref(html_path, rel_html, ref)

css_url_pattern = re.compile(r"url\(\s*(['\"]?)(.*?)\1\s*\)", re.I)
css_import_pattern = re.compile(r"@import\s+(?:url\(\s*)?(['\"])(.*?)\1", re.I)
for css_path in sorted(ui_root.rglob("*.css")):
    rel_css = css_path.relative_to(root).as_posix()
    try:
        source = css_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        errors.append(f"ui asset reference check failed: {rel_css} could not be read as UTF-8: {error}")
        continue
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    seen_refs = set()
    for pattern in (css_url_pattern, css_import_pattern):
        for match in pattern.finditer(source):
            ref = match.group(2).strip()
            if not ref or ref in seen_refs:
                continue
            seen_refs.add(ref)
            check_ui_ref(css_path, rel_css, ref)

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    ui_asset_ref_checked="$(cat "$ui_asset_output")"
  else
    cat "$ui_asset_stderr" >&2
    exit 1
  fi
fi

ui_dom_ref_checked=0
if [[ -d "$ROOT/ui" ]]; then
  ui_dom_output="$tmp_dir/ui-dom.out"
  ui_dom_stderr="$tmp_dir/ui-dom.stderr"
  if python3 - "$ROOT" >"$ui_dom_output" 2>"$ui_dom_stderr" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
ui_root = root / "ui"
errors = []
checked = 0

selector_pattern = re.compile(
    r"""document\.querySelector(?:All)?\(\s*(['"])(.*?)\1\s*\)"""
)
id_selector_pattern = re.compile(r"^#[A-Za-z][A-Za-z0-9_-]*$")
attribute_selector_pattern = re.compile(
    r"""^\[([A-Za-z_][A-Za-z0-9_:-]*)(?:=(['"]?)([^'"\]]+)\2)?\]$"""
)

class DomParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = {}
        self.attrs = {}
        self.duplicates = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            normalized_name = name.lower()
            normalized_value = "" if value is None else value
            self.attrs.setdefault(normalized_name, set()).add(normalized_value)
            if normalized_name != "id" or value is None:
                continue
            location = self.getpos()[0]
            if value in self.ids:
                self.duplicates.append((value, location))
            else:
                self.ids[value] = location

def html_path_for(js_path):
    candidate = js_path.with_name("index.html")
    if candidate.is_file():
        return candidate
    try:
        rel = js_path.relative_to(ui_root)
    except ValueError:
        return None
    if not rel.parts:
        return None
    candidate = ui_root / rel.parts[0] / "index.html"
    return candidate if candidate.is_file() else None

def rel(path):
    return path.relative_to(root).as_posix()

html_ids_by_path = {}
html_attrs_by_path = {}
for html_path in sorted(ui_root.rglob("index.html")):
    parser = DomParser()
    try:
        parser.feed(html_path.read_text(encoding="utf-8"))
    except UnicodeDecodeError as error:
        errors.append(f"ui DOM reference check failed: {rel(html_path)} could not be read as UTF-8: {error}")
        continue
    for duplicate_id, line_no in parser.duplicates:
        errors.append(
            "ui DOM reference check failed: "
            f"{rel(html_path)}:{line_no} repeats id #{duplicate_id}"
        )
    html_ids_by_path[html_path] = set(parser.ids)
    html_attrs_by_path[html_path] = parser.attrs

for js_path in sorted(ui_root.rglob("*.js")):
    html_path = html_path_for(js_path)
    if html_path is None:
        continue
    html_ids = html_ids_by_path.get(html_path)
    html_attrs = html_attrs_by_path.get(html_path)
    if html_ids is None or html_attrs is None:
        continue
    try:
        source = js_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        errors.append(f"ui DOM reference check failed: {rel(js_path)} could not be read as UTF-8: {error}")
        continue
    for match in selector_pattern.finditer(source):
        selector = match.group(2)
        line_no = source.count("\n", 0, match.start()) + 1
        if id_selector_pattern.match(selector):
            checked += 1
            if selector[1:] in html_ids:
                continue
            errors.append(
                "ui DOM reference check failed: "
                f"{rel(js_path)}:{line_no} references missing {selector} in {rel(html_path)}"
            )
            continue
        attribute_match = attribute_selector_pattern.match(selector)
        if attribute_match:
            checked += 1
            attr_name = attribute_match.group(1).lower()
            attr_value = attribute_match.group(3)
            values = html_attrs.get(attr_name, set())
            if attr_value is None:
                if values:
                    continue
            elif attr_value in values:
                continue
            errors.append(
                "ui DOM reference check failed: "
                f"{rel(js_path)}:{line_no} references missing {selector} in {rel(html_path)}"
            )

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    ui_dom_ref_checked="$(cat "$ui_dom_output")"
  else
    cat "$ui_dom_stderr" >&2
    exit 1
  fi
fi

for script_name in "${package_script_names[@]}"; do
  [[ -n "$script_name" ]] || continue
  package_scripts[$script_name]=1
done

if [[ -f "$ROOT/Makefile" ]]; then
  make_npm_run_refs=("${(@f)$(awk '
    {
      line = $0
      while (match(line, /(^|[;&|[:space:]`])npm[[:space:]]+run[[:space:]]+[A-Za-z0-9:_-]+/)) {
        command = substr(line, RSTART, RLENGTH)
        sub(/^.*npm[[:space:]]+run[[:space:]]+/, "", command)
        print command
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$ROOT/Makefile" | LC_ALL=C sort -u)}")
fi

npm_script_ref_failed=0
npm_script_ref_checked=0
for script_name in "${make_npm_run_refs[@]}"; do
  [[ -n "$script_name" ]] || continue
  npm_script_ref_checked=$(( npm_script_ref_checked + 1 ))
  if [[ -z "${package_scripts[$script_name]:-}" ]]; then
    npm_script_ref_failed=1
    echo "npm script reference check failed: Makefile references missing package script $script_name" >&2
  fi
done

if (( npm_script_ref_failed != 0 )); then
  exit 1
fi

package_script_ref_failed=0
package_script_ref_checked=0
for ref_pair in "${package_npm_run_refs[@]}"; do
  [[ -n "$ref_pair" ]] || continue
  owner_name="${ref_pair%%$'\t'*}"
  script_name="${ref_pair#*$'\t'}"
  package_script_ref_checked=$(( package_script_ref_checked + 1 ))
  if [[ -z "${package_scripts[$script_name]:-}" ]]; then
    package_script_ref_failed=1
    echo "npm script reference check failed: package script $owner_name references missing package script $script_name" >&2
  fi
done

if (( package_script_ref_failed != 0 )); then
  exit 1
fi

typeset -A package_script_file_ref_seen
package_script_file_ref_failed=0
package_script_file_ref_checked=0
for ref_pair in "${package_script_file_refs[@]}"; do
  [[ -n "$ref_pair" ]] || continue
  owner_name="${ref_pair%%$'\t'*}"
  ref="${ref_pair#*$'\t'}"
  ref_key="$owner_name:$ref"
  [[ -z "${package_script_file_ref_seen[$ref_key]:-}" ]] || continue
  package_script_file_ref_seen[$ref_key]=1
  package_script_file_ref_checked=$(( package_script_file_ref_checked + 1 ))
  if [[ ! -f "$ROOT/$ref" ]]; then
    package_script_file_ref_failed=1
    echo "package script path check failed: package script $owner_name references missing $ref" >&2
  fi
done

if (( package_script_file_ref_failed != 0 )); then
  exit 1
fi

typeset -A script_ref_seen
script_ref_failed=0
script_ref_checked=0

normalize_shell_script_ref() {
  local ref="$1"

  case "$ref" in
    ./*)
      printf '%s\n' "${ref#./}"
      ;;
    \$ROOT/*|\$\{ROOT\}/*|\$SORASWAP_ROOT/*|\$\{SORASWAP_ROOT\}/*|\$SCRIPT_ROOT/*|\$\{SCRIPT_ROOT\}/*|\$REPO_ROOT/*|\$\{REPO_ROOT\}/*)
      printf '%s\n' "${ref#*/}"
      ;;
    *)
      printf '%s\n' "$ref"
      ;;
  esac
}

for source_script in "$ROOT/scripts"/*.sh; do
  [[ -f "$source_script" ]] || continue

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ '^[[:space:]]*#' ]] && continue

    ref_line="$line"
    while [[ "$ref_line" =~ '(\./(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$SORASWAP_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{SORASWAP_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$SCRIPT_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{SCRIPT_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$REPO_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{REPO_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh)' ]]; do
      ref="$MATCH"
      rel_ref="$(normalize_shell_script_ref "$ref")"
      ref_path="$ROOT/$rel_ref"
      ref_key="${source_script#$ROOT/}:$rel_ref"
      ref_line="${ref_line#*"$ref"}"
      [[ -z "${script_ref_seen[$ref_key]:-}" ]] || continue
      script_ref_seen[$ref_key]=1
      script_ref_checked=$(( script_ref_checked + 1 ))

      if [[ ! -f "$ref_path" ]]; then
        script_ref_failed=1
        echo "shell reference check failed: ${source_script#$ROOT/} references missing $ref" >&2
        continue
      fi

      if [[ "$line" =~ '^[[:space:]]*source[[:space:]]+' || "$line" =~ '^[[:space:]]*\.[[:space:]]+' ]]; then
        continue
      fi

      if [[ ! -x "$ref_path" ]]; then
        script_ref_failed=1
        echo "shell reference check failed: ${source_script#$ROOT/} references non-executable $ref" >&2
      fi
    done
  done < "$source_script"
done

if (( script_ref_failed != 0 )); then
  exit 1
fi

typeset -A script_repo_ref_seen
script_repo_ref_failed=0
script_repo_ref_checked=0

for source_script in "$ROOT/scripts"/*.sh; do
  [[ -f "$source_script" ]] || continue

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ '^[[:space:]]*#' ]] && continue

    ref_line="$line"
    while [[ "$ref_line" =~ '(^|[^A-Za-z0-9_./-])((scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\./(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$\{ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$SORASWAP_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$\{SORASWAP_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$SCRIPT_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$\{SCRIPT_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$REPO_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js)|\$\{REPO_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.(py|js))' ]]; do
      ref="$match[2]"
      rel_ref="$(normalize_shell_script_ref "$ref")"
      ref_path="$ROOT/$rel_ref"
      ref_key="${source_script#$ROOT/}:$rel_ref"
      matched_ref="$MATCH"
      ref_line="${ref_line#*"$matched_ref"}"
      [[ -z "${script_repo_ref_seen[$ref_key]:-}" ]] || continue
      script_repo_ref_seen[$ref_key]=1
      script_repo_ref_checked=$(( script_repo_ref_checked + 1 ))

      if [[ ! -f "$ref_path" ]]; then
        script_repo_ref_failed=1
        echo "repo reference check failed: ${source_script#$ROOT/} references missing $ref" >&2
      fi
    done
  done < "$source_script"
done

if (( script_repo_ref_failed != 0 )); then
  exit 1
fi

typeset -A make_targets make_phony_targets
typeset -a make_target_names make_phony_names doc_paths
make_target_names=()
make_phony_names=()
if [[ -f "$ROOT/Makefile" ]]; then
  make_target_names=("${(@f)$(awk -F: '/^[A-Za-z0-9_.-]+:/ && $1 != ".PHONY" { print $1 }' "$ROOT/Makefile" | LC_ALL=C sort -u)}")
  make_phony_names=("${(@f)$(awk '/^\.PHONY:/ { for (i = 2; i <= NF; i++) print $i }' "$ROOT/Makefile" | LC_ALL=C sort -u)}")
fi

for target in "${make_target_names[@]}"; do
  [[ -n "$target" ]] || continue
  make_targets[$target]=1
done
for target in "${make_phony_names[@]}"; do
  [[ -n "$target" ]] || continue
  make_phony_targets[$target]=1
done

make_target_failed=0
make_target_checked=0
for target in "${make_target_names[@]}"; do
  [[ -n "$target" ]] || continue
  make_target_checked=$(( make_target_checked + 1 ))
  if [[ -z "${make_phony_targets[$target]:-}" ]]; then
    make_target_failed=1
    echo "makefile target check failed: target $target is missing from .PHONY" >&2
  fi
done
for target in "${make_phony_names[@]}"; do
  [[ -n "$target" ]] || continue
  if [[ -z "${make_targets[$target]:-}" ]]; then
    make_target_failed=1
    echo "makefile target check failed: .PHONY references missing target $target" >&2
  fi
done

if (( make_target_failed != 0 )); then
  exit 1
fi

make_recipe_contains() {
  local target="$1"
  local needle="$2"

  [[ -f "$ROOT/Makefile" ]] || return 1
  awk -v target="${target}:" -v needle="$needle" '
    $0 == target {
      in_target = 1
      next
    }
    in_target && /^[A-Za-z0-9_.-]+:/ {
      exit
    }
    in_target && index($0, needle) {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$ROOT/Makefile"
}

canonical_make_target_failed=0
canonical_make_target_checked=0
if [[ -n "${make_targets[lint]:-}" ]]; then
  canonical_make_target_checked=$(( canonical_make_target_checked + 1 ))
fi
if [[ -n "${make_targets[lint]:-}" ]] && ! make_recipe_contains lint "./scripts/lint_contracts.sh"; then
  canonical_make_target_failed=1
  echo "canonical make target check failed: target lint must invoke ./scripts/lint_contracts.sh" >&2
fi
if [[ -n "${make_targets[compile]:-}" ]]; then
  canonical_make_target_checked=$(( canonical_make_target_checked + 1 ))
fi
if [[ -n "${make_targets[compile]:-}" ]] && ! make_recipe_contains compile "./scripts/compile_contracts.sh"; then
  canonical_make_target_failed=1
  echo "canonical make target check failed: target compile must invoke ./scripts/compile_contracts.sh" >&2
fi

if (( canonical_make_target_failed != 0 )); then
  exit 1
fi

script_target_failed=0
script_target_checked=0
for source_script in "$ROOT/scripts"/*.sh; do
  [[ -f "$source_script" ]] || continue
  line_no=0
  in_local_acceptance_targets=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$(( line_no + 1 ))
    [[ "$line" =~ '^[[:space:]]*#' ]] && continue

    if (( in_local_acceptance_targets != 0 )); then
      if [[ "$line" =~ '^[[:space:]]*\)' ]]; then
        in_local_acceptance_targets=0
        continue
      fi
      if [[ "$line" =~ '^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*$' ]]; then
        target="$match[1]"
        script_target_checked=$(( script_target_checked + 1 ))
        if [[ -z "${make_targets[$target]:-}" ]]; then
          script_target_failed=1
          echo "script make target check failed: ${source_script#$ROOT/}:$line_no local_acceptance_targets references missing make target $target" >&2
        fi
      fi
      continue
    fi

    if [[ "$line" =~ '^[[:space:]]*local_acceptance_targets=\(' ]]; then
      in_local_acceptance_targets=1
      continue
    fi

    if [[ "$line" =~ '^[[:space:]]*([A-Za-z0-9_]+=[^[:space:]]+[[:space:]]+)*run_target[[:space:]]+([A-Za-z0-9_.-]+)' ]]; then
      target="$match[2]"
      script_target_checked=$(( script_target_checked + 1 ))
      if [[ -z "${make_targets[$target]:-}" ]]; then
        script_target_failed=1
        echo "script make target check failed: ${source_script#$ROOT/}:$line_no run_target references missing make target $target" >&2
      fi
    fi

    if [[ "$line" =~ '^[[:space:]]*([A-Za-z0-9_]+=[^[:space:]]+[[:space:]]+)*make[[:space:]]+-C[[:space:]]+[^[:space:]]+[[:space:]]+([A-Za-z0-9_.-]+)' ]]; then
      target="$match[2]"
      script_target_checked=$(( script_target_checked + 1 ))
      if [[ -z "${make_targets[$target]:-}" ]]; then
        script_target_failed=1
        echo "script make target check failed: ${source_script#$ROOT/}:$line_no make command references missing make target $target" >&2
      fi
    fi
  done < "$source_script"
done

if (( script_target_failed != 0 )); then
  exit 1
fi

doc_paths=("${(@f)$(find "$ROOT" \
  \( -path "$ROOT/.git" \
    -o -path "$ROOT/artifacts" \
    -o -path "$ROOT/deployments" \
    -o -path "$ROOT/node_modules" \
    -o -path "$ROOT/tmp" \
    -o -path "$ROOT/target" \
  \) -prune \
  -o -type f -name '*.md' -print | LC_ALL=C sort)}")

doc_failed=0
doc_checked=0
doc_npm_failed=0
doc_npm_checked=0
doc_zsh_noexec_checked=0

check_documented_make_targets() {
  local doc_path="$1"
  local line_no="$2"
  local context="$3"
  local text="$4"
  local scan matched_command command_tail token target skip_next
  typeset -a command_tokens

  scan="$text"
  while [[ "$scan" =~ '(^|[;&|[:space:]`])([A-Za-z0-9_]+=[^[:space:]`]+[[:space:]]+)*(make)([[:space:]]+[^;&|`]*)' ]]; do
    matched_command="$MATCH"
    command_tail="$match[4]"
    scan="${scan#*"$matched_command"}"
    command_tokens=("${(@f)$(printf '%s\n' "$command_tail" | tr '[:space:]' '\n')}")
    skip_next=0

    for token in "${command_tokens[@]}"; do
      [[ -n "$token" ]] || continue

      if (( skip_next != 0 )); then
        skip_next=0
        continue
      fi

      case "$token" in
        -C)
          skip_next=1
          continue
          ;;
        -*|*=*)
          continue
          ;;
      esac

      [[ "$token" =~ '^[A-Za-z0-9_.-]+$' ]] || continue
      target="$token"
      doc_checked=$(( doc_checked + 1 ))
      if [[ -z "${make_targets[$target]:-}" ]]; then
        doc_failed=1
        echo "documented command check failed: ${doc_path#$ROOT/}:$line_no $context references missing make target $target" >&2
      fi
    done
  done
}

check_documented_npm_scripts() {
  local doc_path="$1"
  local line_no="$2"
  local context="$3"
  local text="$4"
  local scan matched_command script_name

  scan="$text"
  while [[ "$scan" =~ '(^|[;&|[:space:]`])npm[[:space:]]+run[[:space:]]+([A-Za-z0-9:_-]+)' ]]; do
    matched_command="$MATCH"
    script_name="$match[2]"
    scan="${scan#*"$matched_command"}"
    doc_npm_checked=$(( doc_npm_checked + 1 ))
    if [[ -z "${package_scripts[$script_name]:-}" ]]; then
      doc_npm_failed=1
      echo "documented npm script check failed: ${doc_path#$ROOT/}:$line_no $context references missing package script $script_name" >&2
    fi
  done
}

for doc_path in "${doc_paths[@]}"; do
  [[ -n "$doc_path" ]] || continue
  in_fence=0
  line_no=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$(( line_no + 1 ))
    if [[ "$line" =~ '^```' ]]; then
      if (( in_fence == 0 )); then
        in_fence=1
      else
        in_fence=0
      fi
      continue
    fi
    if (( in_fence != 0 )); then
      check_documented_make_targets "$doc_path" "$line_no" "fenced command" "$line"
      check_documented_npm_scripts "$doc_path" "$line_no" "fenced command" "$line"
      continue
    fi

    doc_line="$line"
    while [[ "$doc_line" =~ '`([^`]*make[[:space:]][^`]*)`' ]]; do
      inline_command="$match[1]"
      matched_command="$MATCH"
      doc_line="${doc_line#*"$matched_command"}"
      check_documented_make_targets "$doc_path" "$line_no" "inline command" "$inline_command"
    done

    doc_line="$line"
    while [[ "$doc_line" =~ '`([^`]*npm[[:space:]]+run[[:space:]][^`]*)`' ]]; do
      inline_command="$match[1]"
      matched_command="$MATCH"
      doc_line="${doc_line#*"$matched_command"}"
      check_documented_npm_scripts "$doc_path" "$line_no" "inline command" "$inline_command"
    done
  done < "$doc_path"
done

if (( doc_failed != 0 )); then
  exit 1
fi
if (( doc_npm_failed != 0 )); then
  exit 1
fi

doc_zsh_noexec_output="$tmp_dir/doc-zsh-noexec.out"
doc_zsh_noexec_stderr="$tmp_dir/doc-zsh-noexec.stderr"
if python3 - "$ROOT" "${doc_paths[@]}" >"$doc_zsh_noexec_output" 2>"$doc_zsh_noexec_stderr" <<'PY'
import os
import re
import shlex
import sys

root = sys.argv[1]
doc_paths = sys.argv[2:]
inline_command_pattern = re.compile(r"`([^`]*zsh\s+-n[^`]*)`")
zsh_noexec_pattern = re.compile(r"(?<![A-Za-z0-9_./-])zsh\s+-n(?P<tail>[^;&|`]*)")


def rel(path):
    return os.path.relpath(path, root)


def check_text(path, line_no, context, text):
    errors = []
    checked = 0
    for match in zsh_noexec_pattern.finditer(text):
        command = ("zsh -n" + match.group("tail")).strip()
        try:
            tokens = shlex.split(command)
        except ValueError:
            continue
        if len(tokens) < 2 or tokens[0] != "zsh" or tokens[1] != "-n":
            continue

        scripts = []
        for token in tokens[2:]:
            if token == "--" or token.startswith("-"):
                continue
            if token.endswith(".sh"):
                scripts.append(token)

        if scripts:
            checked += 1
        if len(scripts) > 1:
            errors.append(
                "documented zsh no-exec check failed: "
                f"{rel(path)}:{line_no} {context} uses zsh -n with multiple script operands: "
                f"{command}; use make check-shell-syntax or separate zsh -n invocations"
            )
    return checked, errors


total_checked = 0
all_errors = []
for doc_path in doc_paths:
    if not doc_path:
        continue
    in_fence = False
    try:
        with open(doc_path, encoding="utf-8") as handle:
            for line_no, raw_line in enumerate(handle, 1):
                line = raw_line.rstrip("\n")
                if line.startswith("```"):
                    in_fence = not in_fence
                    continue
                if in_fence:
                    checked, errors = check_text(doc_path, line_no, "fenced command", line)
                    total_checked += checked
                    all_errors.extend(errors)
                    continue

                for inline_match in inline_command_pattern.finditer(line):
                    checked, errors = check_text(
                        doc_path,
                        line_no,
                        "inline command",
                        inline_match.group(1),
                    )
                    total_checked += checked
                    all_errors.extend(errors)
    except UnicodeDecodeError as error:
        all_errors.append(
            f"documented zsh no-exec check failed: {rel(doc_path)} could not be read as UTF-8: {error}"
        )

if all_errors:
    for error in all_errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print(total_checked)
PY
then
  doc_zsh_noexec_checked="$(cat "$doc_zsh_noexec_output")"
else
  cat "$doc_zsh_noexec_stderr" >&2
  exit 1
fi

doc_repo_failed=0
doc_repo_checked=0
for doc_path in "${doc_paths[@]}"; do
  [[ -n "$doc_path" ]] || continue
  line_no=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$(( line_no + 1 ))
    doc_line="$line"

    while [[ "$doc_line" =~ '(^|[^A-Za-z0-9_./-])((scripts|tests)/[A-Za-z0-9_./-]+\.(sh|py|js))' ]]; do
      ref="$match[2]"
      matched_ref="$MATCH"
      doc_repo_checked=$(( doc_repo_checked + 1 ))
      doc_line="${doc_line#*"$matched_ref"}"

      if [[ ! -f "$ROOT/$ref" ]]; then
        doc_repo_failed=1
        echo "documented repo path check failed: ${doc_path#$ROOT/}:$line_no references missing $ref" >&2
      fi
    done
  done < "$doc_path"
done

if (( doc_repo_failed != 0 )); then
  exit 1
fi

doc_evidence_failed=0
doc_evidence_checked=0
doc_evidence_output="$tmp_dir/doc-evidence.out"
doc_evidence_stderr="$tmp_dir/doc-evidence.stderr"
if python3 - "$ROOT" "${doc_paths[@]}" >"$doc_evidence_output" 2>"$doc_evidence_stderr" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
doc_paths = [Path(path).resolve() for path in sys.argv[2:] if path]
errors = []
checked = 0

repo_path_pattern = re.compile(
    r"`((?:deployments/(?:local|testnet|production)/[^`\s]+\.json)"
    r"|(?:artifacts/telemetry/[^`\s]+\.json))`"
)
timestamped_deployment_pattern = re.compile(
    r"^deployments/(?:local|testnet|production)/[^/]+\.[0-9]{8}T[0-9]{6}Z\.json$"
)
unsupported_path_chars = set("<>$*{}")

for doc_path in doc_paths:
    if not doc_path.is_file():
        continue
    try:
        source = doc_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        errors.append(f"documented evidence path check failed: {doc_path.relative_to(root).as_posix()} could not be read as UTF-8: {error}")
        continue

    for line_no, line in enumerate(source.splitlines(), 1):
        for match in repo_path_pattern.finditer(line):
            ref = match.group(1)
            if any(char in ref for char in unsupported_path_chars):
                continue
            if ref.startswith("deployments/") and not timestamped_deployment_pattern.match(ref):
                continue

            checked += 1
            ref_path = root / ref
            if not ref_path.is_file():
                errors.append(
                    "documented evidence path check failed: "
                    f"{doc_path.relative_to(root).as_posix()}:{line_no} references missing {ref}"
                )

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  doc_evidence_checked="$(cat "$doc_evidence_output")"
else
  cat "$doc_evidence_stderr" >&2
  exit 1
fi

release_status_doc_checked=0
release_status_doc_output="$tmp_dir/release-status-docs.out"
release_status_doc_stderr="$tmp_dir/release-status-docs.stderr"
if [[ "$release_status_doc_freshness_deferred" == "1" ]]; then
  release_status_doc_checked="deferred for status-doc closeout preparation"
elif python3 - "$ROOT" >"$release_status_doc_output" 2>"$release_status_doc_stderr" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
local_status_docs = [
    root / "docs" / "release" / "smart_contract_production_audit.md",
    root / "docs" / "release" / "production_readiness_checklist.md",
]
taira_status_docs = [
    root / "docs" / "release" / "smart_contract_production_audit.md",
    root / "docs" / "release" / "production_readiness_checklist.md",
    root / "docs" / "release" / "taira_devex_critique.md",
]
production_status_docs = [
    root / "docs" / "release" / "smart_contract_production_audit.md",
    root / "docs" / "release" / "production_readiness_checklist.md",
]
local_evidence = [
    ("retained local chain evidence generated_at", root / "deployments" / "local" / "chain.latest.json"),
    ("retained local deploy evidence generated_at", root / "deployments" / "local" / "deploy.latest.json"),
    ("retained local contracts evidence generated_at", root / "deployments" / "local" / "contracts.latest.json"),
    ("retained local smoke evidence generated_at", root / "deployments" / "local" / "smoke.latest.json"),
]
taira_evidence = [
    ("Taira chain evidence generated_at", root / "deployments" / "testnet" / "chain.latest.json"),
    ("Taira preflight evidence generated_at", root / "deployments" / "testnet" / "preflight.latest.json"),
    ("Taira nested-call probe evidence generated_at", root / "deployments" / "testnet" / "nested_call_probe.latest.json"),
    ("Taira deploy evidence generated_at", root / "deployments" / "testnet" / "deploy.latest.json"),
    ("Taira contracts evidence generated_at", root / "deployments" / "testnet" / "contracts.latest.json"),
    ("Taira RWA evidence generated_at", root / "deployments" / "testnet" / "rwa_compliance.latest.json"),
    ("Taira readonly smoke evidence generated_at", root / "deployments" / "testnet" / "smoke.readonly.latest.json"),
    ("Taira signed smoke evidence generated_at", root / "deployments" / "testnet" / "smoke.latest.json"),
    ("Taira contract-console evidence generated_at", root / "deployments" / "testnet" / "contract_console_smoke.latest.json"),
    ("Taira readonly trader evidence generated_at", root / "deployments" / "testnet" / "trader_readonly.latest.json"),
    ("Taira signed trader evidence generated_at", root / "deployments" / "testnet" / "trader.latest.json"),
    ("Taira trader API evidence generated_at", root / "deployments" / "testnet" / "trader_api_bundle.latest.json"),
]
production_evidence = [
    ("production chain evidence generated_at", root / "deployments" / "production" / "chain.latest.json"),
    ("production preflight evidence generated_at", root / "deployments" / "production" / "preflight.latest.json"),
    ("production nested-call probe evidence generated_at", root / "deployments" / "production" / "nested_call_probe.latest.json"),
    ("production deploy evidence generated_at", root / "deployments" / "production" / "deploy.latest.json"),
    ("production contracts evidence generated_at", root / "deployments" / "production" / "contracts.latest.json"),
    ("production RWA evidence generated_at", root / "deployments" / "production" / "rwa_compliance.latest.json"),
    ("production readonly smoke evidence generated_at", root / "deployments" / "production" / "smoke.readonly.latest.json"),
    ("production signed smoke evidence generated_at", root / "deployments" / "production" / "smoke.latest.json"),
    ("production contract-console evidence generated_at", root / "deployments" / "production" / "contract_console_smoke.latest.json"),
    ("production readonly trader evidence generated_at", root / "deployments" / "production" / "trader_readonly.latest.json"),
    ("production signed trader evidence generated_at", root / "deployments" / "production" / "trader.latest.json"),
    ("production trader API evidence generated_at", root / "deployments" / "production" / "trader_api_bundle.latest.json"),
]
primitive_telemetry_ref = "artifacts/telemetry/defi_2026_primitives_latest.json"
primitive_telemetry_path = root / primitive_telemetry_ref


def rel(path):
    return path.relative_to(root).as_posix()


def generated_at(path):
    if not path.is_file():
        return None
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    value = data.get("generated_at")
    if isinstance(value, str) and value:
        return value
    return None


def load_json(path):
    if not path.is_file():
        return None
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None


errors = []
checked = 0
if all(doc.is_file() for doc in local_status_docs):
    local_requirements = []
    for label, path in local_evidence:
        value = generated_at(path)
        if value is not None:
            local_requirements.append((label, value))

    telemetry_generated_at = generated_at(primitive_telemetry_path)
    if telemetry_generated_at is not None:
        local_requirements.append(("primitive telemetry generated_at", telemetry_generated_at))
        local_requirements.append(("primitive telemetry path", primitive_telemetry_ref))

    if local_requirements:
        for doc_path in local_status_docs:
            try:
                source = doc_path.read_text(encoding="utf-8")
            except UnicodeDecodeError as error:
                errors.append(
                    f"release status doc freshness check failed: {rel(doc_path)} could not be read as UTF-8: {error}"
                )
                continue

            for label, value in local_requirements:
                checked += 1
                if value not in source:
                    errors.append(
                        "release status doc freshness check failed: "
                        f"{rel(doc_path)} does not mention current {label} {value}"
                    )

            for line_no, line in enumerate(source.splitlines(), 1):
                if "primitive telemetry" not in line or "`artifacts/telemetry/" not in line:
                    continue
                checked += 1
                if primitive_telemetry_ref not in line:
                    errors.append(
                        "release status doc freshness check failed: "
                        f"{rel(doc_path)}:{line_no} mentions primitive telemetry with a non-canonical telemetry path; "
                        f"expected {primitive_telemetry_ref}"
                    )

if all(doc.is_file() for doc in taira_status_docs):
    taira_requirements = []
    for label, path in taira_evidence:
        value = generated_at(path)
        if value is not None:
            taira_requirements.append((label, value))

    if taira_requirements:
        for doc_path in taira_status_docs:
            try:
                source = doc_path.read_text(encoding="utf-8")
            except UnicodeDecodeError as error:
                errors.append(
                    f"release status doc freshness check failed: {rel(doc_path)} could not be read as UTF-8: {error}"
                )
                continue

            for label, value in taira_requirements:
                checked += 1
                if value not in source:
                    errors.append(
                        "release status doc freshness check failed: "
                        f"{rel(doc_path)} does not mention current {label} {value}"
                    )

if all(doc.is_file() for doc in production_status_docs):
    production_requirements = []
    for label, path in production_evidence:
        value = generated_at(path)
        if value is not None:
            production_requirements.append((label, value))

    production_preflight = load_json(root / "deployments" / "production" / "preflight.latest.json")
    if isinstance(production_preflight, dict):
        chain = production_preflight.get("chain")
        if isinstance(chain, dict) and chain.get("saved_snapshot_exists") is False:
            production_requirements.append(
                ("production chain evidence absence", "no saved production `chain.latest.json`")
            )
        nested_probe = production_preflight.get("nested_call_probe")
        if isinstance(nested_probe, dict) and nested_probe.get("latest_exists") is False:
            production_requirements.append(
                ("production nested-call probe absence", "nested_call_probe.latest_exists: false")
            )

    if production_requirements:
        for doc_path in production_status_docs:
            try:
                source = doc_path.read_text(encoding="utf-8")
            except UnicodeDecodeError as error:
                errors.append(
                    f"release status doc freshness check failed: {rel(doc_path)} could not be read as UTF-8: {error}"
                )
                continue

            for label, value in production_requirements:
                checked += 1
                if value not in source:
                    errors.append(
                        "release status doc freshness check failed: "
                        f"{rel(doc_path)} does not mention current {label} {value}"
                    )

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  release_status_doc_checked="$(cat "$release_status_doc_output")"
else
  cat "$release_status_doc_stderr" >&2
  exit 1
fi

doc_markdown_link_checked=0
doc_markdown_link_output="$tmp_dir/doc-markdown-links.out"
doc_markdown_link_stderr="$tmp_dir/doc-markdown-links.stderr"
if python3 - "$ROOT" "${doc_paths[@]}" >"$doc_markdown_link_output" 2>"$doc_markdown_link_stderr" <<'PY'
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

root = Path(sys.argv[1]).resolve()
doc_paths = [Path(path).resolve() for path in sys.argv[2:] if path]
errors = []
checked = 0

inline_link_pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
external_prefixes = (
    "#",
    "data:",
    "http://",
    "https://",
    "mailto:",
    "tel:",
    "//",
)
unsupported_path_chars = set("<>$*{}")

def rel(path):
    return path.relative_to(root).as_posix()

def link_target(raw):
    value = raw.strip()
    if not value:
        return None
    if value.startswith("<") and ">" in value:
        return value[1:value.index(">")].strip()
    return value.split()[0]

for doc_path in doc_paths:
    if not doc_path.is_file():
        continue
    try:
        source = doc_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        errors.append(f"documented markdown link check failed: {rel(doc_path)} could not be read as UTF-8: {error}")
        continue

    in_fence = False
    for line_no, line in enumerate(source.splitlines(), 1):
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        for match in inline_link_pattern.finditer(line):
            target = link_target(match.group(1))
            if target is None:
                continue
            lowered = target.lower()
            if lowered.startswith(external_prefixes):
                continue

            split = urlsplit(target)
            path = unquote(split.path)
            if not path or any(char in path for char in unsupported_path_chars):
                continue

            candidate = root / path.lstrip("/") if path.startswith("/") else doc_path.parent / path
            resolved = candidate.resolve(strict=False)
            try:
                resolved.relative_to(root)
            except ValueError:
                continue

            checked += 1
            if not resolved.exists():
                errors.append(
                    "documented markdown link check failed: "
                    f"{rel(doc_path)}:{line_no} references missing {target}"
                )

print(checked)
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  doc_markdown_link_checked="$(cat "$doc_markdown_link_output")"
else
  cat "$doc_markdown_link_stderr" >&2
  exit 1
fi

generated_evidence_path_checked=0
generated_evidence_path_output="$tmp_dir/generated-evidence-paths.out"
generated_evidence_path_stderr="$tmp_dir/generated-evidence-paths.stderr"
if python3 - "$ROOT" >"$generated_evidence_path_output" 2>"$generated_evidence_path_stderr" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
candidate_patterns = (
    "deployments/**/*.json",
    "artifacts/telemetry/*.json",
)
local_path_pattern = re.compile(
    r"(?:file:(?://(?:localhost)?)?)?"
    r"(/Users/|/private/var/folders/|/private/tmp/|/var/folders/|/tmp/)"
)
errors = []
checked = 0
seen = set()
paths = []

for pattern in candidate_patterns:
    for path in root.glob(pattern):
        if not path.is_file():
            continue
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        paths.append(resolved)

def rel(path):
    return path.relative_to(root).as_posix()

def path_class(match):
    prefix = "file URI " if match.group(0).startswith("file:") else ""
    return prefix + match.group(1)

for path in sorted(paths):
    checked += 1
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        errors.append(f"generated evidence path hygiene failed: {rel(path)} could not be read as UTF-8: {error}")
        continue

    for line_no, line in enumerate(source.splitlines(), 1):
        match = local_path_pattern.search(line)
        if match is None:
            continue
        errors.append(
            "generated evidence path hygiene failed: "
            f"{rel(path)}:{line_no} contains {path_class(match)}"
        )
        break

print(checked)
if errors:
    visible_errors = errors[:20]
    if len(errors) > len(visible_errors):
        visible_errors.append(
            f"generated evidence path hygiene failed: {len(errors) - len(visible_errors)} additional files contain local paths"
        )
    print("\n".join(visible_errors), file=sys.stderr)
    raise SystemExit(1)
PY
then
  generated_evidence_path_checked="$(cat "$generated_evidence_path_output")"
else
  cat "$generated_evidence_path_stderr" >&2
  exit 1
fi

generated_evidence_redaction_checked=0
generated_evidence_redaction_output="$tmp_dir/generated-evidence-redaction.out"
generated_evidence_redaction_stderr="$tmp_dir/generated-evidence-redaction.stderr"
if SORASWAP_ROOT="$ROOT" zsh "$SCRIPT_ROOT/scripts/redact_generated_evidence.sh" --check \
  >"$generated_evidence_redaction_output" 2>"$generated_evidence_redaction_stderr"
then
  generated_evidence_redaction_checked="$(
    sed -n 's/^generated evidence redaction check: inspected \([0-9][0-9]*\) JSON artifacts; pending 0$/\1/p' \
      "$generated_evidence_redaction_output"
  )"
  if [[ -z "$generated_evidence_redaction_checked" ]]; then
    cat "$generated_evidence_redaction_output" >&2
    echo "generated evidence redaction check failed: unexpected check output" >&2
    exit 1
  fi
else
  cat "$generated_evidence_redaction_stderr" >&2
  exit 1
fi

typeset -A sourced_shell_refs
metadata_failed=0
metadata_checked=0

for source_script in "${shell_scripts[@]}"; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ '^[[:space:]]*(source|\.)[[:space:]]+' ]] || continue

    ref_line="$line"
    while [[ "$ref_line" =~ '(\./(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$SORASWAP_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{SORASWAP_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$SCRIPT_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{SCRIPT_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$REPO_ROOT/(scripts|tests)/[A-Za-z0-9_./-]+\.sh|\$\{REPO_ROOT\}/(scripts|tests)/[A-Za-z0-9_./-]+\.sh)' ]]; do
      ref="$MATCH"
      rel_ref="$(normalize_shell_script_ref "$ref")"
      ref_line="${ref_line#*"$ref"}"
      sourced_shell_refs[$rel_ref]=1
    done
  done < "$source_script"
done

for script_path in "${shell_scripts[@]}"; do
  rel_script="${script_path#$ROOT/}"
  first_line="$(sed -n '1p' "$script_path")"
  metadata_checked=$(( metadata_checked + 1 ))

  if [[ "$first_line" != "#!/bin/zsh" ]]; then
    metadata_failed=1
    echo "shell metadata check failed: $rel_script must start with #!/bin/zsh" >&2
  fi

  if [[ -x "$script_path" ]]; then
    if ! sed -n '1,8p' "$script_path" | grep -q '^set -euo pipefail$'; then
      metadata_failed=1
      echo "shell metadata check failed: $rel_script executable entrypoints must enable set -euo pipefail near the top" >&2
    fi
  elif [[ -z "${sourced_shell_refs[$rel_script]:-}" ]]; then
    metadata_failed=1
    echo "shell metadata check failed: $rel_script is non-executable and is not sourced by a repo shell entrypoint" >&2
  fi
done

if (( metadata_failed != 0 )); then
  exit 1
fi

echo "shell syntax ok: $checked scripts checked"
echo "python syntax ok: $python_checked files checked"
echo "javascript syntax ok: $javascript_checked files checked"
echo "contract sources ok: $contract_source_checked files checked"
echo "migration register ok: $migration_register_checked rows checked"
echo "shell metadata ok: $metadata_checked shell scripts checked"
echo "shell surface ok: $surface_checked Makefile shell references checked"
echo "shell references ok: $script_ref_checked production script references checked"
echo "makefile repo paths ok: $make_repo_ref_checked Python/JS references checked"
echo "unittest discovery ok: $unittest_discover_checked Makefile unittest patterns checked"
echo "npm scripts ok: $npm_script_ref_checked Makefile npm run references checked; $package_script_ref_checked package npm run references checked"
echo "package script commands ok: $package_script_command_checked package command references checked"
echo "package script paths ok: $package_script_file_ref_checked package file references checked"
echo "package lock ok: $package_lock_checked package-lock root manifests checked"
echo "root configs ok: $root_config_checked root project configs checked"
echo "ui asset refs ok: $ui_asset_ref_checked HTML/CSS asset references checked"
echo "ui DOM refs ok: $ui_dom_ref_checked JavaScript selector references checked"
echo "repo references ok: $script_repo_ref_checked production Python/JS references checked"
echo "make targets ok: $make_target_checked PHONY targets checked"
echo "canonical make targets ok: $canonical_make_target_checked wrapper entrypoints checked"
echo "script make targets ok: $script_target_checked literal make targets checked"
echo "documented commands ok: $doc_checked make command targets checked"
echo "documented npm scripts ok: $doc_npm_checked npm run script references checked"
echo "documented zsh no-exec ok: $doc_zsh_noexec_checked single-script commands checked"
echo "documented repo paths ok: $doc_repo_checked script/test references checked"
echo "documented evidence paths ok: $doc_evidence_checked timestamped deployment/telemetry references checked"
echo "release status docs ok: $release_status_doc_checked current evidence mentions checked"
echo "documented markdown links ok: $doc_markdown_link_checked repo-local links checked"
echo "generated evidence paths ok: $generated_evidence_path_checked generated JSON artifacts checked"
echo "generated evidence redaction ok: $generated_evidence_redaction_checked generated JSON artifacts checked"
echo "repo temporary files ok: no stale deploy manifests found"
