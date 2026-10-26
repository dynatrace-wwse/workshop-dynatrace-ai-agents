# agents/

kagent agent manifests and MCP wiring — **Phase 3** (ISI-6716).

```
agents/
├── mcp/                      # shared ModelConfig + MCP tool servers
│   ├── 00-modelconfig.yaml   # workshop-llm — the shared DeepSeek brain
│   ├── 10-github-mcp.yaml    # GitHub MCP  (MCPServer + RemoteMCPServer)
│   └── 20-dynatrace-mcp.yaml # Dynatrace MCP (MCPServer + RemoteMCPServer)
├── sre/                      # SRE agent (kubectl + k8s-networking + dynatrace)
│   └── sre-agent.yaml
├── bmad-crew/                # BMAD software-building crew (6 agents)
│   └── 0{1..6}-bmad-*.yaml
└── install-agents.sh         # applies all of the above, in order
```

## What gets wired (plan §4/§5)

| Tool surface | Source | Used by |
|--------------|--------|---------|
| **Kubernetes / kubectl** + **k8s-networking** | built-in `kagent-tool-server` (kagent chart, `kagent-tools` enabled in Phase 3) | SRE agent |
| **Dynatrace** | `dynatrace-mcp-remote` → in-cluster `@dynatrace-oss/dynatrace-mcp-server` | SRE agent |
| **GitHub** (issues/PRs/repos) | `github-mcp-remote` → in-cluster `ghcr.io/github/github-mcp-server` | BMAD crew |

All agents share one **`workshop-llm`** ModelConfig (**DeepSeek** by default —
OpenAI-API compatible, reading `secret/kagent-deepseek`; swap to OpenAI/Anthropic
in one file). kagent's `otel.tracing` (wired in Phase 2) sends every
agent's LLM/tool spans to Dynatrace + Phoenix automatically.

## Install

Run **after** the Phase 2 platform install (`cluster/install.sh`), which brings
up kagent with `kagent-tool-server` enabled:

```bash
export GITHUB_PAT='<fine-grained PAT, demo repo only>'   # BMAD crew → GitHub
export DT_PLATFORM_TOKEN='dt0s16....'                     # SRE agent → Dynatrace
export DT_ENVIRONMENT='https://<env>.apps.dynatrace.com'  # or derived from DT_TENANT_URL
bash agents/install-agents.sh
```

Tokens are injected at apply time (never committed). See `cluster/kagent/README.md`
for the clean-base kagent install and `docs/02-agents-mcp.md` for the full
walk-through, verification, and sample prompts.
