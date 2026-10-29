# shellcheck shell=bash
# Shared helpers for scenarios/run.sh and the optional per-scenario inject/cleanup
# hooks. Sourced, never executed. Mirrors cluster/install.sh so the two scripts
# read as one toolchain (ISI-6846 §0).
#
# Exposes:
#   log/ok/warn/err  — coloured, prefixed status lines (stdout / stderr)
#   SCENARIOS_DIR    — absolute path to the scenarios/ tree
#   FAULT_NS         — the single infra blast-radius namespace (workshop-faults)
#   NS_ALLOWLIST     — the only namespaces run.sh / a hook may ever touch
#   resolve_id       — short id (01) or dir name -> canonical scenario dir name
#   scenario_dir     — canonical dir name -> absolute path
#   frontmatter_get  — read a key from an expected-diagnosis.md YAML front matter
#   guard_namespaces — fail-closed allowlist check over a manifest's namespaces
#   require_cluster  — kubectl reachable, else exit 2

log()  { printf '\033[1;34m[scenario]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }

# Resolve the scenarios/ root from this file's location (lib/common.sh -> ..).
SCENARIOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The single infra blast-radius namespace. Cleanup deletes exactly this ns.
FAULT_NS="workshop-faults"

# Fail-closed allowlist (ISI-6846 §2 / §5). A manifest or hook may reference ONLY
# these namespaces. otel-demo is owned by the Platform install (ISI-6847); scenario
# #12 flips a fault inside it but must never delete it.
NS_ALLOWLIST=("workshop-faults" "otel-demo")

# resolve_id <id> -> echoes the canonical scenario directory name, or returns 1.
# Accepts a numeric prefix ("01", "12") or the full dir name ("01-crashloopbackoff").
resolve_id() {
  local want="$1" match=() d name
  for d in "${SCENARIOS_DIR}"/[0-9][0-9]-*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ "$name" = "$want" ] || [ "${name%%-*}" = "$want" ]; then
      match+=("$name")
    fi
  done
  case "${#match[@]}" in
    1) printf '%s\n' "${match[0]}"; return 0 ;;
    0) return 1 ;;
    *) err "id '${want}' is ambiguous: ${match[*]}"; return 1 ;;
  esac
}

scenario_dir() { printf '%s/%s\n' "${SCENARIOS_DIR}" "$1"; }

# frontmatter_get <file> <key> -> echoes the value of a top-level YAML front-matter
# key (the first `--- ... ---` block). Minimal parser: enough for our fixed schema.
frontmatter_get() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line ~ "^" k "[ \t]*:") {
        sub("^" k "[ \t]*:[ \t]*", "", line)
        print line
        exit
      }
    }
  ' "$file"
}

# guard_namespaces <manifest.yaml> — fail-closed allowlist check. Extracts every
# `namespace:` value and rejects the whole apply (exit 2) if any value is outside
# NS_ALLOWLIST. Objects with NO namespace are also rejected: the contract requires
# every infra object to pin namespace: workshop-faults explicitly (ISI-6846 §1.1).
guard_namespaces() {
  local manifest="$1" bad=0 found=0 val
  # Count object separators to know how many docs we expect a namespace for.
  while IFS= read -r val; do
    found=1
    local allowed=0 ns
    for ns in "${NS_ALLOWLIST[@]}"; do
      [ "$val" = "$ns" ] && allowed=1 && break
    done
    if [ "$allowed" -ne 1 ]; then
      err "namespace guard: manifest references forbidden namespace '${val}' (allowlist: ${NS_ALLOWLIST[*]})"
      bad=1
    fi
  done < <(grep -E '^[[:space:]]*namespace:[[:space:]]*' "$manifest" \
             | sed -E 's/^[[:space:]]*namespace:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]*(#.*)?$//')
  if [ "$found" -ne 1 ]; then
    err "namespace guard: manifest '${manifest}' pins no namespace — every object must set 'namespace: ${FAULT_NS}' explicitly"
    return 1
  fi
  return "$bad"
}

require_cluster() {
  kubectl cluster-info >/dev/null 2>&1 && return 0
  err "cluster not reachable — run .devcontainer/postCreate.sh / cluster/install.sh first"
  return 1
}
