#!/usr/bin/env bash
# Shared helpers for the devcontainer bootstrap scripts. Source this file.
# Everything here is written to be idempotent and safe to re-run.

# shellcheck disable=SC2034
CLUSTER_TOOL="${CLUSTER_TOOL:-kind}"
CLUSTER_NAME="${CLUSTER_NAME:-workshop}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# Wait until the Docker daemon (Docker-in-Docker) answers, up to N seconds.
wait_for_docker() {
  local tries="${1:-60}"
  log "waiting for Docker daemon..."
  for ((i=0; i<tries; i++)); do
    if docker info >/dev/null 2>&1; then ok "Docker is up"; return 0; fi
    sleep 2
  done
  err "Docker daemon did not become ready in time"
  return 1
}

# True if the workshop kind cluster already exists.
cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"
}

# True if kubectl can reach the API server.
cluster_reachable() {
  kubectl cluster-info >/dev/null 2>&1
}
