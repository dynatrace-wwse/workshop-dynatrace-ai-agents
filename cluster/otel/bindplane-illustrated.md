# BindPlane — illustrated walkthrough (no live install)

> **Scope:** the workshop *illustrates* BindPlane as a way to manage
> OpenTelemetry collectors — it is **not** deployed into the Codespace, to keep
> the footprint small. This page is the script + screenshot placeholders for that
> walkthrough. Switching to a live instance is additive and does not change the
> `otel/collector-gateway.yaml` pipeline.

## What to show (5 minutes)

1. **The problem BindPlane solves.** In this workshop we hand-author
   `collector-gateway.yaml`. BindPlane is a control plane that manages collector
   configs across many agents/gateways from a UI — versioned configs, live
   rollouts, and a processor/pipeline builder.

2. **Map our pipeline onto BindPlane concepts:**
   | Our manifest | BindPlane concept |
   |--------------|-------------------|
   | `receivers.otlp` | a **Source** (OTLP) |
   | `processors` (batch, k8sattributes, transform) | **Processors** on the pipeline |
   | `exporters` (Dynatrace, Phoenix) | **Destinations** |
   | the `OpenTelemetryCollector` CR | a managed **Configuration** applied to agents |

3. **Screens to capture** (add to `docs/` when recorded):
   - `bindplane-01-topology.png` — agent/gateway topology graph.
   - `bindplane-02-config-builder.png` — the Dynatrace + Phoenix destinations.
   - `bindplane-03-rollout.png` — rolling a config change to collectors.

## Talking points

- BindPlane does not replace the OTel Operator — it manages collector *config*;
  the Operator still runs the collectors. In a real fleet you would point
  BindPlane at the gateway instead of editing the CR by hand.
- The same Dynatrace OTLP destination + Phoenix destination we wired manually are
  one-click destinations in BindPlane.

## If we go live later

BindPlane (OSS/observIQ) ships a server Helm chart + per-node agent. It would run
in its own namespace and adopt the existing gateway collector — an optional
add-on if you want a live instance.
