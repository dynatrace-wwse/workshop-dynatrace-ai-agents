# 4. Agents & MCP wiring

With the platform up (module 3), wire MCP tooling into kagent and deploy the
two agent sets. Everything lives under
[`agents/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/agents)
and installs with one idempotent script.

!!! info "What gets deployed"
    A shared **`workshop-llm`** ModelConfig (**DeepSeek**, OpenAI-API compatible),
    the **GitHub** and **Dynatrace** MCP tool servers, an **SRE agent**, and the
    six-member **BMAD crew**. kagent's built-in **`kagent-tool-server`** (default
    Kubernetes tooling) is turned on for this phase.

## The tool surfaces

| Tool | Source | Agent |
|------|--------|-------|
| Kubernetes / `kubectl` + k8s-networking | built-in `kagent-tool-server` | SRE |
| Dynatrace (problems, entities, logs/DQL, metrics, Davis) | `dynatrace-mcp-remote` | SRE |
| GitHub (issues, PRs, repo contents) | `github-mcp-remote` | BMAD crew |

All agents share one model: **`workshop-llm`** — **DeepSeek** (`deepseek-chat`,
DeepSeek-V3), chosen for the workshop's cost-efficiency theme. DeepSeek's API is
OpenAI-compatible, so kagent's OpenAI provider is pointed at
`https://api.deepseek.com/v1` and reads the key from `secret/kagent-deepseek`.
Swap to OpenAI or Anthropic in `agents/mcp/00-modelconfig.yaml` (one-line change).

## 1. The built-in Kubernetes tooling

kagent's built-in tools are switched on in
[`cluster/kagent/values.yaml`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/kagent/values.yaml),
which the platform install (module 3) already used:

```yaml
kagent-tools: { enabled: true }   # built-in kagent-tool-server (k8s + networking)
```

<!-- LAB_QUESTION
type: shell-verification
question: "Verify kagent's built-in tool server discovered its Kubernetes tools"
buttonText: "Check tools"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkToolsDiscovered"
expect:
  operator: exit-zero
hint: "The tool server registers its tools a minute after kagent starts. Wait, then check again; if it stays empty run `installKagent`."
explanation: "kagent-tool-server is up and advertises k8s_get_resources and friends — the SRE agent's hands on the cluster."
-->

## 2. The MCP credentials

The MCP servers receive their credentials **at apply time**; nothing is
committed:

| Variable | Used by | In the Enablement App |
|----------|---------|---|
| `DT_PLATFORM_TOKEN` | Dynatrace MCP (problems, entities, DQL, Davis) | injected for you |
| `DT_ENVIRONMENT` | Dynatrace MCP — the platform **apps** URL | injected for you |
| `GH_PAT` | GitHub MCP (BMAD crew write-back) | optional — fine-grained PAT, one demo repo, Contents/Issues/PRs RW |

Without `GH_PAT` the BMAD crew still deploys and still plans and designs —
it just cannot open issues or pull requests.

!!! warning "Token in pod env"
    The GitHub/Dynatrace MCP servers receive their token as a pod env var
    (kagent's `MCPServer` env is a static map). Scope the tokens tightly and
    rotate them after the workshop.

## 3. Install the agents

```bash
installAgents
```

`installAgents` applies, in order: the `workshop-llm` ModelConfig (DeepSeek
when you have a key, the in-cluster Ollama model otherwise), the GitHub and
Dynatrace MCP servers, the SRE agent, then the six BMAD agents — and waits until
all seven are Accepted.

## 4. Verify the tools registered

```bash
kubectl -n kagent get mcpserver,remotemcpserver
kubectl -n kagent get remotemcpserver kagent-tool-server  -o jsonpath='{.status.discoveredTools[*].name}'; echo
kubectl -n kagent get remotemcpserver github-mcp-remote    -o jsonpath='{.status.discoveredTools[*].name}'; echo
kubectl -n kagent get remotemcpserver dynatrace-mcp-remote -o jsonpath='{.status.discoveredTools[*].name}'; echo
kubectl -n kagent get agents
```

Each `RemoteMCPServer` should be Accepted with a non-empty `discoveredTools`
list, and all seven agents (`sre-agent` + six `bmad-*`) should be Accepted.

<!-- LAB_QUESTION
type: shell-verification
question: "Verify all seven agents are Accepted"
buttonText: "Check agents"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkAgents"
expect:
  operator: exit-zero
hint: "Run `installAgents` in the Terminal, wait for it to report 'All 7 agents Accepted', then check again."
explanation: "sre-agent and the six bmad-* agents are reconciled by the kagent controller and reachable over A2A."
-->

## 5. Send a sample prompt

There are two ways to talk to any agent, and they are interchangeable — both land
on the same A2A endpoint and produce the same traces:

- **kagent UI** — pick the agent, drop a prompt in the chat. Best for exploring
  interactively and watching the agent's loop unfold turn by turn.
- **A2A** — a JSON-RPC `message/send` to the controller. Best for scripting, CI,
  or pasting a prompt verbatim. `askAgent` wraps it.

**kagent UI**

Open the **kagent** app (`listApps` prints the URL), pick **sre-agent**, and paste:

> List the pods in the `kagent` namespace and tell me if any are unhealthy.

**A2A**

```bash
askSreAgent "List the pods in the kagent namespace and tell me if any are unhealthy."
```

The raw call it makes:

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List the pods in the kagent namespace."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

!!! tip "BMAD crew — a longer, multi-hop trace"
    With a `GH_PAT`, send the orchestrator a build task — in the UI pick
    **bmad-orchestrator**, or:
    `askAgent bmad-orchestrator "Build a simple Todo app in <owner>/<repo>. Run the full BMAD workflow and open a PR." 900`.
    It is optional — the rest of the workshop uses the SRE agent.

<!-- LAB_QUESTION
type: shell-verification
question: "Verify the SRE agent answered your prompt over A2A"
buttonText: "Check answer"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkAgentAnswered sre-agent"
expect:
  operator: exit-zero
hint: "Run `askSreAgent` in the Terminal first. On the in-cluster model the first answer can take 1–2 minutes while the model loads."
explanation: "The SRE agent ran its tool loop (LLM → k8s tools → LLM) and returned an answer."
-->

<!-- LAB_SOLUTION
commands:
  - installAgents
  - askSreAgent "List the pods in the kagent namespace and tell me if any are unhealthy." 420
verify:
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkAgents
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkAgentAnswered sre-agent
reveal: |
  `installAgents` renders the MCP layer with your tokens (envsubst at apply
  time, never committed), applies `agents/sre` and `agents/bmad-crew` with
  kustomize and waits for all seven agents to be Accepted. `askSreAgent` then
  sends one A2A `message/send` to the SRE agent and prints its answer.
-->

## 6. See the traces

Agent LLM and tool-call spans flow automatically (kagent `otel.tracing`, wired in
module 3) through the OTel gateway to **both** backends:

- **Phoenix** — the `phoenix` app (`listApps`) for LLM eval/trace inspection.
- **Dynatrace** — distributed traces on your tenant.

<!-- LAB_QUESTION
type: multiple-choice
question: "Which protocol does the BMAD orchestrator use to hand work to the analyst, PM, architect, developer and QA agents?"
options:
  - "A2A — agents call each other as agents"
  - "MCP — each crew member is a tool server"
  - "OTLP — the gateway collector routes the tasks"
  - "A Kubernetes Job per crew member"
correct: 0
explanation: "MCP is how an agent calls tools; A2A is how agents call other agents. The orchestrator's crew members are listed as `type: Agent` tools and reached over A2A."
-->

<div class="grid cards" markdown>
- [5. Secure agents :octicons-arrow-right-24:](5-secure.md)
</div>
