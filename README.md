# Dynatrace AI Agent Workshop

Hands-on workshop: cost-efficient AI agent workflows with **BMAD, kagent,
Kubernetes, and Dynatrace AI Observability**. The entire lab runs inside a
**GitHub Codespace**. See [ISI-6696](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop)
for the full workshop plan.

## Quick start (Codespace)

1. **Code → Codespaces → Create codespace on `main`**, choosing a
   **4-core / 16 GB** (or larger) machine type.
2. Set the required Codespace secrets (`DT_TENANT_URL`, `DT_API_TOKEN`,
   `GITHUB_TOKEN`, `LLM_API_KEY`) — see [`.devcontainer/SECRETS.md`](.devcontainer/SECRETS.md).
3. Wait for `postCreate` to finish. You'll have a running local Kubernetes
   cluster and the full toolchain.
4. `kubectl get nodes` and `mkdocs serve -a 0.0.0.0:8000`.

Everything is idempotent — re-run `bash .devcontainer/postCreate.sh` any time.

## Repository layout

```
.devcontainer/   # devcontainer.json, Dockerfile, bootstrap scripts, SECRETS/DECISIONS docs
cluster/         # cluster engine configs (Phase 1) + per-component helm/manifests (Phase 2)
  dynatrace/ otel/ kagent/ tetragon/ agent-sandbox/ phoenix/
agents/
  sre/           # SRE agent manifest (Phase 3)
  bmad-crew/     # BMAD crew, adapted from isItObservable/Kagent (Phase 3)
evals/           # Phoenix + dt-evals configs & sample runs (Phase 4)
docs/            # mkdocs content (modules 00..08)
mkdocs.yml
```

## Phases

| Phase | Scope | Issue |
|-------|-------|-------|
| 1 | Devcontainer & Codespace bootstrap | ISI-6713 ✅ |
| 2 | Platform install (operators, kagent, Tetragon, Agent Sandbox, Phoenix) | ISI-6715 |
| 3 | Agents & MCP wiring (SRE agent + BMAD crew) | ISI-6716 |
| 4 | Evaluations (Phoenix + dt-evals) | — |
| 5 | Optimization module (Dynatrace AI Observability) | — |
| 6 | mkdocs workshop content | — |

## Key docs

- [Codespace secrets contract](.devcontainer/SECRETS.md)
- [Phase 1 decisions (k3d vs kind, machine type)](.devcontainer/DECISIONS.md)
