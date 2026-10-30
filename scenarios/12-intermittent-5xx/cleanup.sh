#!/usr/bin/env bash
# Scenario 12 — cleanup hook (override path per ISI-6846 §1.2 / §4.4).
# Removes ONLY the injected faulty backend from the product-catalog Service. It
# NEVER deletes the astroshop-lite namespace or any healthy demo workload — the Platform
# install (ISI-6847) owns the demo's lifecycle. A missing fault is success, not an
# error (idempotent).
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HOOK_DIR}/../lib/common.sh"

DEMO_NS="astroshop-lite"
FAULT_NAME="product-catalog-degraded"

case " ${NS_ALLOWLIST[*]} " in *" ${DEMO_NS} "*) : ;; *) err "hook target ${DEMO_NS} not in allowlist"; exit 2 ;; esac

if ! kubectl get ns "${DEMO_NS}" >/dev/null 2>&1; then
  ok "astroshop-lite namespace absent — nothing to clean up"
  exit 0
fi

# Delete by the scenario marker label, so we remove exactly what inject.sh created
# and nothing the demo owns.
log "removing the faulty product-catalog backend from ${DEMO_NS}"
kubectl -n "${DEMO_NS}" delete deploy -l workshop.scenario=12-intermittent-5xx --ignore-not-found \
  || { err "failed to remove faulty backend"; exit 3; }
ok "faulty backend removed — product-catalog Service back to healthy endpoints only"
