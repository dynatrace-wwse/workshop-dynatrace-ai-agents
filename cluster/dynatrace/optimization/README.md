# Phase 5 · AI Agent Optimization artifacts (ISI-6720)

Dynatrace artifacts that turn the kagent crew's `gen_ai.*` spans into the three
optimization signals from **[`docs/06-optimize.md`](../../../docs/06-optimize.md)**
(token spend, unused tools, inefficient loops), a reproducible **before/after**
story, and a **continuous guardian** that gates cost + quality regressions.

All four are **dtctl-ready YAML** — `dtctl apply`/`dtctl create` straight from
this directory. Every DQL/SLI was validated against live crew telemetry before
commit.

| File | Kind | Deploy |
|------|------|--------|
| `ai-agent-optimization.dashboard.yaml` | Dashboard | `dtctl apply -f ai-agent-optimization.dashboard.yaml` |
| `ai-agent-optimization-before-after.notebook.yaml` | Notebook | `dtctl create notebook -f ai-agent-optimization-before-after.notebook.yaml` |
| `ai-agent-quality-cost.guardian.yaml` | Site Reliability Guardian (settings) | `dtctl create settings -f ai-agent-quality-cost.guardian.yaml --schema app:dynatrace.site.reliability.guardian:guardians --scope environment` |
| `ai-agent-optimization.workflow.yaml` | Workflow (scheduled guardian run) | `dtctl create workflow -f ai-agent-optimization.workflow.yaml` |

## Prerequisites

- A Dynatrace tenant receiving OTLP from the Phase 2/3 cluster (the kagent crew
  emits `gen_ai.*` spans under `service.namespace == "kagent"`).
- `dtctl` authenticated against that tenant
  (`dtctl config use-context <your-context>`; verify with `dtctl auth whoami`).

## Deploy (in order)

```bash
dtctl config use-context <your-tenant>

# 1 · Dashboard + notebook (find the waste, tell the before/after story)
dtctl apply -f ai-agent-optimization.dashboard.yaml
dtctl create notebook -f ai-agent-optimization-before-after.notebook.yaml

# 2 · Guardian (the continuous cost + quality gate)
dtctl create settings -f ai-agent-quality-cost.guardian.yaml \
  --schema app:dynatrace.site.reliability.guardian:guardians --scope environment

# 3 · Workflow that runs the guardian daily. It references the guardian by
#     objectId — after step 2, grab the new objectId and set it in the workflow:
dtctl get settings --schema app:dynatrace.site.reliability.guardian:guardians \
  -o json --plain | grep -B2 "AI Agent Quality"      # -> objectId
#     edit ai-agent-optimization.workflow.yaml -> tasks.run_validation.input.objectId
dtctl create workflow -f ai-agent-optimization.workflow.yaml
```

> The workflow ships with its schedule **disabled**
> (`trigger.schedule.isActive: false`). Flip it to `true` to go continuous.

The dashboard/notebook YAML carry **no `id`** — the server assigns one on first
deploy. To *update* a dashboard later, download it first
(`dtctl get dashboard <id> -o yaml --plain > file.yaml`), edit, and re-`apply` —
this preserves UI edits.

## The guardian

A Site Reliability Guardian is the regression gate behind the optimization loop.
Three DQL objectives, all validated against live telemetry:

| Objective | SLI (crew, `call_llm` spans) | Rule | target / warning |
|-----------|------------------------------|------|------------------|
| Cost per LLM call | avg input tokens / call | `<=` | 20000 / 18000 |
| Loop efficiency | avg `call_llm` hops / task | `<=` | 5 / 4 |
| Answer substance (quality proxy) | avg output tokens / call | `>=` | 200 / 300 |

The quality proxy backstops the cost cuts: an agent that got "cheaper" by
emitting empty/truncated answers trips it. For the **LLM-judge** quality gate
(relevance, faithfulness, hallucination), pair this with the Phase-4 dt-evals
suite ([`evals/dt-evals`](../../../evals/dt-evals)) — that is the complementary
gate the workflow narrative references.

## Reference deployment (ISI-6720)

First deployed to `oat05854.dev.apps.dynatracelabs.com`:

- Dashboard `70385f20-36c4-4a82-bf33-eef1a2d03855`
- Notebook `600cc6ab-8874-40ad-8e80-8a9c24806084`
- Guardian `de5dde8f-c585-3e6a-a115-daa7f4d263ca`
- Workflow `70bebb93-12ab-45bd-abff-3d2997dced2b`

Queries carry no hard-coded dashboard time filter — the dashboard time-picker
and notebook section timeframes drive the window (that is how you switch between
the *before* and *after* windows). The guardian/workflow use an explicit 24h
validation window.
