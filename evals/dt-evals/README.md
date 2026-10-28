# evals/dt-evals — the primary eval path

[dt-evals](https://github.com/dynatrace-oss/dt-evals) runs **continuous
LLM-as-judge evals on real production traces**: it pulls `gen_ai.*` spans from
Dynatrace, scores them with a judge model, and writes the scores back as
`gen_ai.evaluation.result` **bizevents** — so eval results live right next to
the traces, logs, and metrics you already have.

```
Dynatrace gen_ai.* spans ─► dt-evals (sample → mask PII → LLM judge) ─► bizevents ─► DQL / dashboard / alert
```

## Files

| File | What |
|------|------|
| `workshop-agents.dt-eval.yaml` | The eval config (template with `${…}` placeholders). schemaVersion 3. |
| `run-dt-eval.sh` | Renders the template with your env values (envsubst), then `validate` + `run`. |

## Prerequisites

- **Node ≥ 22** (the CLI runs via `npx`; pinned to `DT_EVALS_PKG` in `cluster/versions.env`).
- A Dynatrace environment **already receiving the agents' `gen_ai.*` spans** (the
  Phase-2 OTel gateway does this). **Generate some agent traffic first.**
- A **dedicated** Dynatrace token (`dt0c01`) with scopes **`storage:spans:read`** +
  **`storage:events:write`**. This is *not* the Phase-2 OTLP ingest token.
- A judge key (`OPENAI_API_KEY`) — a DeepSeek key works (OpenAI-compatible).

Put all of these in `evals/.env` (see `evals/.env.example`).

## Discover your `service.name`

`scope.service` must be the agent's real `service.name` — set by kagent, not
guessed. List candidates with DQL (Dynatrace Notebook, or the `run-dt-query`
capability):

```dql
fetch spans, from: now() - 2h
| filter isNotNull(gen_ai.operation.name) or isNotNull(gen_ai.request.model)
| summarize span_count = count(), by: { service.name }
| sort span_count desc
```

Then set `DT_EVAL_SERVICE` (in `evals/.env` or the shell).

## Run

```bash
cd evals/dt-evals
./run-dt-eval.sh                 # validate + run with the config's scope
./run-dt-eval.sh --since 1h      # extra flags pass straight through to `dt-evals run`
```

The judge is **DeepSeek** by default (cost-efficiency theme). Switch to OpenAI by
dropping `baseUrl` in the YAML and setting `model: gpt-4o` + an OpenAI key.

## Inspect the scores

```dql
fetch bizevents
| filter event.type == "gen_ai.evaluation.result"
| summarize avg(toDouble(gen_ai.evaluation.score.value)), by: { gen_ai.evaluation.name }
```

A threshold breach makes the run exit non-zero (CI-friendly) — see `alerts:` in
the config.

## Tenant model (§7.4)

**Open question from the ISI-6696 plan:** shared workshop tenant vs. per-attendee?

**Recommendation — per-attendee tenant.** Each attendee uses their own Dynatrace
environment (a free 15-day trial is enough for the lab). Why:

- **Isolation.** dt-evals both *reads* spans and *writes* bizevents scoped by
  `service.name`. On a shared tenant every attendee's spans and eval results pile
  into the same streams — noisy, hard to tell apart, and easy to evaluate someone
  else's traffic by accident.
- **Token blast radius.** dt-evals needs `storage:spans:read` + `storage:events:write`.
  Handing every attendee a token on one shared tenant is broad write access to a
  common environment; per-attendee tokens are naturally scoped to their own data.
- **It matches the existing contract.** The Codespace secrets are already
  per-attendee (`DT_TENANT_URL` / `DT_API_TOKEN`), so per-attendee is the
  low-friction default — no new namespacing to invent.

**Shared-tenant fallback** (if Henrik prefers one tenant for cost/logistics):
namespace each attendee's agents with a unique `service.name` suffix
(e.g. `sre-agent-<attendee-id>`), set `scope.service` to match, and issue
per-attendee scoped API tokens. Expect higher cardinality and cross-talk in
shared dashboards; document the naming scheme up front.

> **Confirmed by the board (2026-10-27): per-attendee tenant** (ISI-6719). The configs
> here work unchanged either way — only `DT_ENVIRONMENT_URL` / `DT_EVAL_SERVICE`
> differ per model.
