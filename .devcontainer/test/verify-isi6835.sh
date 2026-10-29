#!/usr/bin/env bash
# ISI-6835 Codespace bootstrap remediation — acceptance verifier (QA / ISI-6844).
#
# Maps 1:1 to `.devcontainer/ISI-6835-remediation-plan.md` §5 (acceptance) and the
# §4 end-state contract. Two tiers:
#
#   STATIC (A1–A12) — contract checks against the committed .devcontainer/** +
#     cluster/** sources. Runnable anywhere (no Docker/cluster needed). These prove
#     the implementation (ISI-6843) actually landed the kind + NodePort + deploy-on-
#     create model and retired k3d / the kagent CLI with no warnings-as-errors.
#
#   LIVE (L1–L5) — §5 acceptance proper: postCreate exits 0 + idempotent re-run,
#     kind `workshop` node Ready, pods reconciled/cleanly-skipped, Phoenix(6006) +
#     kagent-UI(8080) answer. Auto-SKIP (with a recorded reason) when run outside a
#     real Docker-in-Docker Codespace, so the script is safe to run anywhere.
#
# Usage:
#   bash .devcontainer/test/verify-isi6835.sh                 # static + live (auto-detect)
#   bash .devcontainer/test/verify-isi6835.sh --static        # static contract only
#   bash .devcontainer/test/verify-isi6835.sh --markdown FILE  # append results table to FILE
#   bash .devcontainer/test/verify-isi6835.sh --no-live        # alias for --static
#
# Exit code is non-zero only on a hard FAIL among applicable checks.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVC="$(cd "${HERE}/.." && pwd)"
REPO_ROOT="$(cd "${DEVC}/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-workshop}"

STATIC_ONLY=0
MD_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --static|--no-live) STATIC_ONLY=1 ;;
    --markdown) shift; MD_OUT="${1:-}" ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

have() { command -v "$1" >/dev/null 2>&1; }

PASS=0; FAIL=0; SKIP=0
ROWS=()
record() { # id "gate" RESULT "detail"
  local id="$1" gate="$2" res="$3" detail="$4"
  case "$res" in
    PASS) PASS=$((PASS+1)); printf '  \033[32m[ PASS ]\033[0m %-4s %s\n' "$id" "$gate" ;;
    FAIL) FAIL=$((FAIL+1)); printf '  \033[31m[ FAIL ]\033[0m %-4s %s — %s\n' "$id" "$gate" "$detail" ;;
    SKIP) SKIP=$((SKIP+1)); printf '  \033[33m[ SKIP ]\033[0m %-4s %s — %s\n' "$id" "$gate" "$detail" ;;
  esac
  ROWS+=("| ${id} | ${gate} | ${res} | ${detail} |")
}

# fileline helper: grep that returns the matching content or empty
g() { grep -nE "$1" "$2" 2>/dev/null; }

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# STATIC contract (A1–A12)
# ---------------------------------------------------------------------------
hdr "STATIC contract (§4 end-state)"

PC="${DEVC}/postCreate.sh"
LIB="${DEVC}/bootstrap/lib.sh"
INST="${DEVC}/bootstrap/install-tools.sh"
DOCKER="${DEVC}/Dockerfile"
DEVJSON="${DEVC}/devcontainer.json"
KINDCFG="${REPO_ROOT}/cluster/kind-config.yaml"
PHX="${REPO_ROOT}/cluster/phoenix/phoenix.yaml"
KAGV="${REPO_ROOT}/cluster/kagent/values.yaml"

# A1 — mkdocs NOT in the required-tool gate loop
req_loop="$(grep -nE '^\s*for\s+t\s+in\b' "$PC" 2>/dev/null | head -1)"
if [ -n "$req_loop" ] && echo "$req_loop" | grep -qw mkdocs; then
  record A1 "postCreate required gate excludes mkdocs" FAIL "mkdocs still in required loop: ${req_loop}"
elif [ -n "$req_loop" ]; then
  record A1 "postCreate required gate excludes mkdocs" PASS "required loop: ${req_loop#*:}"
else
  record A1 "postCreate required gate excludes mkdocs" FAIL "could not locate required-tool loop in postCreate.sh"
fi

# A2 — mkdocs + dt-evals are soft warnings (not in the fatal abort path)
if grep -qiE 'mkdocs|dt-evals' "$PC" && grep -qiE 'warn.*(mkdocs|dt-evals)|(mkdocs|dt-evals).*warn' "$PC"; then
  record A2 "mkdocs/dt-evals soft-warn" PASS "soft warn present"
else
  record A2 "mkdocs/dt-evals soft-warn" FAIL "no soft-warn path for mkdocs/dt-evals in postCreate.sh"
fi

# A3 — no kagent CLI gate/warn line
if grep -qiE 'kagent (CLI|cli)' "$PC"; then
  record A3 "no kagent-CLI reference in postCreate" FAIL "kagent-CLI line still present: $(g 'kagent' "$PC" | head -1)"
else
  record A3 "no kagent-CLI reference in postCreate" PASS "none"
fi

# A4 — postCreate deploys the stack via cluster/install.sh
if grep -qE 'cluster/install\.sh|install\.sh' "$PC"; then
  record A4 "postCreate deploys cluster/install.sh" PASS "$(g 'install\.sh' "$PC" | head -1 | cut -c1-80)"
else
  record A4 "postCreate deploys cluster/install.sh" FAIL "postCreate.sh does not invoke cluster/install.sh (still prep-stack only?)"
fi

# A5 — lib.sh default CLUSTER_TOOL=kind
if grep -qE 'CLUSTER_TOOL="?\$\{CLUSTER_TOOL:-kind\}"?' "$LIB"; then
  record A5 "lib.sh defaults CLUSTER_TOOL=kind" PASS "default=kind"
else
  record A5 "lib.sh defaults CLUSTER_TOOL=kind" FAIL "default is not kind: $(g 'CLUSTER_TOOL:-' "$LIB" | head -1)"
fi

# A6 — devcontainer.json CLUSTER_TOOL=kind
if grep -qE '"CLUSTER_TOOL"\s*:\s*"kind"' "$DEVJSON"; then
  record A6 "devcontainer.json CLUSTER_TOOL=kind" PASS "kind"
else
  record A6 "devcontainer.json CLUSTER_TOOL=kind" FAIL "not kind: $(g '"CLUSTER_TOOL"' "$DEVJSON" | head -1)"
fi

# A7 — k3d retired (config gone + no k3d refs that would warn-as-error)
k3d_hits="$(grep -rInE '\bk3d\b' "${DEVC}" "${REPO_ROOT}/cluster" 2>/dev/null \
  | grep -vE 'verify-isi6835\.sh|ISI-6835-remediation-plan|DECISIONS\.md|TEST-RESULTS|run-tests\.sh|/test/README' || true)"
if [ -e "${REPO_ROOT}/cluster/k3d-config.yaml" ]; then
  record A7 "k3d engine retired" FAIL "cluster/k3d-config.yaml still present"
elif [ -n "$k3d_hits" ]; then
  record A7 "k3d engine retired" FAIL "residual k3d refs: $(echo "$k3d_hits" | wc -l) line(s), e.g. $(echo "$k3d_hits" | head -1)"
else
  record A7 "k3d engine retired" PASS "no k3d-config, no residual k3d refs in .devcontainer/cluster"
fi

# A8 — kagent CLI install retired from the image
if grep -qE 'kagent CLI|/usr/local/bin/kagent|KAGENT_URL' "$INST"; then
  record A8 "kagent CLI removed from install-tools" FAIL "kagent-CLI install block still in install-tools.sh"
else
  record A8 "kagent CLI removed from install-tools" PASS "none"
fi

# A9 — Dockerfile has no K3D_VERSION / KAGENT_VERSION
if grep -qE 'K3D_VERSION|KAGENT_VERSION|k3d completion' "$DOCKER"; then
  record A9 "Dockerfile drops K3D/KAGENT ARGs" FAIL "residual: $(g 'K3D_VERSION|KAGENT_VERSION|k3d completion' "$DOCKER" | head -1)"
else
  record A9 "Dockerfile drops K3D/KAGENT ARGs" PASS "none"
fi

# A10 — kind-config.yaml NodePort extraPortMappings (30606->6006, 30080->8080), no ingress-ready
if grep -qE 'containerPort:\s*30606' "$KINDCFG" && grep -qE 'hostPort:\s*6006' "$KINDCFG" \
   && grep -qE 'containerPort:\s*30080' "$KINDCFG" && grep -qE 'hostPort:\s*8080' "$KINDCFG"; then
  if grep -qE 'ingress-ready' "$KINDCFG"; then
    record A10 "kind-config NodePort mappings" FAIL "NodePort mappings present but ingress-ready label still set"
  else
    record A10 "kind-config NodePort mappings" PASS "30606->6006, 30080->8080; no ingress-ready"
  fi
else
  record A10 "kind-config NodePort mappings" FAIL "missing 30606->6006 / 30080->8080 extraPortMappings"
fi

# A11 — phoenix.yaml Service NodePort + nodePort 30606 on the 6006 port
if awk '/kind:\s*Service/{s=1} s && /type:\s*NodePort/{t=1} s && /nodePort:\s*30606/{n=1} END{exit !(t&&n)}' "$PHX"; then
  record A11 "phoenix Service NodePort 30606" PASS "type NodePort + nodePort 30606"
else
  record A11 "phoenix Service NodePort 30606" FAIL "phoenix Service is not NodePort/30606: $(g 'type:|nodePort' "$PHX" | tr '\n' ' ' | cut -c1-80)"
fi

# A12 — kagent UI NodePort 30080 (chart values OR a companion NodePort Service)
kagent_np=""
grep -qE 'nodePort:\s*30080|30080' "$KAGV" 2>/dev/null && kagent_np="values.yaml"
if [ -z "$kagent_np" ]; then
  comp="$(grep -rlE 'nodePort:\s*30080|30080' "${REPO_ROOT}/cluster/kagent/" 2>/dev/null | head -1)"
  [ -n "$comp" ] && kagent_np="$(basename "$comp")"
fi
if [ -n "$kagent_np" ]; then
  record A12 "kagent UI NodePort 30080" PASS "exposed via ${kagent_np}"
else
  record A12 "kagent UI NodePort 30080" FAIL "no nodePort 30080 in cluster/kagent/ (values or companion Service)"
fi

# ---------------------------------------------------------------------------
# LIVE acceptance (L1–L5) — §5 proper
# ---------------------------------------------------------------------------
cluster_up() { have kubectl && kubectl get nodes >/dev/null 2>&1; }

if [ "$STATIC_ONLY" -eq 1 ]; then
  hdr "LIVE acceptance (§5) — skipped (--static)"
  for id in L1 L2 L3 L4 L5; do record "$id" "live §5 check" SKIP "static-only run"; done
else
  hdr "LIVE acceptance (§5)"
  if ! have docker || ! cluster_up; then
    why="no reachable kind cluster (needs a Docker-in-Docker Codespace after postCreate)"
    for id in L1 L2 L3 L4 L5; do record "$id" "live §5 check" SKIP "$why — run inside a fresh Codespace / devcontainer up"; done
  else
    # L1 — postCreate exits 0, idempotent re-run exits 0
    bash "${PC}" >/tmp/isi6835.pc1 2>&1; rc1=$?
    bash "${PC}" >/tmp/isi6835.pc2 2>&1; rc2=$?
    if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
      record L1 "postCreate exits 0 + idempotent" PASS "run1=0 run2=0"
    else
      record L1 "postCreate exits 0 + idempotent" FAIL "run1=${rc1} run2=${rc2} (see /tmp/isi6835.pc*)"
    fi
    # L2 — kind workshop node Ready
    if kubectl get nodes 2>/dev/null | grep -qE '\bReady\b'; then
      record L2 "kind ${CLUSTER_NAME} node Ready" PASS "$(kubectl get nodes --no-headers 2>/dev/null | head -1)"
    else
      record L2 "kind ${CLUSTER_NAME} node Ready" FAIL "no Ready node"
    fi
    # L3 — stack actually deployed: pods present in the component namespaces AND
    # none crash-looping. The pods-present check catches the ISI-6860 failure mode
    # where install.sh aborts (unregistered helm repos) and leaves empty namespaces
    # — a crash-only count passes on zero pods and would miss it entirely.
    pods=0
    for ns in kagent phoenix tetragon; do
      n="$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c . || true)"
      pods=$(( pods + ${n:-0} ))
    done
    crash="$(kubectl get pods -A --no-headers 2>/dev/null | grep -cE 'CrashLoopBackOff|Error|ImagePullBackOff' || true)"
    if [ "${pods:-0}" -eq 0 ]; then
      record L3 "stack deployed / no crash" FAIL "no pods in kagent/phoenix/tetragon — stack did not deploy (helm repos unregistered? see ISI-6860)"
    elif [ "${crash:-0}" -eq 0 ]; then
      record L3 "stack deployed / no crash" PASS "${pods} workload pod(s) present, no CrashLoop/Error across namespaces"
    else
      record L3 "stack deployed / no crash" FAIL "${crash} pod(s) crashing: $(kubectl get pods -A --no-headers 2>/dev/null | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' | head -1)"
    fi
    # L4 — Phoenix on 6006
    if have curl && curl -sf -o /dev/null --max-time 5 http://localhost:6006; then
      record L4 "Phoenix answers on :6006" PASS "200 via NodePort 30606"
    else
      record L4 "Phoenix answers on :6006" FAIL "localhost:6006 did not answer (NodePort 30606 mapping?)"
    fi
    # L5 — kagent UI on 8080
    if have curl && curl -sf -o /dev/null --max-time 5 http://localhost:8080; then
      record L5 "kagent UI answers on :8080" PASS "200 via NodePort 30080"
    else
      record L5 "kagent UI answers on :8080" FAIL "localhost:8080 did not answer (NodePort 30080 mapping?)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
hdr "Summary"
printf '  PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"

if [ -n "$MD_OUT" ]; then
  {
    echo ""
    echo "### ISI-6835 acceptance — \`verify-isi6835.sh\` (PASS=${PASS} FAIL=${FAIL} SKIP=${SKIP})"
    echo ""
    echo "| ID | Gate | Result | Detail |"
    echo "|----|------|--------|--------|"
    for r in "${ROWS[@]}"; do echo "$r"; done
  } >> "$MD_OUT"
  echo "  (results table appended to ${MD_OUT})"
fi

[ "$FAIL" -eq 0 ]
