# evals/ — Evaluating the workshop agents

Phase 4 stands up the **evaluation path** for the agents deployed in Phase 3
(the SRE agent and the BMAD crew). You evaluate them two complementary ways,
both fed by the **same `gen_ai.*` spans** the OTel gateway already produces:

```
                         ┌───────────────────────────► Phoenix (OTLP 4317)  ── path A
agents (kagent) ─► OTel gateway ─ gen_ai.* ─┤
   SRE + BMAD                     normalize  └─────────► Dynatrace (OTLP)    ── path B
                                                              │
                                                 dt-evals pulls gen_ai.* spans,
                                                 scores with an LLM judge, writes
                                                 gen_ai.evaluation.result bizevents
```

| Path | Tool | Where results live | Role in the workshop |
|------|------|--------------------|----------------------|
| **A** | **Phoenix (Arize)** | Phoenix UI (port **6006**) | Walkthrough: inspect LLM traces, run a few evals locally, see labels/scores annotated onto the traces. |
| **B** | **dt-evals** | Dynatrace (bizevents + dashboards) | **Primary eval path.** Continuous, trace-sourced LLM-as-judge evals that land next to the rest of your observability data. |

Both reuse the cost-efficient workshop judge: **DeepSeek** (`deepseek-chat`,
OpenAI-API compatible) — the same model that powers the agents. Swap it for
OpenAI/Anthropic with one env change (documented in each subfolder).

## Layout

| Path | What |
|------|------|
| [`phoenix/`](phoenix/) | Phoenix eval walkthrough — `run_phoenix_eval.py` + a bundled sample dataset so you get scores even before generating live traffic. |
| [`dt-evals/`](dt-evals/) | dt-evals config (`workshop-agents.dt-eval.yaml`) + a `run-dt-eval.sh` wrapper. |
| [`pyproject.toml`](pyproject.toml) | `uv` project pinning the Python eval tooling (Phoenix path). |

## Prerequisites

- Phase 3 complete: agents deployed and reachable (`kubectl -n kagent get agents`).
- **Generate some agent traffic first** so there are spans to evaluate — ask the
  SRE agent a question or run a BMAD task. Then:
  - **Phoenix:** `kubectl -n phoenix port-forward svc/phoenix 6006:6006` → open
    <http://localhost:6006>, confirm traces appear.
  - **Dynatrace:** confirm `gen_ai.*` spans arrive (see `dt-evals/README.md` →
    *Discover your service.name*).
- `uv` is pre-installed in the devcontainer (Phoenix path); `npx` ships with Node
  (dt-evals path).

## Quick start

```bash
# Path A — Phoenix (no cluster/traffic needed — bundled dataset + a judge key):
cd evals && uv sync
uv run python phoenix/run_phoenix_eval.py            # bundled dataset
uv run python phoenix/run_phoenix_eval.py --from-phoenix   # live Phoenix spans

# Path B — dt-evals (primary; needs a Dynatrace tenant with gen_ai.* spans):
cd evals/dt-evals && ./run-dt-eval.sh
```

## Open question §7.4 — shared vs per-attendee Dynatrace tenant

**Recommendation: per-attendee tenant** (each attendee uses their own Dynatrace
free trial / sandbox). Rationale and the shared-tenant fallback are documented in
[`dt-evals/README.md`](dt-evals/README.md#tenant-model-74). This is pending
Henrik's confirmation on the issue thread (ISI-6719).
