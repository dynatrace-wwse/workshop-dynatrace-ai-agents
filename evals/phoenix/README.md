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

## The bundled dataset

`data/sample_llm_interactions.jsonl` holds a mix of good and deliberately
bad (ungrounded / off-topic) agent answers, so the eval produces a **spread** of
labels — you can see the judge catch the hallucinated and irrelevant ones. This
gives an inspectable result even before you've generated live traffic (you still
need a judge key), which satisfies the Phase-4 acceptance on its own.

## Versions

Pinned in `evals/pyproject.toml` (`arize-phoenix-evals`, `arize-phoenix-client`).
The evals API moved from 1.x → 3.x; pinning keeps this script working. Bump
deliberately.
