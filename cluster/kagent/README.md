# cluster/kagent — kagent runtime (clean base)

Installs kagent from its **OCI** Helm charts as a **clean base**: the controller,
UI, kmcp (MCP framework), and bundled database run, but **no default agents and
no default tool servers** are installed. Phase 3 (agents & MCP wiring) adds the
SRE agent, the BMAD crew, and the GitHub/Dynatrace/k8s MCP servers on top.

| File | Role |
|------|------|
| `values.yaml` | kagent Helm values — disables all built-ins, wires OTLP tracing. |

## OCI charts (no `helm repo add`)

kagent moved off the classic `kagent-dev.github.io` Helm repo (now 404) to OCI:

```bash
helm upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds --version 0.10.4 -n kagent
helm upgrade --install kagent      oci://ghcr.io/kagent-dev/kagent/helm/kagent      --version 0.10.4 -n kagent -f values.yaml
```

`install.sh` does both (CRDs first). Versions are pinned in `../versions.env`.

## What "clean base" disables

- Built-in agents: `k8s-agent`, `kgateway-agent`, `istio-agent`, `promql-agent`,
  `observability-agent`, `argo-rollouts-agent`, `helm-agent`,
  `cilium-{policy,manager,debug}-agent` — all `enabled: false`.
- Built-in tool servers: `kagent-tools` and `grafana-mcp` — `enabled: false`.
- Kept: `controller`, `ui`, `kmcp` (MCP plumbing Phase 3 needs), bundled DB.

## Model provider

Provider is decided in Phase 3. Default is **OpenAI**, reading the
key from `secret/kagent-openai` (created by `secrets.sh` from `LLM_API_KEY` or
`OPENAI_API_KEY`). Switch `providers.default` to `anthropic`/`ollama`/`gemini`
in Phase 3 — the chart generates the matching default `ModelConfig`.

## Observability

`otel.tracing` is enabled and points at the gateway collector
(`otel-gateway-collector...:4317`), so Phase 3 agents emit LLM/tool spans to
Dynatrace + Phoenix with no extra wiring.

## Verify

```bash
kubectl -n kagent get pods                 # controller + ui + kmcp + db Ready
kubectl -n kagent get agents 2>/dev/null   # empty — clean base, as intended
kubectl -n kagent port-forward svc/kagent-ui 8080:8080
```
