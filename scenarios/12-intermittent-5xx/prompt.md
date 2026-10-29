# Intermittent 5xx on the astronomy-shop product path

The `opentelemetry-demo-light` astronomy shop (namespace `otel-demo`) is throwing
**intermittent** errors on the product/browse path. Ask the SRE agent to
investigate — **do not tell it the root cause**. This is the correlation scenario:
the agent must lean on **Dynatrace** (open problems, Davis root cause, the affected
entity) and correlate it with cluster state, not guess from `kubectl` alone.

## Drive it from the kagent UI

Open the kagent UI (`http://localhost:8080`), pick **sre-agent**, and paste:

> Users of the astronomy shop (namespace `otel-demo`) are seeing intermittent
> errors when they browse products — some requests work, some fail. Use Dynatrace
> to find the open problem and its Davis root cause, correlate it with the cluster
> state, and tell me which service is actually at fault and why.

## Drive it over A2A (curl)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"The astronomy shop in the otel-demo namespace is returning intermittent errors on the product browse path. Use Dynatrace to find the open problem and its Davis root cause, correlate it with the cluster state, and tell me which service is at fault and why. Cite the Dynatrace problem/entity you relied on."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

## What a correct answer looks like

The agent should cite an **open Dynatrace problem** on the frontend/product path,
name **`product-catalog`** as the **Davis root-cause entity** (not the frontend
that merely surfaces it), note the errors are **intermittent** (a partial error
rate, not a full outage), and corroborate with k8s that the `product-catalog`
Service has an **extra, unhealthy backend** in rotation. Grade against
[`expected-diagnosis.md`](./expected-diagnosis.md).

## Prerequisite — the app must be deployed

This scenario needs the opt-in demo app and Dynatrace. If `otel-demo` is not
present, `inject` fails fast with the enable command:

```bash
INSTALL_OTEL_DEMO=true bash cluster/install.sh     # one-time: deploy the demo (ISI-6847)
```

## Inject / clean up

```bash
bash scenarios/run.sh inject  12      # add a faulty product-catalog backend to the Service (flips in via inject.sh)
bash scenarios/run.sh cleanup 12      # remove the faulty backend (flips back via cleanup.sh) — never touches the healthy demo
```
