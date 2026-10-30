#!/usr/bin/env bash
# scenarios/run.sh — the single entrypoint for the fault-injection diagnostic
# module (ISI-6836 / contract ISI-6846). Injects a real, isolated Kubernetes
# fault the module-02 `sre-agent` then diagnoses; cleans it up with one command.
#
# Usage:
#   bash scenarios/run.sh list                 # enumerate scenarios
#   bash scenarios/run.sh inject  <id>         # apply the fault (id: 01 or 01-crashloopbackoff)
#   bash scenarios/run.sh cleanup <id>         # remove the fault (idempotent)
#
# Safety (ISI-6846 §2/§5): infra faults live ONLY in the `workshop-faults`
# namespace; a fail-closed allowlist rejects any manifest/hook that references
# kagent, dynatrace, agent-sandbox, kube-system, etc. Cleanup deletes exactly
# `workshop-faults` (infra) or flips the scenario fault back (#12) — never the
# platform. See scenarios/README.md.
#
# Exit codes (the contract downstream grades against — ISI-6846 §2):
#   0 success · 1 usage error · 2 precondition failure · 3 runtime failure
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: bash scenarios/run.sh <command> [id]
  list             enumerate every scenario (id, title, app-dep tag)
  inject  <id>     inject the fault into the ${FAULT_NS} namespace
  cleanup <id>     remove the fault (idempotent)

id is a numeric prefix (01, 12) or a full dir name (01-crashloopbackoff).
EOF
}

# ---------------------------------------------------------------------------
cmd_list() {
  local d name title reqs tag
  for d in "${SCENARIOS_DIR}"/[0-9][0-9]-*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    title=""
    [ -f "${d}prompt.md" ] && title="$(grep -m1 -E '^#[[:space:]]+' "${d}prompt.md" | sed -E 's/^#[[:space:]]+//')"
    tag=""
    if [ -f "${d}expected-diagnosis.md" ]; then
      reqs="$(frontmatter_get "${d}expected-diagnosis.md" requires)"
      case "$reqs" in *astroshop-lite*) tag="  [app-dep: astroshop-lite]";; esac
    fi
    printf '  %-22s %s%s\n' "$name" "${title:-<no prompt.md>}" "$tag"
  done
}

# ---------------------------------------------------------------------------
cmd_inject() {
  local id="${1:-}"
  [ -n "$id" ] || { err "inject needs a scenario id"; usage; exit 1; }
  local name; name="$(resolve_id "$id")" || { err "unknown/ambiguous scenario id: ${id}"; exit 1; }
  local dir; dir="$(scenario_dir "$name")"

  require_cluster || exit 2

  # App-dependency gate (keeps #12 skippable on the minimum tier — ISI-6846 §2.4).
  if [ -f "${dir}/expected-diagnosis.md" ]; then
    local reqs; reqs="$(frontmatter_get "${dir}/expected-diagnosis.md" requires)"
    case "$reqs" in
      *astroshop-lite*)
        if ! kubectl get ns astroshop-lite >/dev/null 2>&1; then
          err "scenario '${name}' requires the astroshop-lite app, which is not deployed."
          err "Deploy just the demo (platform stack already installed), then retry:"
          err "  deployOtelDemoLight"
          exit 2
        fi
        ;;
    esac
  fi

  if [ -x "${dir}/inject.sh" ] || [ -f "${dir}/inject.sh" ]; then
    # Override path (#12): the hook owns its own guard + apply.
    log "inject ${name}: running scenario hook inject.sh"
    bash "${dir}/inject.sh" || { err "inject hook failed for ${name}"; exit 3; }
  else
    # Default path (infra 01-03): guarded kubectl apply of manifests.yaml.
    [ -f "${dir}/manifests.yaml" ] || { err "scenario '${name}' has no manifests.yaml and no inject.sh"; exit 1; }
    guard_namespaces "${dir}/manifests.yaml" || exit 2
    log "inject ${name}: ensuring namespace ${FAULT_NS}"
    kubectl create ns "${FAULT_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    log "inject ${name}: applying manifests.yaml"
    kubectl apply -f "${dir}/manifests.yaml" || { err "kubectl apply failed for ${name}"; exit 3; }
  fi

  ok "scenario ${name} injected"
  echo "SCENARIO_INJECTED name=${name}"
  log "next: read the prompt ->  ${dir}/prompt.md"
  log "watch it break ->  kubectl get pods -n ${FAULT_NS} -w"
}

# ---------------------------------------------------------------------------
cmd_cleanup() {
  local id="${1:-}"
  [ -n "$id" ] || { err "cleanup needs a scenario id"; usage; exit 1; }
  local name; name="$(resolve_id "$id")" || { err "unknown/ambiguous scenario id: ${id}"; exit 1; }
  local dir; dir="$(scenario_dir "$name")"

  if [ -f "${dir}/cleanup.sh" ]; then
    log "cleanup ${name}: running scenario hook cleanup.sh"
    bash "${dir}/cleanup.sh" || { err "cleanup hook failed for ${name}"; exit 3; }
  else
    log "cleanup ${name}: deleting namespace ${FAULT_NS} (idempotent)"
    kubectl delete ns "${FAULT_NS}" --ignore-not-found || { err "kubectl delete ns failed"; exit 3; }
  fi

  ok "scenario ${name} cleaned up"
  echo "SCENARIO_CLEANED name=${name}"
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  list)    [ -d "${SCENARIOS_DIR}" ] || { err "scenarios tree unreadable"; exit 2; }; cmd_list ;;
  inject)  cmd_inject "${2:-}" ;;
  cleanup) cmd_cleanup "${2:-}" ;;
  ""|-h|--help|help) usage; [ "${1:-}" = "" ] && exit 1 || exit 0 ;;
  *) err "unknown command: ${1}"; usage; exit 1 ;;
esac
