#!/usr/bin/env bash
# Create (or reuse) the local Kubernetes cluster for the workshop.
# Idempotent: if the cluster already exists it is kept as-is.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

wait_for_docker 90

if cluster_exists; then
  ok "cluster '${CLUSTER_NAME}' already exists (kind) — reusing"
else
  log "creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "${REPO_ROOT}/cluster/kind-config.yaml" --wait 120s
  ok "cluster created"
fi

# Make sure kubeconfig points at the workshop cluster.
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

log "waiting for the cluster API to respond..."
for i in {1..30}; do
  if cluster_reachable; then break; fi
  sleep 2
done

if ! cluster_reachable; then
  err "cluster API not reachable after creation"
  exit 1
fi

kubectl wait --for=condition=Ready nodes --all --timeout=120s || warn "nodes not all Ready yet"
ok "cluster '${CLUSTER_NAME}' is reachable"
kubectl get nodes -o wide
