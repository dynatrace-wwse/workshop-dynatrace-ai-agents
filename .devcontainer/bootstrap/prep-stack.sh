#!/usr/bin/env bash
# Prepare the cluster for the Phase 2 platform install WITHOUT installing it.
# Idempotent: creates namespaces and registers Helm repos so Phase 2 `helm
# install` runs offline-fast. Safe to re-run any number of times.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

cluster_reachable || { err "cluster not reachable; run create-cluster.sh first"; exit 1; }

# --- Namespaces for the component stack (plan §3) ---
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
  else
    helm repo add "$name" "$url" >/dev/null && ok "helm repo '$name' added"
  fi
}
add_repo dynatrace       https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
add_repo open-telemetry  https://open-telemetry.github.io/opentelemetry-helm-charts
add_repo cilium          https://helm.cilium.io
add_repo kagent          https://kagent-dev.github.io/kagent
helm repo update >/dev/null 2>&1 || warn "helm repo update had warnings (non-fatal, may be offline)"

ok "stack prep complete — namespaces + helm repos ready for Phase 2"
