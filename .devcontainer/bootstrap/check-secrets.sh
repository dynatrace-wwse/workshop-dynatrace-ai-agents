#!/usr/bin/env bash
# Report which Codespace secrets are present WITHOUT printing their values.
# See .devcontainer/SECRETS.md for the full contract.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

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

echo "--- Codespace secrets contract (values never printed) ---"
check DT_TENANT_URL      required "Dynatrace tenant, e.g. https://abc12345.live.dynatrace.com"
check DT_API_TOKEN       required "Dynatrace API token for the operator + MCP"
check GITHUB_TOKEN       required "GitHub token for the GitHub MCP (Codespaces usually injects this)"
check LLM_API_KEY        required "Model provider key powering kagent agents"
check OPENAI_API_KEY     optional "used if agents target OpenAI-compatible endpoints"
check ANTHROPIC_API_KEY  optional "used if agents target Anthropic models"
echo "---------------------------------------------------------"
echo "Set/rotate these under: GitHub repo/user Settings > Codespaces > Secrets."
exit 0
