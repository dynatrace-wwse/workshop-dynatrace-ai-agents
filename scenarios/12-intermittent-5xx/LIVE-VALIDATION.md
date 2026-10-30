<!-- ISI-6859 — turnkey live round-trip runbook for scenario 12 (intermittent-5xx).
     Static validation is done (ISI-6858). This file makes the LIVE run a single
     mechanical pass: run top-to-bottom in the live Codespace / cluster env, paste
     every captured block back into ISI-6859, and record the gRPC-stickiness verdict. -->

# Live validation runbook — scenario 12 (intermittent-5xx)

> **Automated equivalent:** `bash scenarios/12-intermittent-5xx/validate-live.sh` runs
> all of steps 1–4 below in one pass (inject → endpoint assert → 5xx-share probe +
> gRPC-stickiness verdict → optional Dynatrace Problems API poll when `DT_TENANT_URL`/
> `DT_API_TOKEN` are set → cleanup), exiting `0`/`2`/`3` per the ISI-6846 §2 contract.
> Use this runbook to capture/paste evidence by hand, or the script for a one-shot run.

**What this proves (ISI-6858 steps 1–4):** that `scenarios/run.sh inject 12` adds a
faulty `product-catalog` backend to the real `otel-demo-product-catalog` Service,
that a **fraction** (not all) of frontend product requests 5xx, that **Dynatrace
raises a problem with Davis root cause = `product-catalog`**, and that
`cleanup 12` leaves the healthy demo intact.

## Prerequisites (all must be true before step 1)

- [ ] **Live cluster + Docker.** A kind cluster the platform is installed on. No agent
      runtime today has Docker/kind — this runs in the ISI-6857 live Codespace (the
      path the board already self-serves) or any equivalent Docker-capable host.
- [ ] **ISI-6860 merged to `main`.** `cluster/install.sh` must self-register the Helm
      repos (commit `78a48c8`). Without it, install aborts at `Error: repo dynatrace
      not found` and the stack never deploys. Verify on the env's checkout:
      `grep -q 'add_repo dynatrace' cluster/install.sh && echo OK`.
- [ ] **Dynatrace tenant configured.** `DT_TENANT_URL` + an ingest/API token set so
      Davis raises the problem (otherwise step 3 cannot be observed).

---

## Step 1 — deploy demo + inject the fault

```bash
# deploy just the demo app (the platform stack is already installed by module 01):
helm upgrade --install otel-demo \
  oci://ghcr.io/henrikrexed/charts/opentelemetry-demo-light --version 0.2.8 \
  -n otel-demo --create-namespace \
  -f cluster/otel-demo/values-light.yaml --wait --timeout 8m
#   (or the all-in-one: INSTALL_OTEL_DEMO=true bash cluster/install.sh)
kubectl -n otel-demo rollout status deploy --timeout=180s   # let the demo settle
bash scenarios/run.sh inject 12                         # add the faulty backend
```

📋 **Capture:** the tail of `inject.sh` output — it should log
`faulty backend will carry the …product-catalog selector, listening on 3550`
and `faulty product-catalog backend injected into otel-demo (intermittent 5xx active)`.

## Step 2 — confirm two endpoints + a *fractional* 5xx rate

```bash
# (a) the faulty pod joined the Service — expect TWO addresses:
kubectl -n otel-demo get endpoints otel-demo-product-catalog -o wide
kubectl -n otel-demo get pods -l workshop.scenario=12-intermittent-5xx -o wide

# (b) drive product traffic from inside the frontend and tally status codes.
#     Loadgen (5 VUs) already exercises the product path; this adds a direct probe.
FE=$(kubectl -n otel-demo get pod -l app.kubernetes.io/component=frontend -o name | head -1)
kubectl -n otel-demo exec "$FE" -- sh -c '
  ok=0; err=0;
  for i in $(seq 1 60); do
    code=$(wget -q -O /dev/null -S "http://localhost:8080/api/products" 2>&1 | awk "/HTTP\//{c=\$2} END{print c}");
    case "$code" in 5*) err=$((err+1));; *) ok=$((ok+1));; esac;
  done;
  echo "product-path requests: ok=$ok err5xx=$err"'
```

📋 **Capture:** the `endpoints … -o wide` line (must show **2 addresses**) and the
`ok=… err5xx=…` tally.

### ⚠️ gRPC-stickiness verdict (the one thing static analysis can't settle)

gRPC frontend→product-catalog uses a long-lived HTTP/2 channel; kube-proxy
load-balances **per connection**, not per request. Read the tally:

| Observed | Verdict | Action |
|---|---|---|
| `0 < err5xx < ok` (a partial rate; both succeed and fail) | ✅ **intermittent** — matches `expected-diagnosis.md` | proceed to step 3 |
| `err5xx == 0` or `err5xx ≈ total` (all-or-nothing per client) | ❌ **sticky / not intermittent** | **do not** tighten diagnosis; escalate to the Architect ([ISI-6846](/ISI/issues/ISI-6846)) for a mechanism tweak (2+ faulty replicas, periodic restart of the faulty pod to force re-dials, or a request-level failing proxy) |

> Note: `inject.sh` currently injects **1** faulty replica. With 1 faulty + 1 healthy
> pod and per-connection LB, a single pinned channel can read all-or-nothing. Loadgen's
> 5 VUs + frontend reconnect churn *usually* aggregates to a partial rate — but this
> must be **observed**, not assumed. Record the raw tally either way.

## Step 3 — confirm the Dynatrace problem (Davis root cause = product-catalog)

Give Davis a few minutes after step 1, then in the DT tenant (Problems):

- Confirm an **open problem** on the frontend / product path.
- Confirm **Davis root cause = `product-catalog`** service entity.
  ⚠️ The k8s Service is `otel-demo-product-catalog` but the **DT service entity is
  `product-catalog`** (from `OTEL_SERVICE_NAME=product-catalog`). Do not expect the
  k8s Service name in the DT problem.

📋 **Capture:** the exact **problem title** and **problem id** (e.g.
`Failure rate increase on product-catalog` / `-<tenant>_…`). Then **tighten**
`expected-diagnosis.md` → `Required signals` to that exact wording (replace the
generic "an open Dynatrace problem affecting the frontend / product-catalog path"
with the observed title) and commit on a follow-up branch.

## Step 4 — cleanup leaves the healthy demo intact

```bash
bash scenarios/run.sh cleanup 12
kubectl -n otel-demo get deploy,pods -l workshop.scenario=12-intermittent-5xx   # expect: no resources
kubectl -n otel-demo get endpoints otel-demo-product-catalog -o wide            # expect: back to 1 address
kubectl -n otel-demo get deploy | grep -v degraded                              # healthy demo untouched
```

📋 **Capture:** the post-cleanup endpoints line (back to **1 address**) and that only
the `workshop.scenario=12-intermittent-5xx` Deployment was removed — the `otel-demo`
namespace and all healthy workloads remain.

---

## Pass/fail summary (paste into ISI-6859 when complete)

- [ ] Step 1 — demo deployed + fault injected (no `repo dynatrace not found`)
- [ ] Step 2a — `otel-demo-product-catalog` endpoints show **2 addresses**
- [ ] Step 2b — **fractional** 5xx (intermittent), gRPC-stickiness verdict = ✅ / ❌
- [ ] Step 3 — DT problem open, Davis root cause = `product-catalog`; title/id captured
- [ ] Step 4 — cleanup restores 1 endpoint; healthy demo intact

If step 2b reads ❌ (all-or-nothing) or the selector-discovery proves unworkable
against the fork, **stop and escalate to the Architect ([ISI-6846](/ISI/issues/ISI-6846))**
before tightening the diagnosis.
