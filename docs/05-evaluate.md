# 05 — Evaluate (Phoenix + dt-evals)

Observability (module 04) tells you *what the agent did* and *what it cost*. It
does **not** tell you whether the answer was correct, grounded, or useful. That's
**evaluation** — scoring agent outputs against expectations — and it's the step
most teams skip, which is why their agents quietly regress. This module uses two
complementary tools:

- **Phoenix (Arize)** — interactive trace + evaluation UI, already running from
  module 01. Great for *exploratory* eval and LLM-as-a-judge over live traces.
- **dt-evals** — [`dynatrace-oss/dt-evals`](https://github.com/dynatrace-oss/dt-evals),
  a repeatable, config-driven eval harness. Great for *regression* suites you run
  before shipping an agent change.

!!! info "Phase status"
    Phoenix is stood up and receiving traces today. The concrete dt-evals suite
    (datasets + eval configs under [`evals/`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/tree/main/evals))
    is delivered by **Phase 4**; this module explains how to drive it and will
    link the exact config files as they land.

---

## Part A — Phoenix: explore and judge live traces

Open Phoenix on the forwarded Codespace port **6006**:

```bash
kubectl -n phoenix port-forward svc/phoenix 6006:6006
# then open http://localhost:6006
```

The same OTel gateway that feeds Dynatrace (module 04) also fans traces out to
Phoenix, so every agent run you triggered shows up here as an LLM trace.

!!! note "What you should see"
    A **Traces** view listing agent runs, each expandable into its LLM and tool
    spans with the full prompt, the model response, and token counts. This is the
    LLM-native view of the same spans Dynatrace received.

### Run an evaluation (LLM-as-a-judge)

Phoenix can score spans against an eval template — for example **hallucination**,
**Q&A correctness**, or **toxicity** — using a model as the judge. The typical
loop:

1. Select a set of spans (e.g. all `sre-agent` runs from today).
2. Run an eval template; Phoenix sends each (input, output) pair to a judge model
   and attaches a **label + explanation** back onto the span.
3. Sort/filter by the eval result to find the bad answers, then click through to
   the exact prompt that produced them.

This is *exploratory*: fast, visual, good for discovering failure modes. For a
gate you can run in CI, you want dt-evals.

---

## Part B — dt-evals: repeatable regression suites

[`dt-evals`](https://github.com/dynatrace-oss/dt-evals) runs a **declared** set of
test cases against an agent and produces pass/fail scores you can diff across
runs. Python tooling is managed with **`uv`** (installed in the devcontainer).

### 1. Get the harness

```bash
cd evals
uv sync          # resolves the dt-evals + dependencies declared for this folder
```

### 2. The shape of an eval suite

A dt-evals run binds three things:

| Piece | What it is |
|-------|------------|
| **Dataset** | Input prompts + expected properties of a good answer (reference, must-contain, must-not-contain, etc.). |
| **Target** | The agent under test — here, a kagent agent reached over its A2A endpoint (`kagent-controller.kagent:8083/api/a2a/kagent/<agent>`). |
| **Evaluators** | How each output is scored — exact/semantic match, LLM-as-a-judge rubric, tool-call assertions, latency/cost budgets. |

### 3. Run the suite

```bash
# illustrative — Phase 4 ships the concrete config under evals/
uv run dt-evals run --config evals/<suite>.yaml
```

Point the suite's judge/reporting at the same backends you already run: scores
can be pushed to **Phoenix** for inspection and the run's traces land in
**Dynatrace** via the gateway — so an eval failure is one click from the trace
that caused it.

!!! tip "Cost + quality in one gate"
    Because dt-evals can assert on **token/cost budgets** alongside correctness,
    a single suite answers both "is it right?" and "is it cheap?" — exactly the
    two axes this workshop cares about. An agent that gets the right answer by
    burning 20k tokens fails the budget check.

---

## What to measure for *these* agents

| Agent | Good eval questions |
|-------|---------------------|
| **SRE agent** | Did it correctly identify the unhealthy pod? Did it call the right k8s/Dynatrace tool (not guess)? Was the diagnosis grounded in real tool output (no hallucinated pod names)? |
| **BMAD crew** | Did the workflow produce the expected artifacts (issues → milestone → branch → PR)? Did the developer agent stay within its repo scope? Did QA actually review the PR? Did it finish within a token budget? |

## What you achieved (acceptance)

- You can inspect any agent run in Phoenix and attach LLM-as-a-judge evals to it.
- You understand how a dt-evals suite turns "did the agent do the right thing,
  cheaply?" into a repeatable pass/fail score wired to Phoenix + Dynatrace.

Next: **[06 — Optimize](06-optimize.md)** — now that you can *measure* cost and
quality, go cut the waste.
