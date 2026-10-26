#!/usr/bin/env bash
# Phase 2 — install the full platform stack into the Codespace cluster.
# Idempotent: every step is `helm upgrade --install` or `kubectl apply`, so
# re-running reconciles rather than duplicating. Safe to run after postCreate.
#
# Usage:   bash cluster/install.sh
# Secrets: read from the environment (see .devcontainer/SECRETS.md). Missing
#          secrets degrade gracefully (component skipped or warns), never crash.
# Toggles: INSTALL_<COMPONENT>=false to skip one, e.g. INSTALL_DYNATRACE=false.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }

INSTALL_DYNATRACE="${INSTALL_DYNATRACE:-true}"
INSTALL_OTEL="${INSTALL_OTEL:-true}"
INSTALL_TETRAGON="${INSTALL_TETRAGON:-true}"
INSTALL_KAGENT="${INSTALL_KAGENT:-true}"
INSTALL_PHOENIX="${INSTALL_PHOENIX:-true}"
INSTALL_AGENT_SANDBOX="${INSTALL_AGENT_SANDBOX:-true}"

kubectl cluster-info >/dev/null 2>&1 || { err "cluster not reachable — run .devcontainer/postCreate.sh first"; exit 1; }
command -v helm >/dev/null || { err "helm not found"; exit 1; }
command -v envsubst >/dev/null || warn "envsubst not found — Dynatrace apiUrl substitution will be skipped"

# prep-stack.sh (Phase 1) already created namespaces + classic helm repos. Make
# this script self-sufficient too (safe if already done).
for ns in dynatrace opentelemetry-operator-system kagent tetragon agent-sandbox phoenix; do
  kubectl get ns "$ns" >/dev/null 2>&1 || kubectl create ns "$ns" >/dev/null
done
helm repo update dynatrace open-telemetry cilium >/dev/null 2>&1 || warn "helm repo update had warnings (offline?)"

# ---------------------------------------------------------------------------
log "0/6  Provisioning secrets from the environment"
bash "${SCRIPT_DIR}/secrets.sh" || warn "secret step reported issues (continuing)"

# ---------------------------------------------------------------------------
if [ "$INSTALL_DYNATRACE" = "true" ]; then
  log "1/6  Dynatrace Operator (k8smonitoring mode)"
  helm upgrade --install dynatrace-operator dynatrace/dynatrace-operator \
    --version "${DT_OPERATOR_CHART_VERSION}" \
    --namespace dynatrace \
    -f "${SCRIPT_DIR}/dynatrace/values.yaml" --wait --timeout 5m
  kubectl -n dynatrace rollout status deploy/dynatrace-webhook --timeout=120s || warn "dynatrace-webhook not ready yet"
  if [ -n "${DT_TENANT_URL:-}" ] && command -v envsubst >/dev/null; then
    envsubst < "${SCRIPT_DIR}/dynatrace/dynakube.yaml" | kubectl apply -f -
    ok "DynaKube applied (tenant monitoring enabled)"
  else
    warn "DT_TENANT_URL unset (or no envsubst) — operator installed, DynaKube NOT applied; set the secret and re-run"
  fi
else
  warn "INSTALL_DYNATRACE=false — skipping Dynatrace"
fi

# ---------------------------------------------------------------------------
if [ "$INSTALL_OTEL" = "true" ]; then
  log "2/6  OpenTelemetry Operator + gateway collector"
  helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
    --version "${OTEL_OPERATOR_CHART_VERSION}" \
    --namespace opentelemetry-operator-system \
    -f "${SCRIPT_DIR}/otel/operator-values.yaml" --wait --timeout 5m
  kubectl -n opentelemetry-operator-system rollout status deploy/opentelemetry-operator --timeout=120s || warn "otel operator not ready"
  # Webhook needs a moment to register before the CR validates.
  for i in {1..15}; do
    kubectl apply -f "${SCRIPT_DIR}/otel/collector-gateway.yaml" 2>/dev/null && { ok "OpenTelemetryCollector applied"; break; }
    sleep 4
  done
else
  warn "INSTALL_OTEL=false — skipping OpenTelemetry"
fi

# ---------------------------------------------------------------------------
if [ "$INSTALL_TETRAGON" = "true" ]; then
  log "3/6  Tetragon (eBPF runtime security)"
  helm upgrade --install tetragon cilium/tetragon \
    --version "${TETRAGON_CHART_VERSION}" \
    --namespace tetragon \
    -f "${SCRIPT_DIR}/tetragon/values.yaml" --wait --timeout 5m || \
    warn "Tetragon install reported issues — check eBPF/BTF support (see cluster/tetragon/README.md)"
else
  warn "INSTALL_TETRAGON=false — skipping Tetragon"
fi

# ---------------------------------------------------------------------------
if [ "$INSTALL_KAGENT" = "true" ]; then
  log "4/6  kagent (clean base — no default agents/tools)"
  helm upgrade --install kagent-crds "${KAGENT_OCI_REPO}/kagent-crds" \
    --version "${KAGENT_CHART_VERSION}" --namespace kagent --wait --timeout 5m
  helm upgrade --install kagent "${KAGENT_OCI_REPO}/kagent" \
    --version "${KAGENT_CHART_VERSION}" --namespace kagent \
    -f "${SCRIPT_DIR}/kagent/values.yaml" --wait --timeout 5m
else
  warn "INSTALL_KAGENT=false — skipping kagent"
fi

# ---------------------------------------------------------------------------
if [ "$INSTALL_PHOENIX" = "true" ]; then
  log "5/6  Phoenix (LLM eval/trace UI)"
  kubectl apply -f "${SCRIPT_DIR}/phoenix/phoenix.yaml"
  kubectl -n phoenix rollout status deploy/phoenix --timeout=180s || warn "Phoenix not ready yet"
else
  warn "INSTALL_PHOENIX=false — skipping Phoenix"
fi

# ---------------------------------------------------------------------------
if [ "$INSTALL_AGENT_SANDBOX" = "true" ]; then
  log "6/6  Agent Sandbox (isolation baseline)"
  kubectl apply -f "${SCRIPT_DIR}/agent-sandbox/isolation.yaml"
else
  warn "INSTALL_AGENT_SANDBOX=false — skipping Agent Sandbox"
fi

cat <<'EOF'

================================================================
 Phase 2 platform install complete.
   kubectl get pods -A            # all operators/components should be Ready
   kubectl get dynakube -n dynatrace
   kubectl get otelcol -n opentelemetry-operator-system

 UIs (forwarded Codespace ports):
   Phoenix   -> port 6006
   kagent UI -> kubectl -n kagent port-forward svc/kagent-ui 8080:8080

 Telemetry: once agents run (Phase 3), spans fan out to Dynatrace + Phoenix
 via otel-gateway-collector.opentelemetry-operator-system.svc:4317.
================================================================
EOF
