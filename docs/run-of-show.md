# Run of show — the guided 13-step demo

This page is the **single, top-to-bottom script** for the live demo. It stitches
the workshop's modules into one continuous run: configure an agent, investigate a
cluster, turn on observability, evaluate the results, and close the
observe → evaluate → optimize loop. Each step is deliberately short — just enough
to *do* it — and links to the full module when you want the depth behind it.

!!! info "How to read this page"
    Every step has the same shape: **What & why** (one line), **Do it** (the exact
    commands), **Apply this** (the config or prompt to paste), and **Go deeper** (the
    module link). Run the steps in order — later steps depend on the traffic and
    traces the earlier ones produce.

!!! note "Prerequisites"
    The cluster is up and the platform is installed — that's
    **[2 — Setup](2-setup.md)** and **[3 — Platform install](3-platform-install.md)**.
    After those, the OpenTelemetry Operator, a gateway collector, kagent (clean
    base, no agents yet), Tetragon, and Phoenix are all running. This walkthrough
    starts from there.

!!! tip "Two surfaces to keep open"
    `listApps` prints the URLs of the **kagent** UI and **Phoenix** — both are
    published through the framework ingress, no port-forward needed. Dynatrace
    is your tenant.

---

## Step 1 — Configure kagent to create an agent

**What & why.** kagent shipped as a clean runtime in module 3. Here you turn on
its built-in Kubernetes tooling, point it at a model, wire the **pre-deployed MCP
servers**, and deploy the **SRE agent** — one idempotent script does all of it.

**Do it.** Supply the MCP credentials, then install:

```bash
export GH_PAT='github_pat_...'                              # fine-grained, one demo repo
export DT_PLATFORM_TOKEN='dt0s16....'                       # Dynatrace platform token
export DT_ENVIRONMENT='https://<env>.apps.dynatrace.com'    # platform apps URL

installAgents
```

The script applies, in order: the MCP layer (the shared **`workshop-llm`**
ModelConfig — DeepSeek — plus the **GitHub** and **Dynatrace** MCP tool servers),
then the **SRE agent**, then the BMAD crew. kagent's built-in
**`kagent-tool-server`** (Kubernetes + networking tools) is already enabled in
`cluster/kagent/values.yaml`.

**Apply this.** Confirm the tools registered and the agent is Accepted:

```bash
kubectl -n kagent get mcpserver,remotemcpserver
kubectl -n kagent get remotemcpserver kagent-tool-server -o jsonpath='{.status.discoveredTools[*].name}'; echo
kubectl -n kagent get agents          # sre-agent + six bmad-* should be Accepted
```

**Go deeper.** [4 — Agents & MCP wiring](4-agents-mcp.md).

---

## Step 2 — Run a simple cluster investigation (SRE agent)

**What & why.** Prove the agent is alive and can reach its Kubernetes tools with a
harmless read-only prompt. This is the "list the pods" baseline — no fault yet.

**Do it.** Paste the prompt into the **sre-agent** in the kagent UI
(the **kagent** app — `listApps`), or send it over A2A:

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List the pods in the kagent namespace and tell me if any are unhealthy."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

**Apply this.** You should get a grounded answer naming real pods — the agent
called `k8s_get_resources`, it did not guess. Keep this first run; you'll compare
its trace against the re-run in Step 4.

**Go deeper.** [4 — Agents & MCP wiring](4-agents-mcp.md#5-send-a-sample-prompt).

---

## Step 3 — Show the observability configuration in the collector

**What & why.** Every answer the agent just gave already emitted spans. The
**gateway collector** is what turns those raw LLM/tool spans into clean,
Dynatrace- and Phoenix-ready telemetry — and fans them out to **both** backends.
Open its config so the audience sees there is no magic: it's a normalise + fan-out
pipeline.

**Do it.** Show the live collector and its config:

```bash
kubectl get otelcol -n opentelemetry-operator-system          # the gateway collector
```

Open [`cluster/otel/collector-gateway.yaml`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/otel/collector-gateway.yaml)
and point at the two things that matter:

```yaml
processors:
  # Normalise OpenInference / Traceloop LLM attributes onto gen_ai.* semconv
  transform/genai-normalize:
    trace_statements:
      - context: span
        statements:
          - set(attributes["gen_ai.usage.input_tokens"],  attributes["llm.token_count.prompt"])     where ...
          - set(attributes["gen_ai.usage.output_tokens"], attributes["llm.token_count.completion"])  where ...
          - set(attributes["gen_ai.request.model"],       attributes["llm.model_name"])              where ...
service:
  pipelines:
    traces:
      processors: [memory_limiter, k8sattributes, resourcedetection, resource, transform/genai-normalize, batch]
      exporters:  [otlphttp/dynatrace, otlp/phoenix, debug]   # ← fan-out to BOTH backends
```

**Apply this.** The takeaway for the room: whatever instrumentation a tool used
(OpenInference, Traceloop, native OTel), the collector rewrites it onto the
OpenTelemetry **`gen_ai.*`** convention — so Dynatrace and Phoenix see the same
model, token, and latency fields. The `traces` pipeline exports to Dynatrace
**and** Phoenix from one place.

**Go deeper.** [6 — Observe with Dynatrace](6-observe.md#how-agent-telemetry-reaches-dynatrace).

---

## Step 4 — Re-run the SRE investigation

**What & why.** Now that everyone has seen the pipeline, run the agent again — this
time to *generate traces on purpose*. Same agent, slightly broader prompt, so there
are fresh runs to open in Phoenix and Dynatrace in the next steps.

**Do it.**

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List pods in all namespaces and summarise anything not Running."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

**Apply this.** Within a few seconds this run is a trace in both backends: an
`agent.run` span wrapping `gen_ai` LLM calls and `k8s` tool calls, each carrying
input/output token counts and latency. That trace is what Steps 5 and 6 inspect.

**Go deeper.** [6 — Observe with Dynatrace](6-observe.md#1-generate-some-traffic).

---

## Step 5 — Open Phoenix and create one evaluation

**What & why.** Observability shows *what* the agent did; evaluation scores
*whether it was any good*. Phoenix is the fast, visual, exploratory judge — open it
and run one LLM-as-a-judge evaluation over the traces you just made.

**Do it.** Phoenix is already forwarded on port **6006**. Run the bundled eval:

```bash
cd evals && uv sync
uv run python phoenix/run_phoenix_eval.py                # bundled sample dataset — just needs a judge key
uv run python phoenix/run_phoenix_eval.py --from-phoenix # grade the LIVE spans and annotate them in the UI
```

**Apply this.** The script builds two judge classifiers — **hallucination** (is
the answer grounded in its context?) and **relevance** (does it answer the
question?). With `--from-phoenix` it writes the scores back onto the originating
spans, so the labels appear on the traces in the Phoenix UI. It also drops a CSV at
`evals/phoenix/out/phoenix_eval_results.csv`.

**Go deeper.** [8 — Evaluate · Part A (Phoenix)](8-evaluate.md#part-a-phoenix-explore-and-judge-live-traces).

---

## Step 6 — Open Dynatrace: traces + AI Observability

**What & why.** Same spans, production-grade backend. Dynatrace adds **estimated
cost**, a full distributed-trace waterfall, and correlation with cluster health —
the signals that drive the workshop's cost-efficiency theme.

**Do it.** In your tenant (`…apps.dynatrace.com`), open the app launcher and go to
**AI & LLM Observability**.

**Apply this.** Walk the four questions on one agent, then open a single trace:

| Question | Where to look |
|----------|---------------|
| How much does a run cost? | token usage × model price → estimated cost per request |
| Where does the latency go? | span waterfall: model time vs tool time vs A2A hops |
| Is it reliable? | error rate + failure spans |
| Is it efficient? | tokens per task, tool calls per task, retries |

Because every agent shares the `workshop-llm` (DeepSeek) ModelConfig, you'll see
one DeepSeek endpoint with call volume, tokens, latency, error rate, and cost.
Click into a request to see `gen_ai` LLM spans and `k8s` tool spans nested under
`agent.run`.

**Go deeper.** [6 — Observe with Dynatrace](6-observe.md#2-open-ai-observability-in-dynatrace).

---

## Step 7 — Create an evaluation using dt-evals

**What & why.** Phoenix was exploratory; **dt-evals** is the CI-friendly path. It
samples `gen_ai.*` spans straight from Dynatrace, masks PII, scores each with a
judge, and writes the results back as **bizevents** next to the rest of your
telemetry — so a low score is one click from the trace that caused it.

**Do it.** Put the credentials in `evals/.env`, then run the wrapper:

```bash
cd evals/dt-evals
./run-dt-eval.sh          # renders the config with your env, then runs validate + run
```

The `.env` needs a dedicated `DYNATRACE_API_TOKEN` (`dt0c01` with
`storage:spans:read` + `storage:events:write`), `DT_ENVIRONMENT_URL`, a judge
`OPENAI_API_KEY` (a DeepSeek key works), and `DT_EVAL_SERVICE` — **discover** that
service name with DQL, don't guess it:

```dql
fetch spans, from: now() - 2h
| filter isNotNull(gen_ai.operation.name) or isNotNull(gen_ai.request.model)
| summarize span_count = count(), by: { service.name }
| sort span_count desc
```

**Apply this.** The shipped config enables relevance, faithfulness, hallucination,
coherence, toxicity, and prompt-injection metrics, and sets thresholds that make
the run **exit non-zero on a breach** — a ready-made CI gate.

**Go deeper.** [8 — Evaluate · Part B (dt-evals)](8-evaluate.md#part-b-dt-evals-trace-sourced-evals-in-dynatrace).

---

## Step 8 — Run the BMAD investigation

**What & why.** So far it's been the single SRE agent. Now show the other side of
the platform: the **BMAD crew** — a six-member orchestrated workflow (analyst → PM
→ architect → developer → QA, driven by the orchestrator). A BMAD run is a long,
multi-hop trace — exactly the kind of workload the optimize steps later target.

**Do it.** Send the orchestrator a task (kagent UI → **bmad-orchestrator**, or A2A):

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"Build a simple Todo app in <owner>/<repo>. Run the full BMAD workflow and open a PR."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/bmad-orchestrator
```

**Apply this.** In the trace you'll see the orchestrator's **A2A hops** to each
crew member as nested spans, and the developer agent using the **GitHub MCP** tools
to open issues, push a branch, and raise a PR. This is the multi-agent run whose
hop-count and token spend you'll scrutinise in Step 12.

**Go deeper.** [4 — Agents & MCP wiring](4-agents-mcp.md#5-send-a-sample-prompt).

---

## Step 9 — Review the Phoenix evaluation

**What & why.** Close the loop you opened in Step 5: read the scores. Phoenix is
where you *discover failure modes* interactively.

**Do it.** In the **phoenix** app (`listApps`), open the traces you graded.
Each now carries **hallucination** and **relevance** labels (from the
`--from-phoenix` run). Sort by score to surface the weakest answers, and open one to
read the prompt, response, tool spans, and token counts behind the label.

**Apply this.** For the SRE agent the questions that matter: did it identify the
right pod, call the right tool (not guess), and stay grounded in real tool output
(no hallucinated pod names)? The per-metric summary and
`evals/phoenix/out/phoenix_eval_results.csv` give you the same numbers outside the
UI.

**Go deeper.** [8 — Evaluate · Part A (Phoenix)](8-evaluate.md#run-an-evaluation-llm-as-a-judge).

---

## Step 10 — Review the dt-evals results

**What & why.** The dt-evals run from Step 7 wrote its scores into Dynatrace as
bizevents. Read them with DQL — this is the queryable, alertable, CI-gated view of
quality.

**Do it.** In a Dynatrace Notebook:

```dql
fetch bizevents
| filter event.type == "gen_ai.evaluation.result"
| summarize avg(toDouble(gen_ai.evaluation.score.value)), by: { gen_ai.evaluation.name }
```

**Apply this.** You get an average score per evaluator (relevance, faithfulness,
hallucination, …). Because the scores live next to the spans, any low score is one
click from the trace, prompt, and tool calls that produced it — and the run already
**exited non-zero** if a threshold was breached, which is your CI gate.

**Go deeper.** [8 — Evaluate · Part B · Read the scores](8-evaluate.md#3-read-the-scores).

---

## Step 11 — Deploy the notebook

**What & why.** You've measured cost (Step 6) and quality (Steps 9–10). The
optimize module ships a ready-made Dynatrace **notebook** that computes every
optimization signal from your crew's `gen_ai.*` spans — deploy it so the next DQL
steps run against a real surface, not a blank page.

**Do it.**

```bash
dtctl config use-context <your-tenant>
cd cluster/dynatrace/optimization
dtctl create notebook -f ai-agent-optimization-before-after.notebook.yaml
```

**Apply this.** The notebook — *AI Agent Optimization — before/after* — is the
observe → find → change → re-measure → keep/revert walkthrough, one runnable DQL
cell per step. Its §5 cell measures the single number optimization moves: average
input tokens per `call_llm`. (The companion **dashboard**,
`ai-agent-optimization.dashboard.yaml`, deploys the same way with `dtctl apply -f`.)

**Go deeper.** [9 — Optimize · deploy the surfaces](9-optimize.md#the-optimization-loop).

---

## Step 12 — Build DQL queries: tool usage + token utilization

**What & why.** This is the heart of optimization. Two questions answer "where is
the waste?": **which tools does an agent actually call** (anything granted but never
called is pure prompt overhead), and **how many tokens is each agent burning**
(especially the input:output ratio, your waste compass).

**Do it — token utilization (rank agents by spend):**

```dql
fetch spans
| filter service.namespace == "kagent" and isNotNull(gen_ai.usage.output_tokens)
| summarize llmCalls = count(),
    inputTokens  = sum(gen_ai.usage.input_tokens),
    outputTokens = sum(gen_ai.usage.output_tokens),
    by:{agent = service.name}
| fieldsAdd totalTokens = inputTokens + outputTokens,
    inOutRatio      = round(toDouble(inputTokens) / outputTokens, decimals: 1),
    avgInputPerCall = round(toDouble(inputTokens) / llmCalls)
| sort totalTokens desc
```

**Do it — tool usage (what an agent really calls):**

```dql
fetch spans
| filter service.namespace == "kagent" and service.name == "<agent-service-name>"
    and gen_ai.operation.name == "execute_tool" and gen_ai.tool.name != "(merged tools)"
| summarize calls = count(), by:{tool = gen_ai.tool.name}
| sort calls desc
```

**Apply this.** Diff the tools the traces prove an agent uses against the tool set
it was *granted* — every unused tool is a JSON schema injected into **every** prompt
(~165 input tokens per tool, on every call). A high **input:output ratio** (e.g.
38:1) means the model re-reads a large context each call — that, not the raw total,
is where to cut. This ranking is the raw material for the cuts in module 9.

**Go deeper.** [9 — Optimize · the four cuts](9-optimize.md#2-the-four-highest-leverage-cuts).

---

## Step 13 — Deploy the workflow

**What & why.** Optimization isn't a one-off. Because cost *and* quality are now
both telemetry, the last artifact makes the loop **continuous**: a scheduled
Dynatrace workflow runs a Site Reliability Guardian daily, so a cost or quality
regression fails loudly on its own.

**Do it.** Deploy the guardian, then the workflow that runs it:

```bash
cd cluster/dynatrace/optimization
dtctl create settings -f ai-agent-quality-cost.guardian.yaml \
  --schema app:dynatrace.site.reliability.guardian:guardians --scope environment
dtctl create workflow -f ai-agent-optimization.workflow.yaml
```

**Apply this.** The guardian holds three DQL objectives over the crew's `call_llm`
spans — **cost per call** (avg input tokens ≤ 20k), **loop efficiency** (avg hops ≤
5), and an **answer-substance** quality proxy (avg output tokens ≥ 200) so an agent
that got "cheaper" by truncating answers trips the gate. The workflow ships with its
schedule **disabled**; flip `trigger.schedule.isActive: true` to run it over the last
24h every day.

**Go deeper.** [9 — Optimize · make it continuous](9-optimize.md#4-make-it-continuous-the-guardian-workflow).

---

## You've run the whole show

In thirteen steps you configured an agent, investigated a cluster, exposed the
telemetry pipeline, evaluated the results two ways, and closed the
**observe → evaluate → optimize** loop with queries and automation that keep the
crew cost-efficient. For the depth behind any step, follow its **Go deeper** link —
and when something misbehaves, the [Troubleshooting](troubleshooting.md) page
collects the common fixes per module.

<!-- LAB_NO_SOLUTION: reference page — the module pages hold the checks and solutions -->
