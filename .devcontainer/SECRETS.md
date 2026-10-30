# Secrets contract

> **Never commit secrets.** They arrive as environment variables: injected per
> learner by the Dynatrace Enablement App (Orbital), or set as Codespace secrets.
> Check presence by name only — `variablesNeeded NAME:false …` never prints a value.

## Variables

| Variable | Who provides it | Used by | Without it |
|---|---|---|---|
| `DT_ENVIRONMENT` | App: injected · Codespace: secret | Operator, OTel gateway, Dynatrace MCP | Dynatrace steps report *not applicable*; everything else runs |
| `DT_OPERATOR_TOKEN` | App: minted (`dt-tokens.yaml` `operator`) | `dynatraceDeployOperator` / k8s-only DynaKube | no Kubernetes monitoring |
| `DT_INGEST_TOKEN` | App: minted (`ingest`) | OTel gateway → Dynatrace OTLP (`Api-Token`, or `Bearer` for a `dt0s16`) | gateway exports to Phoenix only |
| `DT_PLATFORM_TOKEN` | App: minted (`platform`, `kind: platform`) | Dynatrace MCP server (SRE agent), dtctl (module 9) | SRE agent keeps its Kubernetes tools only |
| `DT_HOSTGROUP` | App: injected | names the cluster `<repo>-<session>` → per-learner data isolation | `getDtSessionId` generates one |
| `DEEPSEEK_API_KEY` (or `LLM_API_KEY`) | optional, Codespace secret | `workshop-llm` ModelConfig → DeepSeek | **Ollama** in-cluster (`qwen2.5:3b`) |
| `GH_PAT` | optional, Codespace secret | GitHub MCP for the BMAD crew's write demo — fine-grained, ONE demo repo (Contents/Issues/Pull requests RW) | BMAD crew runs read-only |
| `OPENAI_API_KEY` in `evals/.env` | optional | Phoenix LLM-as-a-judge (module 8 parts A/B) | use part C (deterministic) |

The Dynatrace token scopes are declared in
[`yaml/dt-tokens.yaml`](yaml/dt-tokens.yaml); Orbital mints exactly those.

## Codespace

GitHub → **Settings → Codespaces → Secrets**, scoped to
`dynatrace-wwse/workshop-dynatrace-ai-agents`. Secrets apply to codespaces created
*after* they are set — rebuild the container after adding one.
