# 04 — Observe with Dynatrace AI Observability

You now have agents running (module 02) inside a secured sandbox (module 03).
But are they fast? Reliable? **How much are they costing you per run?** This
module uses **Dynatrace AI Observability** to answer that — turning the spans
your agents already emit into cost, token, latency, and quality signals.

!!! info "Nothing to install here"
    The pipeline was wired in module 01: kagent's `otel.tracing` sends every LLM
    call, tool call, and agent hop as an OTLP span to the gateway collector,
    which forwards to **both** Dynatrace and Phoenix. This module is about
    *reading* that data in Dynatrace.

## How agent telemetry reaches Dynatrace

```
 kagent Agent (LLM + tool spans, gen_ai.* semconv)
        │ OTLP 4317
        ▼
 otel-gateway-collector ──▶ Dynatrace tenant (OTLP ingest)   ← you are here
   (normalises OpenInference/Traceloop → gen_ai.*)  └▶ Phoenix (module 06)
```

The gateway normalises OpenInference/Traceloop LLM attributes onto the
OpenTelemetry `gen_ai.*` semantic conventions, so Dynatrace sees consistent
`gen_ai.request.model`, `gen_ai.usage.input_tokens`,
`gen_ai.usage.output_tokens`, and token/latency fields regardless of which
instrumentation a tool used.

## 1. Generate some traffic

Observability needs something to observe. Send a few prompts so there are runs to
inspect (from module 02):

```bash
# SRE agent — a couple of diagnostic prompts
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List pods in all namespaces and summarise anything not Running."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

Run a BMAD workflow too if you want a longer, multi-hop trace to look at.

## 2. Open AI Observability in Dynatrace

In your Dynatrace tenant (the `.apps.dynatrace.com` URL from module 02), open
**AI Observability** (apps menu → *Observe & Explore* → **AI & LLM
Observability**, or search the app launcher for "AI Observability").

!!! note "What you should see"
    A list of AI/LLM **services** and **model endpoints**. Because every agent
    shares the `workshop-llm` ModelConfig (DeepSeek), you'll see the DeepSeek
    endpoint with call volume, token usage, latency distribution, error rate, and
    an **estimated cost** per call and in aggregate.

## 3. The four questions to ask every agent run

Dynatrace AI Observability is organised around the metrics that drive the
workshop's cost-efficiency theme. For each agent, look at:

| Question | Where to look | What "good" looks like |
|----------|---------------|------------------------|
| **How much does a run cost?** | Token usage × model price → estimated cost per request / per service. | Stable, proportional to task size — no silent blow-ups. |
| **Where does the latency go?** | Span waterfall: model time vs tool time vs agent-to-agent hops. | Model/tool time dominates; little idle gap. |
| **Is it reliable?** | Error rate + failure spans (tool errors, model timeouts, A2A failures). | Low, with clear error messages when it does fail. |
| **Is it efficient?** | Tokens per task, number of tool calls per task, retries. | No redundant tool calls, no runaway token growth. |

## 4. Follow a single trace end to end

Click into one agent request. The distributed trace shows the full loop:

```
 message/send (A2A)
 └─ agent.run                         (the whole loop)
    ├─ gen_ai LLM call  model=deepseek-chat  in=1.2k out=340 tokens  420ms
    ├─ tool: k8s.list_pods            180ms
    ├─ gen_ai LLM call  in=1.9k out=120 tokens  380ms
    └─ final answer
```

Each `gen_ai` span carries the model, the input/output token counts, and the
latency — so you can see **exactly which step** spent the tokens. For a BMAD run,
you additionally see the orchestrator's A2A hops to the analyst → PM → architect
→ developer → QA agents as nested spans.

!!! tip "Build a cost view with DQL"
    The Dynatrace MCP server (module 02) lets the SRE agent query this itself,
    but you can also open **Notebooks** and run DQL against the spans, e.g. sum
    `gen_ai.usage.output_tokens` grouped by agent to rank your most expensive
    agents. That ranking is the raw material for module 07 (Optimize).

## 5. Correlate with the rest of the cluster

Because module 01 also installed the Dynatrace Operator in Kubernetes-monitoring
mode, the agent traces sit **next to** your cluster topology. Under **Kubernetes**
you can line up an expensive agent run against pod CPU/memory, restarts, and
node pressure — so "slow agent" vs "starved pod" is one click apart.

## What you achieved (acceptance)

- Every agent run appears in Dynatrace AI Observability with **cost, tokens,
  latency, and error** signals.
- You can open a single trace and attribute spend to a specific model or tool
  call, and correlate it with Kubernetes health.

Next: **[05 — Diagnose a broken cluster](05-diagnose.md)** — stop sending toy
prompts: inject a real failure and watch the SRE agent find the root cause.
