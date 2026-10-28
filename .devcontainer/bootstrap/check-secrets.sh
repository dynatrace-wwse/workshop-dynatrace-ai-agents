#!/usr/bin/env bash
# Report which Codespace secrets are present WITHOUT printing their values.
# Mirrors the canonical contract in .devcontainer/SECRETS.md (ISI-6744 matrix).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Presence check for a single variable (value never printed).
check() {
  local var="$1" required="$2" note="$3"
  if [ -n "${!var:-}" ]; then
    ok "${var} is set"
  elif [ "$required" = "required" ]; then
    warn "${var} is MISSING (required) — ${note}"
  else
    warn "${var} is not set (optional) — ${note}"
  fi
}

# Presence check for a "preferred / fallback" pair: satisfied if EITHER is set.
check_either() {
  local preferred="$1" fallback="$2" required="$3" note="$4"
  if [ -n "${!preferred:-}" ]; then
    ok "${preferred} is set (preferred)"
  elif [ -n "${!fallback:-}" ]; then
    ok "${fallback} is set (fallback for ${preferred})"
  elif [ "$required" = "required" ]; then
    warn "${preferred} / ${fallback} are MISSING (required) — ${note}"
  else
    warn "${preferred} / ${fallback} not set (optional) — ${note}"
  fi
}

echo "--- Codespace secrets contract (values never printed) ---"

echo "[Phase 2] Dynatrace operator + OTLP ingest"
check DT_TENANT_URL required "Dynatrace tenant, e.g. https://abc12345.live.dynatrace.com"
check DT_API_TOKEN  required "Dynatrace API token (dt0c01) for the operator + OTLP ingest"

echo "[Phase 3/5] Dynatrace platform — dtctl + Dynatrace MCP (one platform token)"
check DT_PLATFORM_TOKEN required "Dynatrace platform token (dt0s16) shared by dtctl and the Dynatrace MCP"
check DT_ENVIRONMENT    optional "platform apps URL (https://<env>.apps.dynatrace.com); derived from DT_TENANT_URL if unset"

echo "[Phase 3] Agents LLM + GitHub MCP (BMAD 'bad crew')"
check_either DEEPSEEK_API_KEY LLM_API_KEY required "model-provider key powering the kagent agents + eval judge (DeepSeek by default)"
check_either GITHUB_PAT GITHUB_TOKEN       required "GitHub token for the GitHub MCP; fine-grained PAT for the write demo (Codespaces injects GITHUB_TOKEN)"
check GITHUB_DEMO_REPO required "BMAD/'bad crew' demo repo (owner/repo) the GitHub MCP writes to"

echo "[Phase 4] dt-evals (trace-sourced LLM-as-judge)"
check_either DT_ENV_URL DT_ENVIRONMENT_URL optional "dt-evals tenant URL; derived from DT_TENANT_URL if unset"
check DYNATRACE_API_TOKEN optional "dt-evals token (dt0c01), scopes: storage:spans:read + storage:events:write"
check DT_EVAL_SERVICE     optional "service.name of the agent to evaluate (discovered, not a secret)"

echo "[Optional] alternate model providers"
check OPENAI_API_KEY    optional "used if agents/judge target OpenAI directly"
check ANTHROPIC_API_KEY optional "used if agents target Anthropic models"

echo "---------------------------------------------------------"
echo "Set/rotate these under: GitHub repo/user Settings > Codespaces > Secrets."
exit 0
