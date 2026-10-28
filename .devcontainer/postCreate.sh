#!/usr/bin/env bash
# postCreate — runs once after the container is built (and re-runnable by hand).
# Boots the workshop cluster and preps the Phase 2 stack install. IDEMPOTENT.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
source "${SCRIPT_DIR}/bootstrap/lib.sh"

log "postCreate: engine=${CLUSTER_TOOL} cluster=${CLUSTER_NAME}"

# 1. Verify the toolchain baked into the image is present.
missing=0
for t in docker kubectl helm yq dtctl uv node mkdocs "$CLUSTER_TOOL"; do
  if have "$t"; then ok "tool: $t"; else err "tool MISSING: $t"; missing=1; fi
done
have kagent   && ok "tool: kagent"   || warn "kagent CLI not on PATH (see install-tools.sh notes)"
have dt-evals && ok "tool: dt-evals" || warn "dt-evals CLI not on PATH — run-dt-eval.sh falls back to npx (see evals/dt-evals/README.md)"
[ "$missing" -eq 0 ] || { err "required tools missing; aborting"; exit 1; }

# 2. Create (or reuse) the cluster.
bash "${SCRIPT_DIR}/bootstrap/create-cluster.sh"

# 3. Prep namespaces + helm repos for Phase 2 (no component installs here).
bash "${SCRIPT_DIR}/bootstrap/prep-stack.sh"

# 4. Report secret presence (non-fatal).
bash "${SCRIPT_DIR}/bootstrap/check-secrets.sh" || true

cat <<'EOF'

================================================================
 Phase 1 bootstrap complete.
   - Local Kubernetes cluster is running.
   - Namespaces + Helm repos staged for the Phase 2 platform install.
   - Toolchain: kubectl, helm, kind, k3d, kagent, yq, dtctl, uv, node,
     dt-evals, mkdocs ready.

 Next:
   kubectl get nodes
   mkdocs serve -a 0.0.0.0:8000      # workshop site on forwarded port 8000
   # Phase 2 installs the operators + kagent + Tetragon + Phoenix.
================================================================
EOF
