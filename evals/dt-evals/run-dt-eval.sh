#!/usr/bin/env bash
# Phase 4 — run a dt-evals eval over the workshop agents' gen_ai.* spans.
#
# Renders workshop-agents.dt-eval.yaml (a template) with your env values via
# envsubst, then validates and runs it. Secrets never touch the committed file;
# the rendered copy (workshop-agents.generated.dt-eval.yaml) is gitignored.
#
# Required env (put them in evals/.env — see evals/.env.example):
#   OPENAI_API_KEY        judge key (a DeepSeek key works — OpenAI-compatible)
#   DYNATRACE_API_TOKEN   dt0c01 token with scopes: storage:spans:read + storage:events:write
#   DT_EVAL_SERVICE       service.name of the agent to evaluate (discover first!)
# One of:
#   DT_ENVIRONMENT_URL    e.g. https://abc12345.apps.dynatrace.com
#   DT_TENANT_URL         Phase-2 .live. URL — auto-converted to .apps.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$HERE/workshop-agents.dt-eval.yaml"
RENDERED="$HERE/workshop-agents.generated.dt-eval.yaml"

# Pinned CLI version (single source of truth in cluster/versions.env).
# shellcheck disable=SC1091
DT_EVALS_PKG="${DT_EVALS_PKG:-$(grep -E '^DT_EVALS_PKG=' "$REPO_ROOT/cluster/versions.env" | cut -d'"' -f2)}"
DT_EVALS_PKG="${DT_EVALS_PKG:-@dynatrace-oss/dt-evals@alpha}"

# Load evals/.env if present (keeps secrets out of the shell history).
[ -f "$REPO_ROOT/evals/.env" ] && { set -a; . "$REPO_ROOT/evals/.env"; set +a; }

# Derive the apps URL from the Phase-2 .live. tenant URL if needed.
if [ -z "${DT_ENVIRONMENT_URL:-}" ] && [ -n "${DT_TENANT_URL:-}" ]; then
  DT_ENVIRONMENT_URL="${DT_TENANT_URL/.live./.apps.}"
fi

missing=()
[ -n "${OPENAI_API_KEY:-}" ]      || missing+=("OPENAI_API_KEY")
[ -n "${DYNATRACE_API_TOKEN:-}" ] || missing+=("DYNATRACE_API_TOKEN")
[ -n "${DT_ENVIRONMENT_URL:-}" ]  || missing+=("DT_ENVIRONMENT_URL (or DT_TENANT_URL)")
if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: missing required env: ${missing[*]}" >&2
  echo "       Set them in evals/.env (see evals/.env.example)." >&2
  exit 1
fi

if [ -z "${DT_EVAL_SERVICE:-}" ]; then
  cat >&2 <<EOF
ERROR: DT_EVAL_SERVICE is not set — this is the service.name of the agent to
evaluate, and it must be discovered, not guessed. Run this DQL in Dynatrace
(Notebooks / the run-dt-query capability) to list candidates:

  fetch spans, from: now() - 2h
  | filter isNotNull(gen_ai.operation.name) or isNotNull(gen_ai.request.model)
  | summarize span_count = count(), by: { service.name }
  | sort span_count desc

Then: export DT_EVAL_SERVICE="<the service.name>"  (or add it to evals/.env)
EOF
  exit 1
fi

export OPENAI_API_KEY DYNATRACE_API_TOKEN DT_ENVIRONMENT_URL DT_EVAL_SERVICE

echo "Rendering $RENDERED (service=$DT_EVAL_SERVICE, env=$DT_ENVIRONMENT_URL)"
envsubst '${DT_ENVIRONMENT_URL} ${DYNATRACE_API_TOKEN} ${OPENAI_API_KEY} ${DT_EVAL_SERVICE}' \
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
