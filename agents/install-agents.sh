#!/usr/bin/env bash
# Phase 3 — deploy the MCP tool servers and both agent sets into the kagent
# namespace. Run AFTER the Phase 2 platform install (cluster/install.sh), which
# brings up kagent with the built-in kagent-tool-server (default Kubernetes
# tooling) enabled.
#
#   bash agents/install-agents.sh
#
# Credentials (read from the environment, injected at apply time — never committed):
#   GH_PAT         fine-grained PAT scoped to the ONE demo repo
#                      (Contents RW · Issues RW · Pull requests RW; NO org/admin).
#                      Required for the BMAD crew to touch GitHub.
#   DT_PLATFORM_TOKEN  Dynatrace platform token (dt0s16.*) for the SRE agent's
#                      Dynatrace MCP tools. Optional — without it the dynatrace
#                      tools install but return auth errors.
#   DT_ENVIRONMENT     Dynatrace platform (apps) URL, e.g.
#                      https://abc12345.apps.dynatrace.com. If unset, derived from
#                      DT_TENANT_URL by swapping .live. -> .apps.
#
# Idempotent: every step is `kubectl apply`, so re-running reconciles.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../cluster/versions.env
source "${REPO_ROOT}/cluster/versions.env"

log()  { printf '\033[1;34m[agents]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; }

kubectl cluster-info >/dev/null 2>&1 || { err "cluster not reachable — run cluster/install.sh first"; exit 1; }
command -v envsubst >/dev/null || { err "envsubst not found (gettext) — needed to inject tokens at apply time"; exit 1; }
kubectl get ns kagent >/dev/null 2>&1 || { err "namespace kagent missing — run cluster/install.sh (Phase 2) first"; exit 1; }

# --- preflight: default Kubernetes tooling must be present ------------------
if ! kubectl -n kagent get remotemcpserver kagent-tool-server >/dev/null 2>&1; then
  warn "kagent-tool-server not found — the SRE agent's k8s/networking tools need it."
  warn "Enable it: set kagent-tools.enabled=true in cluster/kagent/values.yaml and re-run cluster/install.sh."
fi

# --- credentials ------------------------------------------------------------
export GITHUB_MCP_IMAGE DYNATRACE_MCP_NODE_IMAGE DYNATRACE_MCP_PACKAGE
# Accept GITHUB_TOKEN (Codespaces injects one) as a fallback for GH_PAT. A
# fine-grained PAT scoped to the demo repo is strongly preferred for the write demo.
export GH_PAT="${GH_PAT:-${GITHUB_TOKEN:-}}"
export DT_PLATFORM_TOKEN="${DT_PLATFORM_TOKEN:-}"
# Derive the platform (apps) URL from the Phase-2 tenant URL if not given.
if [ -z "${DT_ENVIRONMENT:-}" ] && [ -n "${DT_TENANT_URL:-}" ]; then
  DT_ENVIRONMENT="${DT_TENANT_URL/.live./.apps.}"
  warn "DT_ENVIRONMENT not set — derived ${DT_ENVIRONMENT} from DT_TENANT_URL (override by exporting DT_ENVIRONMENT)."
fi
export DT_ENVIRONMENT="${DT_ENVIRONMENT:-}"

[ -n "${GH_PAT}" ]        || warn "GH_PAT unset — BMAD crew installs but GitHub tools will not authenticate."
[ -n "${DT_PLATFORM_TOKEN}" ] || warn "DT_PLATFORM_TOKEN unset — SRE agent installs but Dynatrace tools will not authenticate."

# Only these vars are substituted; every other $ in the manifests is left intact.
SUBST_VARS='${GITHUB_MCP_IMAGE} ${GH_PAT} ${DYNATRACE_MCP_NODE_IMAGE} ${DYNATRACE_MCP_PACKAGE} ${DT_ENVIRONMENT} ${DT_PLATFORM_TOKEN}'

# --- 1/3  MCP layer: shared ModelConfig + GitHub + Dynatrace tool servers ----
# Applied file-by-file (NOT via kustomize): kustomize round-trips flow scalars and
# would re-emit the Dynatrace package arg (@dynatrace-oss/...) unquoted → invalid
# YAML. envsubst on the raw files preserves the quoting.
log "1/3  MCP wiring (workshop-llm ModelConfig + GitHub + Dynatrace MCP servers)"
for f in 00-modelconfig.yaml 10-github-mcp.yaml 20-dynatrace-mcp.yaml; do
  envsubst "${SUBST_VARS}" < "${SCRIPT_DIR}/mcp/${f}" | kubectl apply -f -
done
ok "MCP layer applied"

# --- 2/3  SRE agent ----------------------------------------------------------
log "2/3  SRE agent"
kubectl apply -k "${SCRIPT_DIR}/sre"
ok "SRE agent applied"

# --- 3/3  BMAD crew ----------------------------------------------------------
log "3/3  BMAD crew (analyst, pm, architect, developer, qa, orchestrator)"
kubectl apply -k "${SCRIPT_DIR}/bmad-crew"
ok "BMAD crew applied"

cat <<'EOF'

================================================================
 Phase 3 agents & MCP wiring applied.

 Verify the tool servers registered their tools:
   kubectl -n kagent get mcpserver,remotemcpserver
   kubectl -n kagent get remotemcpserver kagent-tool-server   -o jsonpath='{.status.discoveredTools[*].name}'; echo
   kubectl -n kagent get remotemcpserver github-mcp-remote     -o jsonpath='{.status.discoveredTools[*].name}'; echo
   kubectl -n kagent get remotemcpserver dynatrace-mcp-remote  -o jsonpath='{.status.discoveredTools[*].name}'; echo

 Verify the agents are Accepted:
   kubectl -n kagent get agents

 Sample prompts over A2A (controller on :8083) — SRE agent:
   kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
     --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
     --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List the pods in the kagent namespace and tell me if any are unhealthy."}]}}}' \
     http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent

 BMAD orchestrator (swap the text for your demo repo + task):
   ... http://kagent-controller.kagent:8083/api/a2a/kagent/bmad-orchestrator

 Or use the kagent UI:  kubectl -n kagent port-forward svc/kagent-ui 8080:8080

 Traces: kagent otel.tracing (Phase 2) fans agent LLM/tool spans to Dynatrace +
 Phoenix via otel-gateway-collector.opentelemetry-operator-system.svc:4317.
================================================================
EOF
