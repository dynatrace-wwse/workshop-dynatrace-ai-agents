#!/usr/bin/env bash
# ── ISI-6986 WS5 (ISI-6991) · end-to-end prefix render/consistency check ─────
# Ported from upstream; adapted: here the collector keeps the per-learner
# k8s.cluster.name (${K8S_CLUSTER_NAME}, what the training's {{DT_SESSION_ID}}
# DQL filters on) and stamps the prefix as workshop.attendee only.
# Proves the ${WORKSHOP_PREFIX} isolation mechanism renders correctly across the
# WHOLE workshop stack, not just one layer. On a shared Dynatrace tenant every
# attendee's telemetry must be tagged + queried under their own prefix, so this
# gate renders each templated asset exactly the way cluster/install.sh and
# agents/install-agents.sh do (scoped `envsubst`) with a sample prefix and
# asserts, failing closed on any leak:
#
#   A. COLLECTOR (cluster/otel/collector-gateway.yaml)
#      1. nothing unresolved — no ${WORKSHOP_PREFIX} survives substitution;
#      2. the resource processor STAMPS workshop.attendee = <prefix> AND
#         k8s.cluster.name = the per-learner cluster name;
#      3. the collector's own ${env:...} runtime refs are LEFT INTACT (scoped
#         envsubst must not eat them).
#
#   B. DQL ASSETS (cluster/dynatrace/optimization/*.{dashboard,guardian,notebook}
#      + the UI-importable docs/assets/optimization/*.json generated from them)
#      1. nothing unresolved — no ${WORKSHOP_PREFIX} survives substitution;
#      2. every asset FILTERS on workshop.attendee == "<prefix>";
#      3. no BARE service.name filter leaks — every `service.name == "..."`
#         that targets the SRE agent is prefixed (<prefix>-sre-agent); a bare
#         `sre-agent` or the legacy single-tenant `seta_sre_investigator` as a
#         DQL filter value fails the run.
#
#   C. AGENT / MCP CRs — delegated to agents/check-render.sh (kagent CR names
#      prefixed, orchestrator child list resolves, Dynatrace MCP intact).
#
# No cluster required — pure local render. Needs: envsubst (gettext), grep -P.
#   bash cluster/check-prefix-render.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }
info() { printf '\033[1;36m[ info ]\033[0m %s\n' "$*"; }

command -v envsubst >/dev/null || { err "envsubst not found (install gettext-base)"; exit 1; }

# Sample prefix — a realistic worst case (contains a '-') to exercise boundaries.
export WORKSHOP_PREFIX="team-test"
PFX="${WORKSHOP_PREFIX}"
info "rendering with WORKSHOP_PREFIX='${PFX}'"
fail=0

# ── A. COLLECTOR ─────────────────────────────────────────────────────────────
COLLECTOR_SRC="${SCRIPT_DIR}/otel/collector-gateway.yaml"
# SCOPED envsubst — exactly as installOtelGateway does, so the collector's own
# ${env:...} runtime refs are preserved.
export K8S_CLUSTER_NAME="aiw-team-test-20261102"
COLLECTOR="$(envsubst '${K8S_CLUSTER_NAME} ${WORKSHOP_PREFIX}' < "${COLLECTOR_SRC}")"

# NB: all matches use herestrings (<<<), never `printf | grep -q`. Under
# `set -o pipefail` a downstream `grep -q` closes the pipe on first match, the
# upstream writer catches SIGPIPE (exit 141), and pipefail then reports the
# whole pipeline as failed even though the match SUCCEEDED — a real, observed
# flake. Herestrings have no pipe, so no SIGPIPE, so no flake.
if grep -qE '\$\{(WORKSHOP_PREFIX|K8S_CLUSTER_NAME)\}' <<<"${COLLECTOR}"; then
  err "collector: \${WORKSHOP_PREFIX} / \${K8S_CLUSTER_NAME} left unresolved after scoped envsubst"
  fail=1
fi
# workshop.attendee = <prefix>  (value sits on the line AFTER the key)
col_attendee="$(grep -A1 -E '^\s*- key: workshop\.attendee\s*$' <<<"${COLLECTOR}" || true)"
if grep -qE "^\s*value: ${PFX}\s*$" <<<"${col_attendee}"; then
  ok "collector: workshop.attendee = ${PFX}"
else
  err "collector: resource processor does NOT stamp workshop.attendee = ${PFX}"
  fail=1
fi
# k8s.cluster.name = the per-learner cluster name
col_cluster="$(grep -A1 -E '^\s*- key: k8s\.cluster\.name\s*$' <<<"${COLLECTOR}" || true)"
if grep -qE "^\s*value: ${K8S_CLUSTER_NAME}\s*$" <<<"${col_cluster}"; then
  ok "collector: k8s.cluster.name = ${K8S_CLUSTER_NAME}"
else
  err "collector: resource processor does NOT stamp k8s.cluster.name = ${K8S_CLUSTER_NAME}"
  fail=1
fi
# scoped envsubst must not have eaten the collector's own ${env:...} runtime refs
if grep -qF '${env:' <<<"${COLLECTOR}"; then
  ok "collector: \${env:...} runtime refs preserved (scoped envsubst)"
else
  err "collector: expected \${env:...} runtime refs are gone — envsubst was NOT scoped"
  fail=1
fi

# ── B. DQL ASSETS ────────────────────────────────────────────────────────────
DQL_ASSETS=(
  "${SCRIPT_DIR}/dynatrace/optimization/ai-agent-optimization.dashboard.yaml"
  "${SCRIPT_DIR}/dynatrace/optimization/ai-agent-quality-cost.guardian.yaml"
  "${SCRIPT_DIR}/dynatrace/optimization/ai-agent-optimization-before-after.notebook.yaml"
  "${SCRIPT_DIR}/dynatrace/optimization/ai-agent-workflow-steps.notebook.yaml"
  "${REPO_ROOT}/docs/assets/optimization/ai-agent-optimization.dashboard.json"
  "${REPO_ROOT}/docs/assets/optimization/ai-agent-optimization-before-after.notebook.json"
)
for src in "${DQL_ASSETS[@]}"; do
  [ -f "${src}" ] || { err "DQL asset missing: ${src}"; fail=1; continue; }
  name="$(basename "${src}")"
  rendered="$(envsubst '${WORKSHOP_PREFIX}' < "${src}")"
  # JSON assets escape the DQL quotes (\"); normalise \" -> " so one set of
  # patterns matches both the YAML (bare ") and JSON (\") encodings.
  norm="$(sed 's/\\"/"/g' <<<"${rendered}")"

  # 1. nothing unresolved — DQL assets template ONLY ${WORKSHOP_PREFIX}, so ANY
  #    surviving ${...} (a typo'd or newly-added var) is a leak.
  if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"${rendered}"; then
    err "${name}: unresolved \${...} placeholder(s) above after render"
    fail=1
  fi
  # 2. attendee-scoped filter present
  if grep -qF "workshop.attendee == \"${PFX}\"" <<<"${norm}"; then
    ok "${name}: filters on workshop.attendee == \"${PFX}\""
  else
    err "${name}: no 'workshop.attendee == \"${PFX}\"' filter found — asset is not attendee-scoped"
    fail=1
  fi
  # 3a. no BARE service.name filter (unprefixed or legacy single-tenant name)
  if grep -nE 'service\.name *== *"(sre-agent|seta_sre_investigator)"' <<<"${norm}"; then
    err "${name}: BARE service.name filter above — must be \"${PFX}-sre-agent\""
    fail=1
  fi
  # 3b. no bare attendee filter leaked a legacy name
  if grep -nE 'workshop\.attendee *== *"(sre-agent|seta_sre_investigator)"' <<<"${norm}"; then
    err "${name}: workshop.attendee compared to a legacy/bare name above — must be \"${PFX}\""
    fail=1
  fi
done

# ── C. AGENT / MCP CRs ───────────────────────────────────────────────────────
AGENT_CHECK="${REPO_ROOT}/agents/check-render.sh"
if [ -x "${AGENT_CHECK}" ] || [ -f "${AGENT_CHECK}" ]; then
  info "delegating agent/MCP CR render check -> agents/check-render.sh"
  if bash "${AGENT_CHECK}"; then
    ok "agent/MCP CRs: names prefixed, orchestrator child list resolves, nothing unresolved"
  else
    err "agents/check-render.sh FAILED (see above)"
    fail=1
  fi
else
  err "agents/check-render.sh not found at ${AGENT_CHECK}"
  fail=1
fi

if [ "${fail}" -ne 0 ]; then
  err "prefix render/consistency check FAILED"
  exit 1
fi
ok "prefix render/consistency check passed (prefix='${PFX}'): collector stamped, DQL attendee-scoped, agent CRs prefixed, nothing unresolved"
