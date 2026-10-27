# kagent in 5 minutes

Before you build anything, here's the mental model for **kagent** — the piece
that turns "an LLM calling some tools" into **agents you can deploy, secure,
observe, and evaluate like any other Kubernetes workload**.

## Why run agents on Kubernetes at all?

An AI agent is a loop: a model reads a goal, decides which **tool** to call,
reads the result, and repeats until it's done. Run that loop from a laptop script
and you get no isolation, no shared credentials story, no telemetry, and no way
for one agent to hand work to another. kagent moves the loop onto Kubernetes, so
an agent becomes a first-class, declarative object — reconciled by a controller,
scheduled onto nodes, and wired into the same observability and security tooling
as the rest of your platform.

!!! quote "The one-line definition"
    **kagent is an agentic runtime for Kubernetes.** You describe agents, models,
    and tools as custom resources; a controller runs them, exposes them over a
    standard agent-to-agent (A2A) API, and keeps them reconciled.

## The four objects you'll meet

kagent ships a handful of CRDs. In this workshop you only need four of them:

| CRD | What it is | Where you'll see it |
|-----|------------|---------------------|
| `ModelConfig` | Which LLM an agent talks to (provider, model, endpoint, secret). | [`agents/mcp/00-modelconfig.yaml`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/agents/mcp/00-modelconfig.yaml) — the shared `workshop-llm` (DeepSeek). |
| `Agent` | A deployed agent: a system prompt + a `ModelConfig` + the tools it may call. | the SRE agent and the six BMAD agents (module 02). |
| `MCPServer` | A tool server that runs **inside** the cluster (stdio or HTTP). | GitHub MCP (module 02). |
| `RemoteMCPServer` | A reference to a tool server reached over the network, whose tools kagent discovers. | the built-in `kagent-tool-server`, Dynatrace MCP (module 02). |

Everything else — the controller, the UI, the bundled database, and `kmcp` (the
MCP plumbing) — runs for you once the platform is installed (module 01).

## How a tool call actually happens

```
 you ──prompt──▶  Agent (loop)
                    │  "I need to list pods"
                    ▼
              ModelConfig ──▶ LLM picks a tool + arguments
                    │
                    ▼
            MCP tool server (kagent-tool-server / github / dynatrace)
                    │  returns a result
                    ▼
              Agent feeds result back to the LLM ──▶ repeat ──▶ final answer
```

Two acronyms matter:

- **MCP (Model Context Protocol)** is the open standard for *how an agent
  discovers and calls tools*. kagent speaks it, so any MCP server — GitHub's,
  Dynatrace's, or your own — plugs in the same way.
- **A2A (Agent-to-Agent)** is the protocol *agents* use to call *each other*.
  The BMAD orchestrator delegates to the analyst, PM, architect, developer, and
  QA agents over A2A; that's how a "crew" works when there is no Team CRD.

## Why it fits this workshop's theme

The whole lab is about **cost-efficient** agents. Because kagent makes each tool
call, model call, and agent hand-off a real span emitted over OpenTelemetry (we
wire this in module 01), you can *see* where tokens and latency actually go — and
in module 06 you use that evidence to cut the waste. No runtime, no visibility;
no visibility, no optimization.

!!! tip "You don't configure kagent by hand here"
    Every object above is applied for you by the scripts in modules 01–02. This
    page is just so the YAML you're about to read makes sense. If you want the
    full CRD reference, see the [kagent docs](https://kagent.dev).

## Next

Head to **[00 — Setup (Codespace)](00-setup.md)** to boot the environment, then
install the platform in module 01.
