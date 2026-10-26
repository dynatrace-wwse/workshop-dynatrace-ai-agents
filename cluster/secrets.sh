#!/usr/bin/env bash
# Create the Kubernetes secrets the platform stack consumes, from Codespace
# environment variables (see .devcontainer/SECRETS.md). Values are NEVER printed
# and NEVER committed. Idempotent: secrets are upserted with apply.
#
#   DT_TENANT_URL   e.g. https://abc12345.live.dynatrace.com   (no trailing /api)
#   DT_API_TOKEN    Dynatrace token: k8s-monitoring scopes for the operator +
#                   OTLP ingest scopes (openTelemetryTrace/metrics/logs.ingest)
#                   for the OTel collector.
#   LLM_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY  model-provider key for kagent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m[secrets]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }

apply_secret() { kubectl apply -f - >/dev/null; }

# --- Dynatrace token secret -------------------------------------------------
# The operator convention: the secret name MUST match the DynaKube name ("dynakube").
if [ -n "${DT_API_TOKEN:-}" ]; then
  kubectl create secret generic dynakube -n dynatrace \
    --from-literal=apiToken="${DT_API_TOKEN}" \
    --from-literal=dataIngestToken="${DT_API_TOKEN}" \
    --dry-run=client -o yaml | apply_secret
  ok "secret/dynakube (dynatrace) upserted"
else
  warn "DT_API_TOKEN not set — skipping secret/dynakube (operator + OTLP export will not authenticate)"
fi

# --- OTLP export secret (collector -> Dynatrace tenant) ---------------------
# The OTel gateway reads the tenant URL + token from this secret (ns opentelemetry-operator-system).
if [ -n "${DT_TENANT_URL:-}" ] && [ -n "${DT_API_TOKEN:-}" ]; then
  # Normalise: ensure the OTLP endpoint is <tenant>/api/v2/otlp
  endpoint="${DT_TENANT_URL%/}/api/v2/otlp"
  kubectl create secret generic dynatrace-otlp -n opentelemetry-operator-system \
    --from-literal=endpoint="${endpoint}" \
    --from-literal=apiToken="${DT_API_TOKEN}" \
    --dry-run=client -o yaml | apply_secret
  ok "secret/dynatrace-otlp (opentelemetry-operator-system) upserted"
else
  warn "DT_TENANT_URL / DT_API_TOKEN not set — OTel gateway will export to Phoenix only (no Dynatrace)"
fi

# --- kagent model-provider secret -------------------------------------------
# Provider is decided in Phase 3. Default values target OpenAI.
# Create whichever secret matches the key that is actually present.
MODEL_KEY="${LLM_API_KEY:-${OPENAI_API_KEY:-}}"
if [ -n "${MODEL_KEY}" ]; then
  kubectl create secret generic kagent-openai -n kagent \
    --from-literal=OPENAI_API_KEY="${MODEL_KEY}" \
    --dry-run=client -o yaml | apply_secret
  ok "secret/kagent-openai (kagent) upserted"
fi
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  kubectl create secret generic kagent-anthropic -n kagent \
    --from-literal=ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    --dry-run=client -o yaml | apply_secret
  ok "secret/kagent-anthropic (kagent) upserted"
fi
[ -n "${MODEL_KEY}${ANTHROPIC_API_KEY:-}" ] || \
  warn "no model key (LLM_API_KEY/OPENAI_API_KEY/ANTHROPIC_API_KEY) — kagent installs clean but agents need a key in Phase 3"

ok "secret provisioning complete"
