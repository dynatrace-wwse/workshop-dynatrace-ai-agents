# cluster/otel — OpenTelemetry Operator + gateway collector

Installs the OpenTelemetry Operator and a single **gateway** collector that all
agent/LLM telemetry flows through, fanning out to the Dynatrace tenant and Phoenix.

| File | Role |
|------|------|
| `operator-values.yaml` | Helm values for `open-telemetry/opentelemetry-operator`. |
| `collector-gateway.yaml` | `OpenTelemetryCollector` CR (deployment mode). |
| `bindplane-illustrated.md` | BindPlane walkthrough (illustrated only — see below). |

## Why `autoGenerateCert`

A fresh kind cluster has **no cert-manager**. The operator's admission
webhook therefore uses a self-signed cert the chart generates itself
(`admissionWebhooks.autoGenerateCert.enabled: true`,
`certManager.enabled: false`). Omitting this makes the operator hang.

## Pipeline

Agents/workloads send OTLP to
`otel-gateway-collector.opentelemetry-operator-system.svc.cluster.local:4317`
(gRPC) / `:4318` (HTTP). The collector:

1. enriches spans with k8s attributes + `k8s.cluster.name`,
2. normalises OpenInference/Traceloop LLM attributes → OpenTelemetry `gen_ai.*`
   semconv (`transform/genai-normalize`), so Dynatrace and Phoenix agree on names,
3. fans out: **traces** → Dynatrace + Phoenix; **metrics/logs** → Dynatrace.

> **Recommended for production — the `genainormalizer` processor.** We normalise
> with a few OTTL `set()` statements because the workshop runs the lighter
> `opentelemetry-collector-k8s` distro (see `operator-values.yaml`). Outside the
> workshop, prefer the purpose-built
> [`genainormalizerprocessor`](https://explorer.opentelemetry.io/collector/components/contrib/genainormalizerprocessor?type=processor&version=0.155.0):
> it ships maintained, richer mappings for OpenInference and OpenLLMetry/Traceloop
> (token counts, model names, request params, finish reasons) targeting GenAI
> semconv v1.40.0, instead of a mapping table you maintain by hand.
>
> ```yaml
> processors:
>   genainormalizer:
>     sources:
>       - name: openinference
>       - name: openllmetry      # Traceloop
>         remove_originals: true
> ```
>
> It is a **contrib** component (Alpha for traces) and is *not* in the k8s distro,
> so adopting it means switching `collectorImage` to the heavier
> `opentelemetry-collector-contrib` image (or a custom OCB build that adds just
> this processor).

Dynatrace export credentials come from `secret/dynatrace-otlp` (created by
`secrets.sh`); if absent, Phoenix export keeps working and the collector just
logs auth errors.

## BindPlane — illustrated only

BindPlane is **illustrated, not installed**:
a short walkthrough + screenshots of how BindPlane manages OTel collectors,
kept lightweight so it doesn't bloat the Codespace. See `bindplane-illustrated.md`.
A live BindPlane instance is a self-contained add-on (agent + Helm chart) that
does not change this pipeline, if you want to run one instead.

## Verify

```bash
kubectl get otelcol -n opentelemetry-operator-system
kubectl -n opentelemetry-operator-system get pods   # operator + otel-gateway-collector Ready
```
