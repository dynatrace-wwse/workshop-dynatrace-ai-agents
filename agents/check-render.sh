#!/usr/bin/env bash
# ── Render / consistency check for the prefixed agent manifests ─────────────
# Ported from upstream (ISI-6989, WS3 of ISI-6986) and adapted to this repo:
# the manifests are applied by `installAgents` in
# .devcontainer/util/my_functions.sh, which renders them with `aiwRender`
# (envsubst over a whitelist). This check sources that file and renders with
# the SAME function, so it tests the wiring, not a copy of it. It asserts:
#
#   1. nothing unresolved — no `${...}` survives in an applied agent manifest;
#   2. no BARE resource name leaks — every sre-agent / workshop-llm /
#      github-mcp / github-mcp-remote / bmad-* that ends up applied is prefixed;
#   3. the prefixed names are actually PRESENT (a file that silently failed to
#      template would otherwise pass 1 and 2);
#   4. the Dynatrace MCP stays as it is: `dynatrace-mcp-remote` is referenced
#      unprefixed and the `# >>> dynatrace-tools` markers survive the render
#      (installAgents strips that block by marker when there is no token);
#   5. the prefix resolver never fails closed and always yields a valid label.
#
# Not prefixed on purpose: the `kagent` namespace, the Helm built-in
# `kagent-tool-server`, the upstream `github-mcp-server` image and the
# Dynatrace MCP objects (agents/mcp/20-dynatrace-mcp.yaml).
#
# No cluster required. Needs: envsubst (gettext), grep -P.
#   bash agents/check-render.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }

command -v envsubst >/dev/null || { err "envsubst not found (gettext)"; exit 1; }
echo x | grep -qP x 2>/dev/null || { err "grep -P (PCRE) not available"; exit 1; }

# Source the lab functions the way the framework does (REPO_PATH set). Only
# definitions and pure variable resolution run at source time.
export REPO_PATH="${REPO_ROOT}"
# A realistic worst case (contains a '-') to exercise the boundary logic.
export WORKSHOP_PREFIX="team-test"
set +u
# shellcheck source=../.devcontainer/util/my_functions.sh
source "${REPO_ROOT}/.devcontainer/util/my_functions.sh"
set -u
[ "${WORKSHOP_PREFIX}" = "team-test" ] || { err "my_functions.sh rewrote a valid WORKSHOP_PREFIX to '${WORKSHOP_PREFIX}'"; exit 1; }
export GITHUB_MCP_IMAGE="ghcr.io/github/github-mcp-server:v0.0.0"
export GH_PAT="x-render-check-token"
export DT_ENVIRONMENT="https://render-check.invalid" DT_PLATFORM_TOKEN="x-render-check"
export AIW_OLLAMA_MODEL="qwen2.5:3b" AIW_OLLAMA_THREADS="4"
export WORKSHOP_LLM_MODEL WORKSHOP_LLM_BASE_URL DYNATRACE_MCP_NODE_IMAGE DYNATRACE_MCP_PACKAGE

# The agent manifests installAgents applies (kustomization.yaml is kustomize
# config, never applied as a resource; 20-dynatrace-mcp.yaml is checked in 4).
MANIFESTS=(
  "${SCRIPT_DIR}/mcp/00-modelconfig.yaml"
  "${SCRIPT_DIR}/mcp/00-modelconfig-ollama.yaml"
  "${SCRIPT_DIR}/mcp/10-github-mcp.yaml"
  "${SCRIPT_DIR}/sre/sre-agent.yaml"
  "${SCRIPT_DIR}/sre/sre-agent-lean.yaml"
  "${SCRIPT_DIR}/bmad-crew/01-bmad-analyst.yaml"
  "${SCRIPT_DIR}/bmad-crew/02-bmad-pm.yaml"
  "${SCRIPT_DIR}/bmad-crew/03-bmad-architect.yaml"
  "${SCRIPT_DIR}/bmad-crew/04-bmad-developer.yaml"
  "${SCRIPT_DIR}/bmad-crew/05-bmad-qa.yaml"
  "${SCRIPT_DIR}/bmad-crew/06-bmad-orchestrator.yaml"
)

# Render the install way; strip full-line comments so doc prose is not
# mistaken for an applied value.
RENDERED="$(for f in "${MANIFESTS[@]}"; do aiwRender < "$f"; echo "---"; done | grep -vP '^\s*#')"

fail=0

# 1. nothing unresolved
if grep -nP '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"${RENDERED}"; then
  err "unresolved \${...} placeholder(s) above — add the var to aiwRender or fix the manifest"
  fail=1
fi

# 2. no bare (unprefixed) names. A token is OK only right after "<prefix>-".
#    (?![a-z0-9-]) keeps github-mcp from matching inside github-mcp-server.
TOKENS='github-mcp-remote|github-mcp|workshop-llm|sre-agent|bmad-analyst|bmad-pm|bmad-architect|bmad-developer|bmad-qa|bmad-orchestrator'
if grep -nP "(?<!${WORKSHOP_PREFIX}-)(?<![a-z0-9])(${TOKENS})(?![a-z0-9-])" <<<"${RENDERED}"; then
  err "bare (unprefixed) resource name(s) above — prefix with \${WORKSHOP_PREFIX}-"
  fail=1
fi

# 3. the prefixed names must be present
for expect in workshop-llm github-mcp github-mcp-remote sre-agent bmad-analyst bmad-pm \
              bmad-architect bmad-developer bmad-qa bmad-orchestrator; do
  grep -qF "${WORKSHOP_PREFIX}-${expect}" <<<"${RENDERED}" \
    || { err "expected prefixed name missing from render: ${WORKSHOP_PREFIX}-${expect}"; fail=1; }
done
[ "$(aiwAgent sre-agent)" = "${WORKSHOP_PREFIX}-sre-agent" ] \
  && [ "$(aiwAgent "${WORKSHOP_PREFIX}-sre-agent")" = "${WORKSHOP_PREFIX}-sre-agent" ] \
  || { err "aiwAgent does not map sre-agent to ${WORKSHOP_PREFIX}-sre-agent idempotently"; fail=1; }

# 4. Dynatrace MCP untouched: unprefixed reference + intact markers in both SRE agents
for f in "${SCRIPT_DIR}/sre/sre-agent.yaml" "${SCRIPT_DIR}/sre/sre-agent-lean.yaml"; do
  r="$(aiwRender < "$f")"
  grep -qE '^\s*name: dynatrace-mcp-remote\s*$' <<<"$r" \
    || { err "$(basename "$f"): dynatrace-mcp-remote reference missing or renamed"; fail=1; }
  [ "$(grep -c '# >>> dynatrace-tools' <<<"$r")" = 1 ] && [ "$(grep -c '# <<< dynatrace-tools' <<<"$r")" = 1 ] \
    || { err "$(basename "$f"): dynatrace-tools markers lost"; fail=1; }
  grep -q 'dynatrace-mcp-remote' <<<"$(aiwStripDynatraceTools "$f" | grep -v '^\s*#')" \
    && { err "$(basename "$f"): stripping the dynatrace-tools block leaves a Dynatrace MCP reference"; fail=1; }
done
grep -qE '^\s*name: dynatrace-mcp(-remote)?\s*$' "${SCRIPT_DIR}/mcp/20-dynatrace-mcp.yaml" \
  || { err "20-dynatrace-mcp.yaml: object names changed"; fail=1; }

# 5. resolver: never empty, always valid, deterministic
check_prefix(){ # <expected> <env assignments...>
  local want="$1"; shift
  local got
  got="$(env -i PATH="$PATH" "$@" bash -c 'source "$0"; aiwResolvePrefix' "${REPO_ROOT}/.devcontainer/util/my_functions.sh" 2>/dev/null)"
  if [ "$got" = "$want" ] && grep -qE "$AIW_PREFIX_PATTERN" <<<"$got"; then ok "prefix: $* -> ${got}"
  else err "prefix: $* -> '${got}', expected '${want}'"; fail=1; fi
}
check_prefix team-alpha    WORKSHOP_PREFIX=team-alpha
check_prefix team-alpha    WORKSHOP_PREFIX=Team_Alpha!
check_prefix w-42          WORKSHOP_PREFIX=42
check_prefix octo-cat      GITHUB_USER=Octo-Cat
check_prefix maria-jose    DT_HOSTGROUP=maria-jose-20261102
check_prefix a-very-long-learner DT_HOSTGROUP=a-very-long-learner-name-20261102
check_prefix workshop      WORKSHOP_PREFIX=--- GITHUB_USER=
check_prefix workshop

if [ "${fail}" -ne 0 ]; then
  err "render/consistency check FAILED"
  exit 1
fi
ok "render/consistency check passed (prefix='${WORKSHOP_PREFIX}'): names prefixed, Dynatrace MCP intact, nothing unresolved"
