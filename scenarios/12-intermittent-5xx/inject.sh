#!/usr/bin/env bash
# Scenario 12 — inject hook (override path per ISI-6846 §1.2).
#
# MECHANISM NOTE (divergence from ISI-6846 §4.4, surfaced to ISI-6847/Architect):
#   The contract assumed the fault was a *flagd feature-flag flip*. The selected
#   fork `henrikrexed/opentelemetry-demo-light` SHIPS NO flagd — it trims the
#   upstream OTel Demo to frontend/product-catalog/cart/checkout/payment (+postgres,
#   valkey, loadgen), confirmed in the fork tree and in cluster/versions.env
#   (ISI-6847). So there is no flag to flip. This hook instead injects an
#   equivalent, additive, reversible, release-name-agnostic fault that produces the
#   same observable (intermittent 5xx on the product path correlated in Dynatrace):
#
#   It discovers the `product-catalog` Service in otel-demo and adds a SECOND
#   backend Deployment carrying that Service's exact selector labels, but which
#   accepts connections on the gRPC port and never answers — so the Service
#   round-robins a FRACTION of product requests to a broken endpoint => intermittent
#   5xx. cleanup.sh removes only that injected Deployment; the healthy demo is never
#   touched and the otel-demo namespace is never deleted (Platform owns it).
#
#   !! NOT YET VALIDATED against a live deploy — ISI-6847 had not finished deploying
#      the demo at authoring time. Live round-trip validation is tracked as a child
#      issue blocked on ISI-6847. The selector-discovery below is written to adapt
#      to whatever release name ISI-6847 picks.
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
[ -n "${SVC}" ] || { err "no product-catalog Service found in ${DEMO_NS} — is the demo deployed? (INSTALL_OTEL_DEMO=true bash cluster/install.sh)"; exit 2; }
log "found ${SVC}"

# 2. Read the Service's selector labels + target port — the faulty backend must
#    carry the SAME labels so the Service routes a share of traffic to it.
PORT="$(kubectl -n "${DEMO_NS}" get "${SVC}" -o jsonpath='{.spec.ports[0].targetPort}')"
[ -n "${PORT}" ] || PORT=3550
# selector as "k=v,k=v" -> rebuild as YAML label lines.
mapfile -t SEL < <(kubectl -n "${DEMO_NS}" get "${SVC}" -o jsonpath='{range .spec.selector}{@}{"\n"}{end}' 2>/dev/null) || true
# jsonpath over a map is awkward; read keys/values explicitly instead.
SELECTOR_YAML="$(kubectl -n "${DEMO_NS}" get "${SVC}" -o json \
  | python3 -c 'import sys,json; s=json.load(sys.stdin)["spec"]["selector"]; print("\n".join(f"        {k}: \"{v}\"" for k,v in s.items()))')"
[ -n "${SELECTOR_YAML}" ] || { err "could not read ${SVC} selector labels"; exit 2; }
log "faulty backend will carry the product-catalog Service selector on port ${PORT}"

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
          command: ["/bin/sh", "-c", "while true; do nc -l -p ${PORT} >/dev/null 2>&1 || sleep 1; done"]
          ports:
            - containerPort: ${PORT}
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits:   { cpu: 50m, memory: 32Mi }
YAML

log "waiting for the faulty backend to join the Service endpoints..."
kubectl -n "${DEMO_NS}" rollout status deploy/${FAULT_NAME} --timeout=60s || warn "faulty backend not Ready yet — endpoints may lag"
ok "faulty product-catalog backend injected into ${DEMO_NS} (intermittent 5xx active)"
