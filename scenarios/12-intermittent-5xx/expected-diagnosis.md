---
scenario: 12-intermittent-5xx
fault_family: app
namespace: otel-demo
requires: [cluster-state, dynatrace, otel-demo]
pass_threshold: 4
---

# Expected Diagnosis — Intermittent 5xx on the product path (Dynatrace correlation)

> **App scenario — needs the opt-in `opentelemetry-demo-light` app (ISI-6847) and
> Dynatrace.** Unlike 01–03 this fault lives in the `otel-demo` namespace and is
> graded partly on a **Dynatrace problem / Davis root cause** citation, not on
> cluster state alone. If `otel-demo` is not deployed, `run.sh inject 12` fails
> fast — this scenario is skippable on the minimum tier.

## Root cause (one sentence)
A faulty `product-catalog` backend has joined the `product-catalog` Service's endpoints, so a fraction of the frontend's product requests are load-balanced to it and fail — surfacing as intermittent 5xx on the astronomy-shop product/browse path, which Dynatrace raises as a problem with Davis pointing at the `product-catalog` service.

## Required signals (grader checks the agent cited ≥ pass_threshold of these)
- an **open Dynatrace problem** affecting the **frontend / product-catalog** path (cite the problem title or id)
- Davis / Dynatrace **root-cause entity = `product-catalog`** (the failing upstream service, not the frontend that merely surfaces it)
- the failures are **intermittent / a fraction of requests** (an elevated-but-partial error rate, not 100%), i.e. some product requests still succeed
- the errors are **5xx / gRPC errors on the product-catalog call path** (frontend → product-catalog), e.g. failed `GetProduct` / `ListProducts`
- k8s corroboration: the `product-catalog` **Service has more than one endpoint and one is unhealthy/faulty** (an extra backend Pod behind the same Service)

## Acceptable root-cause phrasings (any one satisfies the "root cause" check)
- "a bad product-catalog backend is serving a share of requests, causing intermittent 5xx"
- "part of the product-catalog fleet is faulty, so some frontend product requests fail"
- "Dynatrace shows product-catalog as the Davis root cause of intermittent errors on the frontend"

## Must NOT claim (negative signals — catch small-model confabulation)
- the **frontend itself** is the root cause (it only surfaces the upstream failure — Davis attributes it to product-catalog)
- a **total outage** / every request failing (the signal is *intermittent* — a partial error rate)
- a CrashLoopBackOff / OOMKilled / ImagePullBackOff of the *healthy* product-catalog pod (wrong family → scenarios 01–03)
- a database (postgres) or cart/checkout/payment outage as the primary cause without evidence

## Expected remediation (optional step — graded only if the attendee remediates)
Remove the faulty backend from rotation so the Service only routes to healthy `product-catalog` pods — `bash scenarios/run.sh cleanup 12` (the hook deletes the injected faulty Deployment; it never touches the healthy demo). An agent-driven remediation stays inside the non-destructive operate set (scale the faulty workload to 0, or re-apply the healthy manifest); no `k8s_delete_resource`.
