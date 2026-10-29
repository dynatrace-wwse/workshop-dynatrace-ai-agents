#!/usr/bin/env bash
# Tear down the Phase 2 platform stack. Leaves the cluster + namespaces intact
# (re-run cluster/install.sh to reinstall). Idempotent — ignores "not found".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '\033[1;34m[uninstall]\033[0m %s\n' "$*"; }

log "removing CRs first (so operators can finalize cleanly)"
kubectl delete -f "${SCRIPT_DIR}/otel/collector-gateway.yaml" --ignore-not-found
kubectl delete dynakube dynakube -n dynatrace --ignore-not-found
kubectl delete -f "${SCRIPT_DIR}/phoenix/phoenix.yaml" --ignore-not-found
kubectl delete -f "${SCRIPT_DIR}/agent-sandbox/isolation.yaml" --ignore-not-found

log "uninstalling helm releases"
# opentelemetry-demo-light (scenario #12, opt-in) — released as 'otel-demo' in ns otel-demo.
helm uninstall otel-demo -n otel-demo 2>/dev/null || true
kubectl delete ns otel-demo --ignore-not-found
helm uninstall kagent -n kagent 2>/dev/null || true
helm uninstall kagent-crds -n kagent 2>/dev/null || true
helm uninstall tetragon -n tetragon 2>/dev/null || true
helm uninstall opentelemetry-operator -n opentelemetry-operator-system 2>/dev/null || true
helm uninstall dynatrace-operator -n dynatrace 2>/dev/null || true

log "done (namespaces + secrets kept; delete manually if you want a clean slate)"
