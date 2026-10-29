#!/usr/bin/env bash
# postCreate — runs once after the container is built (and re-runnable by hand).
# Boots the workshop cluster and preps the Phase 2 stack install. IDEMPOTENT.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
source "${SCRIPT_DIR}/bootstrap/lib.sh"

log "postCreate: engine=${CLUSTER_TOOL} cluster=${CLUSTER_NAME}"

# 1. Verify the REQUIRED toolchain baked into the image is present.
#    Only the tools the bootstrap genuinely cannot proceed without are fatal.
#    mkdocs (local docs preview) and dt-evals (Phase 4, npx fallback exists) are
#    best-effort and must NEVER abort the Codespace — they are soft warnings.
missing=0
for t in kubectl helm kind dtctl node; do
  if have "$t"; then ok "tool: $t"; else err "tool MISSING: $t"; missing=1; fi
done
have mkdocs   && ok "tool: mkdocs"   || warn "mkdocs not on PATH — local docs preview unavailable (read the published site); non-fatal"
have dt-evals && ok "tool: dt-evals" || warn "dt-evals not on PATH — run-dt-eval.sh falls back to npx (see evals/dt-evals/README.md); non-fatal"
[ "$missing" -eq 0 ] || { err "required tools missing; aborting"; exit 1; }

# 2. Create (or reuse) the kind cluster (NodePort port-mappings → forwarded ports).
bash "${SCRIPT_DIR}/bootstrap/create-cluster.sh"

# 3. Deploy the full workshop platform. Non-fatal: a single failing component
#    (e.g. a missing secret) must never brick the Codespace — install.sh degrades
#    gracefully and per-component INSTALL_<COMPONENT>=false toggles still apply.
bash "${REPO_ROOT}/cluster/install.sh" || warn "cluster/install.sh reported issues — see output above; re-run manually with 'bash cluster/install.sh'"

# 4. Report secret presence (non-fatal).
bash "${SCRIPT_DIR}/bootstrap/check-secrets.sh" || true

cat <<'EOF'

================================================================
 Workshop bootstrap complete.
   - kind cluster 'workshop' is running.
   - The platform stack was deployed by cluster/install.sh (components with a
     missing secret are skipped cleanly, never fatal).
   - Toolchain: kubectl, helm, kind, yq, dtctl, uv, node, dt-evals, mkdocs.

 UIs (forwarded Codespace ports, via kind NodePort mappings):
   Phoenix   -> http://localhost:6006
   kagent UI -> http://localhost:8080

 Next:
   kubectl get nodes
   kubectl get pods -A
   mkdocs serve -a 0.0.0.0:8000      # workshop site on forwarded port 8000 (optional)
================================================================
EOF
