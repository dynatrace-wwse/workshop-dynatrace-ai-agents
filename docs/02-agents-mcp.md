# 02 — Agents & MCP wiring

With the platform up (module 01), wire MCP tooling into kagent and deploy the
two agent sets. Everything lives under
[`agents/`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/tree/main/agents)
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

## 1. Enable the default Kubernetes tooling

Module 01 shipped kagent as a clean base with the built-in tools **off**. This
module turns them on (already set in
[`cluster/kagent/values.yaml`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/cluster/kagent/values.yaml)):

```yaml
kagent-tools: { enabled: true }   # built-in kagent-tool-server (k8s + networking)
```

If you installed the platform before this change, re-run `bash cluster/install.sh`
to roll kagent and create the `kagent-tool-server`.

## 2. Provide the MCP credentials

These are injected **at apply time** and never committed. You created them during
onboarding — see
**[Start the benchmark → Create the required tokens](start-benchmark.md#4-create-the-required-tokens)**
for the exact permissions and where each is generated:

| Variable | Used by | Notes |
|----------|---------|-------|
| `GH_PAT` | GitHub MCP | Fine-grained PAT scoped to the **one** demo repo: Contents RW · Issues RW · Pull requests RW. No org/admin. ([token E](start-benchmark.md#e-github-fine-grained-pat-gh_pat)) |
| `DT_PLATFORM_TOKEN` | Dynatrace MCP | Dynatrace **platform** token (`dt0s16.*`) — distinct from the module 01 OTLP `DT_API_TOKEN`. ([token B](start-benchmark.md#b-dynatrace-platform-token-dt_platform_token)) |
| `DT_ENVIRONMENT` | Dynatrace MCP | Platform **apps** URL, e.g. `https://abc12345.apps.dynatrace.com`. Derived from `DT_TENANT_URL` (`.live.`→`.apps.`) if unset. |

```bash
export GH_PAT='github_pat_...'
export DT_PLATFORM_TOKEN='dt0s16....'
export DT_ENVIRONMENT='https://<env>.apps.dynatrace.com'
```

!!! warning "Token in pod env"
    The GitHub/Dynatrace MCP servers receive their token as a pod env var
    (kagent's `MCPServer` env is a static map). Scope the tokens tightly and
    rotate them after the workshop.

## 3. Install

```bash
bash agents/install-agents.sh
```

The script applies, in order: the MCP layer (ModelConfig + GitHub + Dynatrace),
the SRE agent, then the BMAD crew.

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

## 5. Send a sample prompt

=== "SRE agent"

    ```bash
    kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
      --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List the pods in the kagent namespace and tell me if any are unhealthy."}]}}}' \
      http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
    ```

=== "BMAD orchestrator"

    ```bash
    kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
      --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"Build a simple Todo app in <owner>/<repo>. Run the full BMAD workflow and open a PR."}]}}}' \
      http://kagent-controller.kagent:8083/api/a2a/kagent/bmad-orchestrator
    ```

Or use the kagent UI: `kubectl -n kagent port-forward svc/kagent-ui 8080:8080`.

## 6. See the traces

Agent LLM and tool-call spans flow automatically (kagent `otel.tracing`, wired in
module 01) through the OTel gateway to **both** backends:

- **Phoenix** — `http://localhost:6006` (forwarded Codespace port) for LLM
  eval/trace inspection.
- **Dynatrace** — distributed traces on your tenant.

That satisfies the acceptance for this phase: both agent sets respond to a sample
prompt, and their traces land in Phoenix and Dynatrace.
