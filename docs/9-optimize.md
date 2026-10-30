# 9. Optimize

This is where the whole workshop pays off. You can now **run** agents (4),
**secure** them (5), **observe** their cost (6), and **evaluate** their quality
(8). Optimization is the loop that uses that evidence to make agents **cheaper
without making them worse**.

!!! quote "The core idea"
    The biggest driver of AI agent cost is **tokens** — and most token spend is
    waste: unused tools inflating every prompt, oversized system prompts, chatty
    multi-hop workflows, and retries. You can't cut what you can't see, which is
    why observation and evaluation came first.

## The optimization loop

```mermaid
flowchart TD
    observe["observe (6)"] --> waste["find the waste"]
    evaluate["evaluate (8)"] --> change["make one change"]
    waste --> change
    change --> remeasure["re-measure cost + quality"]
    remeasure -->|keep only if quality holds| waste
```

Change one thing, re-run the eval suite, and keep the change **only if quality
holds and cost dropped**. Never optimize on cost alone — that's how you ship a
cheap agent that gives wrong answers.

!!! tip "Two ready-made surfaces — deploy them first"
    This module ships a Dynatrace **dashboard** and **notebook** that compute every
    signal below from your crew's `gen_ai.*` spans. Deploy them, then read the rest
    of this page with your own data on screen:

    ```bash
    # dtctl is preinstalled and already pointed at your tenant (installDtctl)
    cd cluster/dynatrace/optimization
    dtctl apply -f ai-agent-optimization.dashboard.yaml
    dtctl create notebook -f ai-agent-optimization-before-after.notebook.yaml
    ```

    - **Dashboard** — *AI Agent Optimization*: spend ranking, input:output ratio,
      tools-actually-used, loop detection, token-trend.
    - **Notebook** — *AI Agent Optimization — before/after*: the observe → find →
      change → re-measure → keep/revert walkthrough, one runnable DQL cell per step.

    All four artifacts (dashboard, notebook, guardian, workflow — §4) are
    dtctl-ready YAML in [`cluster/dynatrace/optimization/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/cluster/dynatrace/optimization) with a README.

## 1. Rank your agents by spend

From Dynatrace AI Observability (module 6), find your most expensive agents —
total tokens and estimated cost per run. Start at the top of that list; a 20%
cut on your priciest agent beats a 50% cut on a rarely-used one.

```
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

!!! example "What this looked like on the reference tenant (7-day window)"
    | Agent | Total tokens | in:out ratio | Avg input / call |
    |-------|---:|:---:|---:|
    | `seta_sre_investigator` | 46.2 M | **38 : 1** | **33,180** |
    | `bmad_orchestrator` | 11.8 M | 14 : 1 | 8,762 |
    | `bmad_developer` | 2.7 M | 3 : 1 | 6,191 |

    The whole crew burned **64 M tokens**, and one agent — the SRE investigator —
    is **72%** of it. Note the **input : output ratio**: 38 input tokens for every
    output token means the model re-reads a large context on *every* call. That
    ratio, not the raw total, is your waste compass. Start there.

## 2. The four highest-leverage cuts

### a) Remove tools the agent never uses

Every tool an agent is granted is described in **every** prompt sent to the
model — that's input tokens on every single call, whether the tool is used or
not. In the traces, look at which tools an agent *actually* calls over many runs;
anything never called is pure overhead.

Trim the agent's `toolNames` to only what it uses:

```yaml
# agents/sre/sre-agent.yaml (illustrative)
spec:
  tools:
    - type: McpServer
      mcpServer:
        toolNames:        # ← keep only the tools this agent actually calls
          - list_pods
          - get_logs
          - dql_query
          # dropped: a dozen k8s tools the SRE agent never invoked
```

List the tools the agent *actually* calls straight from the traces, then diff
against its granted set:

```
fetch spans
| filter service.namespace == "kagent" and service.name == "seta_sre_investigator"
    and gen_ai.operation.name == "execute_tool" and gen_ai.tool.name != "(merged tools)"
| summarize calls = count(), by:{tool = gen_ai.tool.name}
| sort calls desc
```

!!! example "Measure the schema tax directly"
    Each tool is a JSON schema injected into every prompt. On the reference
    tenant one captured `call_llm` request carried **7** tool declarations costing
    **~1,160 input tokens** — about **165 tokens per tool, on every call**. The
    shipped SRE agent (`agents/sre/sre-agent.yaml`) attaches the Dynatrace MCP
    server with **no `toolNames` filter** (every discovered tool) *plus* 15 k8s
    tools. Pin `toolNames` to the handful the traces prove it uses and you reclaim
    those tokens on all 1,357 calls — before touching anything else.

The workshop ships that cut ready-made: `agents/sre/sre-agent-lean.yaml` is the
same agent with the Dynatrace MCP pinned to five tools (`list_problems`,
`execute_dql`, `find_entity_by_name`, `get_kubernetes_events`,
`get_environment_info`) instead of all seventeen. Apply it, send the same
prompts, and compare input-token counts in Dynatrace:

```bash
applyLeanSreAgent
generateAgentTraffic
```

Fewer tools → smaller prompts → lower cost on *every* call. To revert:
`kubectl apply -k agents/sre`.

<!-- LAB_QUESTION
type: shell-verification
question: "Verify the SRE agent now pins its Dynatrace tools"
buttonText: "Check agent"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkLeanSreAgent"
expect:
  operator: exit-zero
hint: "Run `applyLeanSreAgent` in the Terminal, then check again."
explanation: "The agent's Dynatrace tool list is pinned — every prompt now carries five tool schemas instead of seventeen."
-->

<!-- LAB_SOLUTION
commands:
  - applyLeanSreAgent
  - waitForAgentsAccepted
  - generateAgentTraffic
verify:
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkLeanSreAgent
reveal: |
  `sre-agent-lean.yaml` differs from `sre-agent.yaml` in one place: a
  `toolNames` list under the `dynatrace-mcp-remote` tool server. kagent then
  sends only those five tool schemas to the model on every call.
-->

### b) Tighten the system prompt

A rambling system prompt is a fixed tax on every request. Shorten it to the
essentials; move examples out unless they measurably improve the eval score.

### c) Fix chatty workflows

In a BMAD run, the span waterfall (module 6) shows how many A2A hops and LLM
calls a task took. Redundant hand-offs, an agent that re-reads context it already
has, or a loop that retries silently all show up as extra `gen_ai` spans. Collapse
the hops that don't earn their tokens.

```
fetch spans
| filter service.namespace == "kagent" and span.name == "call_llm"
| summarize llmCalls = count(), inputTokens = sum(gen_ai.usage.input_tokens),
    by:{agent = service.name, task = gen_ai.task.id}
| filter llmCalls >= 5
| sort inputTokens desc
```

!!! example "Loops are where big agents actually bleed"
    On the reference tenant the SRE investigator's heaviest task made **7
    `call_llm` hops and re-sent 228,000 input tokens** — the same growing context
    pushed to the model again and again. For an already-lean agent (few tools,
    tight prompt) this loop re-send, *not* unused tools, is the dominant cost. The
    dashboard's **loop table** ranks these so you fix the worst first.

### d) Right-size the model per agent

Not every agent needs the most capable model. kagent makes the model a
one-line `ModelConfig` reference, so you can point a cheap, mechanical agent
(e.g. a formatter) at a smaller/cheaper model while the reasoning-heavy
orchestrator keeps the stronger one. This workshop already defaults the whole
crew to **DeepSeek** for cost; per-agent tuning goes further.

```yaml
# agents/mcp/00-modelconfig.yaml — the shared workshop-llm (DeepSeek, cost-first)
# Create a second, cheaper ModelConfig and reference it from the agents that
# don't need the strong model. One field per agent: spec.modelConfig.
```

## 3. Prove the win

Open the **before/after notebook** (deployed above). Its §5 cell measures the one
number that moves — average input tokens per `call_llm` — and the section
time-picker is how you switch the *before* and *after* windows:

```
fetch spans
| filter service.namespace == "kagent" and service.name == "seta_sre_investigator"
    and span.name == "call_llm" and isNotNull(gen_ai.usage.input_tokens)
| summarize llmCalls = count(),
    avgInputPerCall    = round(avg(gen_ai.usage.input_tokens)),
    medianInputPerCall = round(median(gen_ai.usage.input_tokens)),
    totalInputTokens   = sum(gen_ai.usage.input_tokens)
```

The procedure, in order:

1. Run the query over a window *before* the change — record `avgInputPerCall`.
2. Make **one** change (trim tools / tighten prompt / collapse hops / right-size model).
3. Re-apply and replay the **same** prompts.
4. Run the query over the *after* window and run the dt-evals suite (module 8).

Fill the scorecard from those two runs:

| Metric | Before | After | Keep? |
|--------|:---:|:---:|:---:|
| Avg input tokens / call | *(§5 notebook)* | *(§5 notebook)* | — |
| Est. cost / task | — | — | — |
| Eval pass rate | *(module 8)* | *(module 8)* | ✅ only if ≥ before |

!!! success "The rule"
    Ship the change when **cost went down and the eval pass rate did not**. If
    quality dropped, revert — the cheaper agent that's wrong is more expensive
    than the costly one that's right.

## 4. Make it continuous — the guardian + workflow

Optimization isn't a one-off. Because cost and quality are now both telemetry,
the workshop ships two more dtctl-ready artifacts in
[`cluster/dynatrace/optimization/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/cluster/dynatrace/optimization)
that turn the optimization loop into an automated gate:

**A Site Reliability Guardian** (`ai-agent-quality-cost.guardian.yaml`) — three
DQL objectives over the crew's `call_llm` spans, so a regression fails loudly:

| Objective | SLI | Rule | target / warning |
|-----------|-----|------|------------------|
| Cost per LLM call | avg input tokens / call | `≤` | 20,000 / 18,000 |
| Loop efficiency | avg hops / task | `≤` | 5 / 4 |
| Answer substance (quality proxy) | avg output tokens / call | `≥` | 200 / 300 |

```bash
dtctl create settings -f ai-agent-quality-cost.guardian.yaml \
  --schema app:dynatrace.site.reliability.guardian:guardians --scope environment
```

The quality proxy backstops the cost cuts — an agent that got "cheaper" by
emitting truncated answers trips it. For the full **LLM-judge** quality gate,
pair the guardian with the dt-evals suite (module 8).

**A scheduled Workflow** (`ai-agent-optimization.workflow.yaml`) runs that
guardian daily over the last 24h (schedule ships disabled — flip
`trigger.schedule.isActive: true` to go continuous):

```bash
dtctl create workflow -f ai-agent-optimization.workflow.yaml
```

Beyond the guardian:

- Keep the dt-evals suite in CI as a **regression + budget gate** on every agent
  change.
- Watch the dashboard's **token-trend** tile; the guardian alerts when an
  agent's tokens-per-call drifts up.
- Re-rank your agents periodically — usage patterns change, and today's cheap
  agent is tomorrow's top spender.

## What you achieved (acceptance)

- You identified the most expensive agents from real telemetry.
- You applied at least one concrete cut (unused tools / prompt / hops / model)
  and **proved** with evals that quality held while cost fell.
- You have a repeatable loop — observe → evaluate → change → re-measure — to keep
  agents cost-efficient in production.

<!-- LAB_QUESTION
type: multiple-choice
question: "You trimmed tools and input tokens per call fell 40%, but the eval pass rate dropped from 4/4 to 2/4. What do you do?"
options:
  - "Ship it — cost is the goal of this module"
  - "Revert the change: a cheaper agent that is wrong more often costs more than one that is right"
  - "Keep it and lower the eval threshold to 2/4"
  - "Switch to a larger model and keep the trimmed tools without re-measuring"
correct: 1
explanation: "The rule of the loop: keep a change only if cost went down AND the eval pass rate did not."
-->

## You've completed the arc

**Why → kagent → cluster → agents → secure → observe → diagnose → evaluate → optimize.**
You built a full, cost-efficient AI-agent platform on Kubernetes and have the
telemetry and evals to keep it that way.

Stuck on anything? See **[Troubleshooting](troubleshooting.md)**.
