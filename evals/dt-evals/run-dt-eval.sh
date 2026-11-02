#!/usr/bin/env bash
# Phase 4 — run a dt-evals eval over the workshop agents' gen_ai.* spans.
#
# Renders workshop-agents.dt-eval.yaml (a template) with your env values via
# envsubst, then validates and runs it. Secrets never touch the committed file;
# the rendered copy (workshop-agents.generated.dt-eval.yaml) is gitignored.
#
# Required env (put them in evals/.env — see evals/.env.example):
#   OPENAI_API_KEY        judge key (a DeepSeek key works — OpenAI-compatible).
#                         Auto-picked-up from the workshop's DEEPSEEK_API_KEY /
#                         LLM_API_KEY secret when OPENAI_API_KEY itself is unset.
#   DYNATRACE_API_TOKEN   dt0c01 token with scopes: storage:spans:read + storage:events:write
#   DT_EVAL_SERVICE       service.name of the agent to evaluate (discover first!)
# One of:
#   DT_ENVIRONMENT_URL    e.g. https://abc12345.apps.dynatrace.com
#   DT_TENANT_URL         Phase-2 .live. URL — auto-converted to .apps.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

# Pinned CLI version (single source of truth in cluster/versions.env). Resolved
# up here so the `evaluators` passthrough below can reach it too.
# shellcheck disable=SC1091
DT_EVALS_PKG="${DT_EVALS_PKG:-$(grep -E '^DT_EVALS_PKG=' "$REPO_ROOT/cluster/versions.env" | cut -d'"' -f2)}"
DT_EVALS_PKG="${DT_EVALS_PKG:-@dynatrace-oss/dt-evals@alpha}"

# Resolve the judge base URL. Sourcing versions.env gives WORKSHOP_LLM_BASE_URL* and
# (at its tail) any .workshop-llm.env proxy override written by the room-password
# dispenser (ISI-6996) — so the judge routes through the LiteLLM proxy when dispensed,
# or hits DeepSeek directly otherwise. The dt-eval.yaml judge baseUrl must NOT carry
# /v1 (the validate probe hardcodes ${baseUrl}/v1/chat/completions → a /v1 here doubles it).
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/cluster/versions.env" ] && . "$REPO_ROOT/cluster/versions.env"
WORKSHOP_LLM_BASE_URL_NOV1="${WORKSHOP_LLM_BASE_URL_NOV1:-${WORKSHOP_LLM_BASE_URL:-https://api.deepseek.com/v1}}"
WORKSHOP_LLM_BASE_URL_NOV1="${WORKSHOP_LLM_BASE_URL_NOV1%/v1}"
export WORKSHOP_LLM_BASE_URL_NOV1

# `evaluators` is a LOCAL management command — it writes custom evaluator
# definitions to ~/.config/dt-eval/custom-prompts.json and needs no Dynatrace
# token and no rendered config. Pass it straight through to the pinned CLI so
# attendees have ONE entry point and nothing to export (no bare $DT_EVALS_PKG in
# a copy-pasted line).  e.g.  ./run-dt-eval.sh evaluators add
if [ "${1:-}" = "evaluators" ]; then
  exec npx -y "$DT_EVALS_PKG" "$@"
fi

# Optional `--config <file>` picks a different eval template (e.g. the module-05
# diagnosis config). Default is the general workshop-agents config. The flag is
# parsed out here; everything else still passes straight through to `dt-evals run`.
CONFIG="workshop-agents.dt-eval.yaml"
PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --config=*) CONFIG="${1#--config=}"; shift ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done
set -- "${PASSTHRU[@]+"${PASSTHRU[@]}"}"
case "$CONFIG" in /*) TEMPLATE="$CONFIG" ;; *) TEMPLATE="$HERE/$CONFIG" ;; esac
[ -f "$TEMPLATE" ] || { echo "ERROR: config not found: $TEMPLATE" >&2; exit 1; }
RENDERED="${TEMPLATE%.yaml}.generated.yaml"

# Load evals/.env if present (keeps secrets out of the shell history).
[ -f "$REPO_ROOT/evals/.env" ] && { set -a; . "$REPO_ROOT/evals/.env"; set +a; }

# The judge is OpenAI-compatible, so any OpenAI/DeepSeek key works. The Codespace
# onboarding provisions this key as DEEPSEEK_API_KEY (fallback LLM_API_KEY) — there
# is no OPENAI_API_KEY secret in the workshop — so map the provisioned name onto it
# when OPENAI_API_KEY is unset. Lets a correctly-set-up Codespace run with no .env.
OPENAI_API_KEY="${OPENAI_API_KEY:-${DEEPSEEK_API_KEY:-${LLM_API_KEY:-}}}"

# Enablement-framework edition: the platform URL arrives as DT_ENVIRONMENT.
DT_ENVIRONMENT_URL="${DT_ENVIRONMENT_URL:-${DT_ENVIRONMENT:-}}"
# Derive the apps URL from the Phase-2 .live. tenant URL if needed.
if [ -z "${DT_ENVIRONMENT_URL:-}" ] && [ -n "${DT_TENANT_URL:-}" ]; then
  DT_ENVIRONMENT_URL="${DT_TENANT_URL/.live./.apps.}"
fi

missing=()
[ -n "${OPENAI_API_KEY:-}" ]      || missing+=("OPENAI_API_KEY (or DEEPSEEK_API_KEY / LLM_API_KEY)")
[ -n "${DYNATRACE_API_TOKEN:-}" ] || missing+=("DYNATRACE_API_TOKEN")
[ -n "${DT_ENVIRONMENT_URL:-}" ]  || missing+=("DT_ENVIRONMENT_URL (or DT_TENANT_URL)")
if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: missing required env: ${missing[*]}" >&2
  echo "       Set them in evals/.env (see evals/.env.example)." >&2
  echo "       The judge key is auto-picked-up from DEEPSEEK_API_KEY / LLM_API_KEY" >&2
  echo "       if either is set, so a provisioned Codespace needs no OPENAI_API_KEY." >&2
  exit 1
fi

# Default the evaluated service.name from the shared-tenant prefix (ISI-6986): the
# SRE agent's spans arrive as ${WORKSHOP_PREFIX}-sre-agent, which is exactly what the
# .dt-eval.yaml scope.service must match. An explicit DT_EVAL_SERVICE still wins.
if [ -z "${DT_EVAL_SERVICE:-}" ] && [ -n "${WORKSHOP_PREFIX:-}" ]; then
  DT_EVAL_SERVICE="${WORKSHOP_PREFIX}-sre-agent"
  echo "DT_EVAL_SERVICE defaulted to '${DT_EVAL_SERVICE}' from WORKSHOP_PREFIX." >&2
fi

if [ -z "${DT_EVAL_SERVICE:-}" ]; then
  cat >&2 <<EOF
ERROR: DT_EVAL_SERVICE is not set and WORKSHOP_PREFIX is unset — DT_EVAL_SERVICE is
the service.name of the agent to evaluate. On the shared workshop tenant set
WORKSHOP_PREFIX (it defaults DT_EVAL_SERVICE to \${WORKSHOP_PREFIX}-sre-agent), or
set DT_EVAL_SERVICE directly. Confirm the value with DQL
(Dynatrace Notebook / run-dt-query capability):

  fetch spans, from: now() - 2h
  | filter isNotNull(gen_ai.operation.name) or isNotNull(gen_ai.request.model)
  | summarize span_count = count(), by: { service.name }
  | sort span_count desc

Then: export DT_EVAL_SERVICE="<the service.name>"  (or set it in evals/.env)
EOF
  exit 1
fi

export OPENAI_API_KEY DYNATRACE_API_TOKEN DT_ENVIRONMENT_URL DT_EVAL_SERVICE

echo "Rendering $RENDERED (service=$DT_EVAL_SERVICE, env=$DT_ENVIRONMENT_URL)"
# The rendered config carries the judge key and the Dynatrace token: owner-only.
umask 077
envsubst '${DT_ENVIRONMENT_URL} ${DYNATRACE_API_TOKEN} ${OPENAI_API_KEY} ${DT_EVAL_SERVICE} ${WORKSHOP_LLM_BASE_URL_NOV1}' \
  < "$TEMPLATE" > "$RENDERED"

echo "==> dt-evals validate"
npx -y "$DT_EVALS_PKG" validate --config "$RENDERED"

echo "==> dt-evals run"
npx -y "$DT_EVALS_PKG" run --config "$RENDERED" "$@"

cat <<EOF

Done. Inspect results in Dynatrace with DQL:

  fetch bizevents
  | filter event.type == "gen_ai.evaluation.result"
  | summarize avg(toDouble(gen_ai.evaluation.score.value)), by: { gen_ai.evaluation.name }

(Rendered config left at $RENDERED — it contains secrets and is gitignored.)
EOF
