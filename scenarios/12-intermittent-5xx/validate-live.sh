#!/usr/bin/env bash
# Scenario 12 — LIVE round-trip validation harness (ISI-6859 / steps 1-4 of ISI-6858).
#
# WHY THIS EXISTS
#   The static validation (ISI-6858) proved inject.sh/cleanup.sh are correctly wired
#   to the real opentelemetry-demo-light 0.2.8 chart. What static analysis *cannot*
#   settle is the live behaviour — above all the gRPC-stickiness question: gRPC
#   clients hold a long-lived HTTP/2 channel to the ClusterIP, and kube-proxy
#   load-balances PER CONNECTION, not per request. So a frontend channel pinned to
#   the healthy pod sees 0 errors and one pinned to the faulty pod may see ~100% —
#   which could make the fault read ALL-OR-NOTHING per client rather than the
#   intended "intermittent". This harness MEASURES that, end to end, and captures the
#   exact evidence ISI-6859 owes, so the eventual live run (a Codespace with a
#   Dynatrace tenant, as the board self-served for ISI-6835 §5 / ISI-6857) is one
#   copy-paste instead of a hand-run checklist.
#
# PREREQUISITES (the harness checks these and fails fast — exit 2 — if missing):
#   - a running cluster with the platform stack installed (needs ISI-6860 merged so
#     `cluster/install.sh` actually deploys the stack) AND the opt-in demo:
#         INSTALL_OTEL_DEMO=true bash cluster/install.sh
#   - for the Dynatrace assertion (step 3): export DT_TENANT_URL and DT_API_TOKEN
#     (token needs problems.read). Without them the harness still runs steps 1,2,4
#     and prints the manual DT capture steps instead of failing.
#
# USAGE
#   bash scenarios/12-intermittent-5xx/validate-live.sh            # full round-trip
#   PROBE_COUNT=60 bash .../validate-live.sh                       # more HTTP samples
#   SKIP_CLEANUP=1 bash .../validate-live.sh                       # leave fault in place
#   FRONTEND_SVC=otel-demo-frontend PRODUCTS_PATH=/api/products bash .../validate-live.sh
#
# EXIT CODES (match the ISI-6846 §2 contract run.sh grades against):
#   0 all live assertions passed · 2 precondition failure · 3 a live assertion failed
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

DEMO_NS="otel-demo"
FAULT_NAME="product-catalog-degraded"
RUN_SH="${SCENARIOS_DIR}/run.sh"

# Tunables (env-overridable).
PROBE_COUNT="${PROBE_COUNT:-40}"          # how many frontend product requests to sample
PROBE_IMAGE="${PROBE_IMAGE:-curlimages/curl:8.10.1}"
FRONTEND_SVC="${FRONTEND_SVC:-}"          # auto-discovered by name suffix if empty
FRONTEND_PORT="${FRONTEND_PORT:-8080}"
PRODUCTS_PATH="${PRODUCTS_PATH:-/api/products}"
DT_PROBLEM_LOOKBACK="${DT_PROBLEM_LOOKBACK:-now-30m}"
SKIP_CLEANUP="${SKIP_CLEANUP:-0}"

PASS=0 FAIL=0
pass() { ok "$*"; PASS=$((PASS+1)); }
fail() { err "$*"; FAIL=$((FAIL+1)); }

# endpoint_count <svc-name> -> number of ready+notReady addresses behind the Service.
endpoint_count() {
  kubectl -n "${DEMO_NS}" get endpoints "$1" -o json 2>/dev/null \
    | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit()
n=0
for s in d.get("subsets",[]) or []:
    n+=len(s.get("addresses",[]) or [])+len(s.get("notReadyAddresses",[]) or [])
print(n)'
}

# ---------------------------------------------------------------------------
# STEP 0 — preconditions
# ---------------------------------------------------------------------------
log "STEP 0 — preconditions"
require_cluster || exit 2
kubectl get ns "${DEMO_NS}" >/dev/null 2>&1 \
  || { err "namespace ${DEMO_NS} absent — run: INSTALL_OTEL_DEMO=true bash cluster/install.sh"; exit 2; }

SVC_NAME="$(kubectl -n "${DEMO_NS}" get svc -o name 2>/dev/null | sed 's#^service/##' | grep -E 'product-catalog$' | head -1 || true)"
[ -n "${SVC_NAME}" ] || { err "no product-catalog Service in ${DEMO_NS} — is the demo deployed?"; exit 2; }
pass "product-catalog Service present: ${SVC_NAME}"

# Discover the frontend Service for the HTTP probe (exclude *-proxy / *-frontendproxy).
if [ -z "${FRONTEND_SVC}" ]; then
  FRONTEND_SVC="$(kubectl -n "${DEMO_NS}" get svc -o name 2>/dev/null | sed 's#^service/##' \
    | grep -E 'frontend$' | grep -vE 'proxy' | head -1 || true)"
fi
[ -n "${FRONTEND_SVC}" ] || warn "frontend Service not found — the HTTP 5xx probe (step 2b) will be skipped"

# ---------------------------------------------------------------------------
# STEP 1 — inject the fault
# ---------------------------------------------------------------------------
log "STEP 1 — inject scenario 12"
BASELINE_EP="$(endpoint_count "${SVC_NAME}")"
log "baseline ${SVC_NAME} endpoints: ${BASELINE_EP}"
bash "${RUN_SH}" inject 12 || { err "inject failed"; exit 3; }

# ---------------------------------------------------------------------------
# STEP 2a — the faulty backend joined the Service endpoints (needs 2 addresses)
# ---------------------------------------------------------------------------
log "STEP 2a — confirm the faulty backend joined the Service endpoints"
# Give endpoints a moment to converge (the injected pod has no readiness probe, so
# it registers as an endpoint quickly, but allow for kubelet/endpoint-controller lag).
AFTER_EP=0
for _ in $(seq 1 15); do
  AFTER_EP="$(endpoint_count "${SVC_NAME}")"
  [ "${AFTER_EP}" -ge 2 ] && break
  sleep 2
done
kubectl -n "${DEMO_NS}" get endpoints "${SVC_NAME}" -o wide || true
if [ "${AFTER_EP}" -ge 2 ]; then
  pass "STEP 2 (endpoints): ${SVC_NAME} now has ${AFTER_EP} addresses (healthy + injected faulty)"
else
  fail "STEP 2 (endpoints): expected >=2 addresses, saw ${AFTER_EP} — faulty backend did not join the Service"
fi

# ---------------------------------------------------------------------------
# STEP 2b — the fraction of frontend product requests that 5xx (the gRPC-stickiness read)
# ---------------------------------------------------------------------------
# This is the one thing static analysis can't settle. We fire PROBE_COUNT fresh HTTP
# requests at the frontend's product endpoint and count 5xx. The frontend holds a
# long-lived gRPC channel to the product-catalog ClusterIP, so this reads the REAL
# per-client channel behaviour the workshop will exhibit:
#   - share ≈ 0%            -> frontend channel pinned to the HEALTHY pod (all-or-nothing)
#   - share ≈ 100%          -> frontend channel pinned to the FAULTY pod (all-or-nothing)
#   - 0% < share < 100%     -> INTERMITTENT in aggregate (the intended signal) ✅
# If it reads all-or-nothing, that is the signal to escalate to the Architect
# (ISI-6846) for a mechanism tweak (2+ faulty replicas / periodic faulty-pod restart
# to force re-dials / a proxy that fails a share of requests).
if [ -n "${FRONTEND_SVC}" ]; then
  log "STEP 2b — sampling ${PROBE_COUNT} frontend requests to ${PRODUCTS_PATH} (gRPC-stickiness read)"
  URL="http://${FRONTEND_SVC}.${DEMO_NS}.svc.cluster.local:${FRONTEND_PORT}${PRODUCTS_PATH}"
  # One throwaway pod loops curl and prints one HTTP status code per line.
  CODES="$(kubectl -n "${DEMO_NS}" run scn12-probe-$$ --rm -i --restart=Never \
      --image="${PROBE_IMAGE}" --command -- sh -c \
      "for i in \$(seq 1 ${PROBE_COUNT}); do curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 '${URL}' || echo 000; done" \
      2>/dev/null || true)"
  if [ -z "${CODES}" ]; then
    warn "STEP 2b: probe produced no output (URL/path may differ in this fork; override with FRONTEND_SVC/PRODUCTS_PATH) — read the fraction from Dynatrace in step 3 instead"
  else
    TOTAL="$(printf '%s\n' "${CODES}" | grep -cE '^[0-9]{3}$' || true)"
    ERRS="$(printf '%s\n' "${CODES}" | grep -cE '^(5[0-9]{2}|000)$' || true)"
    OKS=$((TOTAL - ERRS))
    SHARE=$(( TOTAL>0 ? ERRS*100/TOTAL : 0 ))
    log "frontend product requests: ${OKS}/${TOTAL} ok, ${ERRS}/${TOTAL} failed (${SHARE}% error share)"
    if [ "${ERRS}" -gt 0 ] && [ "${OKS}" -gt 0 ]; then
      pass "STEP 2 (intermittent): ${SHARE}% of product requests 5xx — a FRACTION, not total → reads as intermittent ✅"
    elif [ "${ERRS}" -eq 0 ]; then
      fail "STEP 2 (intermittent): 0% errors — frontend channel appears PINNED to the healthy pod (gRPC-stickiness all-or-nothing). ESCALATE to Architect ISI-6846 for a mechanism tweak."
    else
      fail "STEP 2 (intermittent): ${SHARE}% errors (≈total) — frontend channel appears PINNED to the faulty pod. ESCALATE to Architect ISI-6846 for a mechanism tweak."
    fi
  fi
else
  warn "STEP 2b skipped (no frontend Service) — read the intermittent error share from Dynatrace in step 3"
fi

# ---------------------------------------------------------------------------
# STEP 3 — Dynatrace raises a problem with Davis root cause = product-catalog
# ---------------------------------------------------------------------------
log "STEP 3 — Dynatrace problem (Davis root cause = product-catalog)"
if [ -n "${DT_TENANT_URL:-}" ] && [ -n "${DT_API_TOKEN:-}" ]; then
  log "querying ${DT_TENANT_URL%/}/api/v2/problems (OPEN, from=${DT_PROBLEM_LOOKBACK}) ..."
  # Davis can take a few minutes to open a problem after errors start — poll a while.
  DT_HIT=""
  for _ in $(seq 1 20); do
    RESP="$(curl -s --max-time 15 \
      -H "Authorization: Api-Token ${DT_API_TOKEN}" \
      "${DT_TENANT_URL%/}/api/v2/problems?from=${DT_PROBLEM_LOOKBACK}&problemSelector=status(%22OPEN%22)&fields=evidenceDetails,affectedEntities" \
      2>/dev/null || true)"
    DT_HIT="$(printf '%s' "${RESP}" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for p in d.get("problems",[]) or []:
    blob=json.dumps(p).lower()
    if "product-catalog" in blob or "productcatalog" in blob:
        print(f"{p.get(\"problemId\",\"?\")}\t{p.get(\"title\",\"?\")}")
        break
' 2>/dev/null || true)"
    [ -n "${DT_HIT}" ] && break
    sleep 15
  done
  if [ -n "${DT_HIT}" ]; then
    PID="${DT_HIT%%$'\t'*}"; PTITLE="${DT_HIT#*$'\t'}"
    pass "STEP 3 (Dynatrace): OPEN problem referencing product-catalog — id=${PID} title=\"${PTITLE}\""
    cat <<EON
  ┌─ ACTION: tighten expected-diagnosis.md 'Required signals' to this exact wording:
  │    problem id    : ${PID}
  │    problem title : ${PTITLE}
  │  Verify in the DT UI that the Davis ROOT-CAUSE entity is the 'product-catalog'
  │  service (OTEL_SERVICE_NAME=product-catalog), NOT 'frontend'. Capture a screenshot
  │  of the problem's root-cause panel and attach it to ISI-6859.
  └─
EON
  else
    fail "STEP 3 (Dynatrace): no OPEN problem referencing product-catalog yet. Davis may need more error volume/time, or the entity name differs. Re-run with a longer DT_PROBLEM_LOOKBACK, or inspect the DT UI manually (steps below)."
  fi
else
  warn "STEP 3 (Dynatrace): DT_TENANT_URL / DT_API_TOKEN not set — cannot auto-verify. Capture manually:"
  cat <<'EON'
  1. Dynatrace UI → Problems: find the OPEN problem on the frontend → product path.
  2. Open it → confirm the Davis ROOT-CAUSE entity is the 'product-catalog' service
     (OTEL_SERVICE_NAME=product-catalog; the k8s Service is 'otel-demo-product-catalog'
     but the DT service entity is 'product-catalog'). Capture the problem title + id.
  3. Confirm the failure rate is a FRACTION (intermittent), not 100%.
  4. DQL (Problems/Davis): fetch dt.davis.problems | filter matchesValue(affected_entity_ids, "*product-catalog*")
  5. Tighten expected-diagnosis.md 'Required signals' to the captured title/id and
     attach a screenshot of the root-cause panel to ISI-6859.
EON
fi

# ---------------------------------------------------------------------------
# STEP 4 — cleanup leaves the healthy demo intact
# ---------------------------------------------------------------------------
if [ "${SKIP_CLEANUP}" = "1" ]; then
  warn "STEP 4 skipped (SKIP_CLEANUP=1) — fault left in place; run 'bash scenarios/run.sh cleanup 12' to remove it"
else
  log "STEP 4 — cleanup and confirm the healthy demo survives"
  bash "${RUN_SH}" cleanup 12 || { err "cleanup failed"; exit 3; }
  POST_EP=0
  for _ in $(seq 1 15); do
    POST_EP="$(endpoint_count "${SVC_NAME}")"
    [ "${POST_EP}" -le "${BASELINE_EP}" ] && [ "${POST_EP}" -ge 1 ] && break
    sleep 2
  done
  NS_OK=0;  kubectl get ns "${DEMO_NS}" >/dev/null 2>&1 && NS_OK=1
  FAULT_GONE=1; kubectl -n "${DEMO_NS}" get deploy "${FAULT_NAME}" >/dev/null 2>&1 && FAULT_GONE=0
  if [ "${NS_OK}" = 1 ] && [ "${FAULT_GONE}" = 1 ] && [ "${POST_EP}" -ge 1 ]; then
    pass "STEP 4 (cleanup): faulty backend removed, ${SVC_NAME} back to ${POST_EP} endpoint(s), ${DEMO_NS} namespace intact"
  else
    fail "STEP 4 (cleanup): ns_present=${NS_OK} fault_removed=${FAULT_GONE} endpoints=${POST_EP} — demo not left clean"
  fi
fi

# ---------------------------------------------------------------------------
echo
log "────────── live validation summary ──────────"
log "passed: ${PASS}   failed: ${FAIL}"
if [ "${FAIL}" -eq 0 ]; then
  ok "scenario 12 live round-trip VALIDATED"
  exit 0
fi
err "scenario 12 live round-trip has ${FAIL} failing assertion(s) — see above"
exit 3
