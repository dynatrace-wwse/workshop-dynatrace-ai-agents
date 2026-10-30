#!/usr/bin/env bash
# Scenario 12 — inject hook (override path per ISI-6846 §1.2 / §4.4 rev 2).
#
# MECHANISM (ratified by the Architect in ISI-6846 §4.4 rev 2, ISI-6856):
#   The fork `henrikrexed/opentelemetry-demo-light` SHIPS NO flagd — it trims the
#   upstream OTel Demo to frontend/product-catalog/cart/checkout/payment (+postgres,
#   valkey, loadgen), confirmed in the fork tree and in cluster/versions.env
#   (ISI-6847). So the contract's original flagd flag-flip has no flag to flip; §4.4
#   rev 2 replaces it with the additive, reversible, release-name-agnostic fault
#   implemented here, which produces the same observable (intermittent 5xx on the
#   product path, correlated in Dynatrace to the product-catalog entity):
#
#   It discovers the `product-catalog` Service in otel-demo and adds a SECOND
#   backend Deployment carrying that Service's exact selector labels, but which
#   accepts connections on the gRPC port and never answers — so the Service
#   round-robins a FRACTION of product requests to a broken endpoint => intermittent
#   5xx. cleanup.sh removes only that injected Deployment; the healthy demo is never
#   touched and the otel-demo namespace is never deleted (Platform owns it).
#
#   !! LIVE ROUND-TRIP VALIDATION STILL OWED (ISI-6848) — ISI-6847's demo deploy is
#      now done (PR #14), which unblocks it. Before marking #12 validated, close the
#      three §4.4-rev-2 hardening items: (1) resolve a NAMED gRPC targetPort to a
#      number (the PORT=3550 fallback below only fires when the lookup is empty, not
#      when it is a name like "grpc"); (2) sanity-check the failing share (~50% with
#      one healthy replica — intermittent but high); (3) confirm the injected pod
#      joins the Service endpoints and the 5xx raises a Dynatrace problem with Davis
#      root-cause = product-catalog. Selector-discovery adapts to any release name.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

DEMO_NS="otel-demo"
FAULT_NAME="product-catalog-degraded"   # the injected faulty backend

# Hard allowlist guard: this hook may ONLY touch otel-demo.
case " ${NS_ALLOWLIST[*]} " in *" ${DEMO_NS} "*) : ;; *) err "hook target ${DEMO_NS} not in allowlist"; exit 2 ;; esac

# 1. Find the product-catalog Service (release-name agnostic: match by name suffix).
SVC="$(kubectl -n "${DEMO_NS}" get svc -o name 2>/dev/null | grep -E 'product-catalog$' | head -1 || true)"
[ -n "${SVC}" ] || { err "no product-catalog Service found in ${DEMO_NS} — is the demo deployed? (helm upgrade --install otel-demo oci://ghcr.io/henrikrexed/charts/opentelemetry-demo-light --version 0.2.8 -n otel-demo --create-namespace -f cluster/otel-demo/values-light.yaml --wait)"; exit 2; }
log "found ${SVC}"

# 2. Read the Service's selector labels + target port — the faulty backend must
#    carry the SAME labels so the Service routes a share of traffic to it.
#    targetPort may be a NUMBER (3550) or a NAMED port ("grpc"). Resolve both:
#      - numeric targetPort  -> the faulty container listens on that number, unnamed.
#      - named targetPort    -> the faulty container exposes a port with that NAME,
#        bound to the Service's numeric .spec.ports[0].port (3550 fallback), so the
#        Service (targetPort=<name>) still routes to the faulty pod.
#    (§4.4-rev-2 hardening item 1 — ISI-6856.)
TARGET_PORT="$(kubectl -n "${DEMO_NS}" get "${SVC}" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)"
SVC_PORT="$(kubectl -n "${DEMO_NS}" get "${SVC}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
if [[ "${TARGET_PORT}" =~ ^[0-9]+$ ]]; then
  LISTEN_PORT="${TARGET_PORT}"; PORT_NAME=""
else
  # named (or empty) targetPort -> listen on the numeric Service port, keep the name.
  LISTEN_PORT="${SVC_PORT:-3550}"; PORT_NAME="${TARGET_PORT}"
fi
# selector as a map -> YAML label lines (jsonpath over a map is awkward; use python).
SELECTOR_YAML="$(kubectl -n "${DEMO_NS}" get "${SVC}" -o json \
  | python3 -c 'import sys,json; s=json.load(sys.stdin)["spec"]["selector"]; print("\n".join(f"        {k}: \"{v}\"" for k,v in s.items()))')"
[ -n "${SELECTOR_YAML}" ] || { err "could not read ${SVC} selector labels"; exit 2; }
# Build the container port block (add `name:` only for a named targetPort).
PORT_BLOCK="            - containerPort: ${LISTEN_PORT}"
[ -n "${PORT_NAME}" ] && PORT_BLOCK="${PORT_BLOCK}
              name: ${PORT_NAME}"
log "faulty backend will carry the ${SVC##*/} selector, listening on ${LISTEN_PORT}${PORT_NAME:+ (named ${PORT_NAME})}"

# 3. Apply the faulty backend. It binds the gRPC port with netcat but never speaks
#    gRPC, so calls routed to it fail — and it has NO readiness probe, so it stays
#    an endpoint. The labels are the Service selector PLUS a marker label we can
#    delete by, pinned into otel-demo.
kubectl apply -f - <<YAML || { err "failed to apply faulty backend"; exit 3; }
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${FAULT_NAME}
  namespace: ${DEMO_NS}
  labels:
    workshop.scenario: "12-intermittent-5xx"
spec:
  replicas: 1
  selector:
    matchLabels:
      workshop.scenario: "12-intermittent-5xx"
  template:
    metadata:
      labels:
        workshop.scenario: "12-intermittent-5xx"
${SELECTOR_YAML}
    spec:
      containers:
        - name: broken-backend
          image: busybox:1.36
          # Accept TCP connects on the gRPC port but never answer -> gRPC calls fail.
          command: ["/bin/sh", "-c", "while true; do nc -l -p ${LISTEN_PORT} >/dev/null 2>&1 || sleep 1; done"]
          ports:
${PORT_BLOCK}
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits:   { cpu: 50m, memory: 32Mi }
YAML

log "waiting for the faulty backend to join the Service endpoints..."
kubectl -n "${DEMO_NS}" rollout status deploy/${FAULT_NAME} --timeout=60s || warn "faulty backend not Ready yet — endpoints may lag"
ok "faulty product-catalog backend injected into ${DEMO_NS} (intermittent 5xx active)"
