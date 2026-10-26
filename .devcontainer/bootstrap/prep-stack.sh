#!/usr/bin/env bash
# Prepare the cluster for the Phase 2 platform install WITHOUT installing it.
# Idempotent: creates namespaces and registers Helm repos so Phase 2 `helm
# install` runs offline-fast. Safe to re-run any number of times.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

cluster_reachable || { err "cluster not reachable; run create-cluster.sh first"; exit 1; }

# --- Namespaces for the component stack ---
for ns in dynatrace opentelemetry-operator-system kagent tetragon agent-sandbox phoenix; do
  kubectl get namespace "$ns" >/dev/null 2>&1 \
    && ok "namespace/$ns exists" \
    || { kubectl create namespace "$ns" >/dev/null && ok "namespace/$ns created"; }
done

# --- Helm repos used by Phase 2 (registration only, no installs) ---
add_repo() {
  local name="$1" url="$2"
  if helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    ok "helm repo '$name' present"
  elif helm repo add "$name" "$url" >/dev/null 2>&1; then
    ok "helm repo '$name' added"
  else
    warn "could not add helm repo '$name' ($url) — may be offline; Phase 2 will retry"
  fi
}
add_repo dynatrace       https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
add_repo open-telemetry  https://open-telemetry.github.io/opentelemetry-helm-charts
add_repo cilium          https://helm.cilium.io
# NOTE: kagent moved to OCI Helm charts (oci://ghcr.io/kagent-dev/kagent/helm/*);
# the old kagent-dev.github.io repo now 404s. OCI charts need no `helm repo add`
# — cluster/install.sh pulls them directly. See cluster/kagent/README.md.
helm repo update >/dev/null 2>&1 || warn "helm repo update had warnings (non-fatal, may be offline)"

ok "stack prep complete — namespaces + helm repos ready for Phase 2"
