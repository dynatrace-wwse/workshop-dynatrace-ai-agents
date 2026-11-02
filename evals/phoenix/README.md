# evals/phoenix — Phoenix (Arize) eval walkthrough

Phoenix is the Phase-2 LLM trace/eval UI (port **6006**). The OTel gateway fans
the agents' `gen_ai.*` spans into it. This folder adds a small, pinned eval
script so you can **run LLM-as-judge evals and see labelled scores on the traces**.

## 1. Inspect traces (UI, no code)

```bash
kubectl -n phoenix port-forward svc/phoenix 6006:6006
```

Open <http://localhost:6006>. After you've driven the agents a bit, each
agent/LLM call shows up as a trace: prompt, response, tool calls, token counts,
latency. Click a span to see the `gen_ai.*` attributes.

## 2. Run evals

```bash
cd evals && uv sync                 # installs the pinned eval tooling
# Bundled sample dataset — no cluster or agent traffic needed (just a judge key):
uv run python phoenix/run_phoenix_eval.py
# Live spans pulled from Phoenix, with scores logged back onto the traces:
uv run python phoenix/run_phoenix_eval.py --from-phoenix
```

What it does:

- Builds two LLM-judge classifiers — **hallucination** (is the answer grounded in
  its context?) and **relevance** (does it answer the question?) — with
  `phoenix.evals.create_classifier`.
- Scores each interaction with `evaluate_dataframe`.
- Prints a per-metric summary and writes `phoenix/out/phoenix_eval_results.csv`.
- With `--from-phoenix`, logs the labels/scores back as span annotations so they
  appear on the traces in the Phoenix UI.

The judge is **DeepSeek** by default (same model as the agents). It's driven
purely by env vars — see `evals/.env.example`:

| Var | Purpose |
|-----|---------|
| `OPENAI_API_KEY` | judge key (a DeepSeek key works) |
| `OPENAI_BASE_URL` | `https://api.deepseek.com/v1` — drop it to use real OpenAI |
| `JUDGE_MODEL` | `deepseek-chat` |
| `PHOENIX_ENDPOINT` / `PHOENIX_PROJECT` | only for `--from-phoenix` |

## Grade diagnoses against the scenario answer keys (module 05)

`run_diagnosis_eval.py` is the diagnostic-module companion: it grades an SRE
diagnosis against its scenario's **ground truth**
([`evals/ground-truth/`](../ground-truth/), ISI-6850) — did it cite the required
signals and reach the right root cause?

```bash
cd evals
uv run python phoenix/run_diagnosis_eval.py        # bundled golden+confab diagnoses (offline, no key)
uv run python phoenix/run_diagnosis_eval.py --llm-judge      # + LLM root-cause grader (needs a judge key)
uv run python phoenix/run_diagnosis_eval.py --from-phoenix   # grade live diagnosis spans + annotate
```

The core grader is deterministic (pure stdlib) so it runs with no judge key; the
LLM root-cause grader is optional. Results go to `phoenix/out/diagnosis_eval_results.csv`.

## The bundled dataset

`data/sample_llm_interactions.jsonl` holds a mix of good and deliberately
bad (ungrounded / off-topic) agent answers, so the eval produces a **spread** of
labels — you can see the judge catch the hallucinated and irrelevant ones. This
gives an inspectable result even before you've generated live traffic (you still
need a judge key), which satisfies the Phase-4 acceptance on its own.

## `--from-phoenix` span mapping

Our agents export **OTel GenAI semconv** spans through the collector-gateway, so
the prompt/response content lands under `gen_ai.*` keys — not the OpenInference
`input.value` / `output.value` keys. `span_mapping.py` maps both conventions to
the judge's `input` / `output` / `context` columns:

- OTel GenAI indexed — `gen_ai.prompt.N.content` / `gen_ai.completion.N.content`
- OTel GenAI structured — `gen_ai.input.messages` / `gen_ai.output.messages`
- OpenInference — `input.value` / `output.value`
- GenAI log-events on the span

If a run reports *"Found spans but none carried recognisable LLM input/output
attributes"*, it now prints the `attributes.*` columns your spans actually have —
add any missing key to `INPUT_KEYS` / `OUTPUT_KEYS` in `span_mapping.py`. The
offline test `tests/test_span_mapping.py` covers every supported form.

### Which spans get pulled — `span_kind == 'LLM'`

Project `PHOENIX_PROJECT` (default: `default`) holds **all** workshop traffic —
the otel-demo app alone floods it with microservice spans (`http`/`db`/`rpc`/…).
So `--from-phoenix` does **not** grab the newest-N of everything (which buried the
sparse agent `call_llm` spans — ISI-6962). `span_mapping.fetch_llm_spans()` filters
**server-side** to `span_kind == 'LLM'` *before* the limit: the collector-gateway
OTTL (ISI-6960) stamps `openinference.span.kind=LLM` on the `call_llm` span, which
Phoenix exposes as the queryable `span_kind` field. If that filter matches nothing
(an older capture, or the gateway isn't stamping it yet) the call falls back to the
unfiltered pull and the run prints which path it took, so a crowded result is never
mistaken for a clean one.

This is proven end-to-end on a real Phoenix server (no cluster/judge key needed)
by `verify_from_phoenix.py`, run in CI by
[`.github/workflows/phoenix-from-phoenix.yaml`](../../.github/workflows/phoenix-from-phoenix.yaml)
(ISI-6966) — it floods a live Phoenix with infra spans + sparse LLM spans and
asserts the old newest-N pull maps **zero** while the filter returns the LLM spans.

## Versions

Pinned in `evals/pyproject.toml` (`arize-phoenix-evals`, `arize-phoenix-client`).
The evals API moved from 1.x → 3.x; pinning keeps this script working. Bump
deliberately.
