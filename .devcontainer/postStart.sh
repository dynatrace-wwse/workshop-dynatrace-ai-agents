#!/usr/bin/env bash
# postStart — runs every time the Codespace starts/resumes. IDEMPOTENT.
# A stopped Codespace loses the running containers (incl. the k3d/kind nodes),
# so we ensure the cluster is back up without recreating it if it survived.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
source "${SCRIPT_DIR}/bootstrap/lib.sh"

wait_for_docker 90 || { warn "Docker not ready; skipping cluster restart"; exit 0; }

if ! cluster_exists; then
  warn "cluster '${CLUSTER_NAME}' not found — recreating"
  bash "${SCRIPT_DIR}/bootstrap/create-cluster.sh"
  bash "${SCRIPT_DIR}/bootstrap/prep-stack.sh"
  exit 0
fi

# Cluster exists but its node containers may be stopped after a resume.
case "$CLUSTER_TOOL" in
  k3d)
    if ! cluster_reachable; then
      log "starting stopped k3d cluster '${CLUSTER_NAME}'"
      k3d cluster start "${CLUSTER_NAME}" || true
    fi
    ;;
  kind)
    # kind nodes are plain containers; Docker restarts them with the daemon.
    if ! cluster_reachable; then
      log "ensuring kind node containers are running"
      docker start "${CLUSTER_NAME}-control-plane" "${CLUSTER_NAME}-worker" 2>/dev/null || true
    fi
    ;;
esac

for i in {1..30}; do cluster_reachable && break; sleep 2; done
if cluster_reachable; then
  ok "cluster '${CLUSTER_NAME}' is up"
  kubectl get nodes --no-headers 2>/dev/null || true
else
  warn "cluster not reachable after start; run: bash .devcontainer/postCreate.sh"
fi
