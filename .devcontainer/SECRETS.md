# Codespace Secrets Contract

> **Never commit secrets.** These are provided as **Codespace secrets**, injected
> as environment variables at container start. Nothing here is stored in git.
> `.devcontainer/bootstrap/check-secrets.sh` reports which are present (values are
> never printed) and runs automatically during `postCreate`.

## Where to set them

GitHub → **Settings → Codespaces → Secrets** (user-level) or the repo's
**Settings → Secrets and variables → Codespaces** (repo-level). Scope each secret
to the `henrikrexed/dynatrace-AI-Agent-Workshop` repository. After adding/rotating
a secret, **rebuild or restart the Codespace** so the new value is injected.

## Required secrets

| Variable | Purpose | Example / format |
|----------|---------|------------------|
| `DT_TENANT_URL` | Dynatrace tenant used by the Operator (k8smonitoring) and OTLP export. | `https://abc12345.live.dynatrace.com` |
| `DT_API_TOKEN` | Dynatrace API token for the operator + OTLP ingest (metrics/traces/logs ingest scopes). | `dt0c01.XXXX...` |
| `GITHUB_TOKEN` / `GH_PAT` | Token for the **GitHub MCP** wired into the BMAD crew (Phase 3). Codespaces injects a scoped `GITHUB_TOKEN`; for the write demo provide a **fine-grained `GH_PAT`** scoped to the one demo repo (Contents RW · Issues RW · Pull requests RW; no org/admin). The installer prefers `GH_PAT`, falling back to `GITHUB_TOKEN`. | `github_pat_...` |
| `LLM_API_KEY` / `DEEPSEEK_API_KEY` | Model-provider key that powers the kagent agents. **DeepSeek by default** (Phase 3, cost-efficient; `secret/kagent-deepseek`). `DEEPSEEK_API_KEY` is preferred; `LLM_API_KEY` is the generic fallback and should hold the DeepSeek key when DeepSeek is the provider. | `sk-...` (DeepSeek) |
| `GH_DEMO_REPO` | The **BMAD/"bad crew"** demo repository the GitHub MCP writes to (issues/PRs). Explicit var so the environment test can assert it. | `owner/repo` or full URL |

## Phase 3 / 5 — Dynatrace platform (`dtctl` + Dynatrace MCP)

Both the **Dynatrace MCP server** (`@dynatrace-oss/dynatrace-mcp-server`, SRE
agent) and the **`dtctl` CLI** (Phase 5 optimization — dashboards, notebooks,
SRG, workflows) authenticate against the Dynatrace **platform**, which uses a
different token and URL than the Phase-2 operator/OTLP pair above. They share
**one** platform token:

| Variable | Purpose | Example / format |
|----------|---------|------------------|
| `DT_PLATFORM_TOKEN` | Dynatrace **platform** token for the SRE agent's Dynatrace tools (problems/entities/logs/metrics) **and** `dtctl`. Distinct from `DT_API_TOKEN`. | `dt0s16.XXXX...` |
| `DT_ENVIRONMENT` | Dynatrace **platform (apps)** URL used by the MCP and `dtctl`. If unset, `agents/install-agents.sh` derives it from `DT_TENANT_URL` by swapping `.live.`→`.apps.`. | `https://abc12345.apps.dynatrace.com` |

For the MCP, these are injected at **apply time** by `agents/install-agents.sh`
(into the kagent-managed MCP server pods) — not stored as long-lived cluster
secrets. `dtctl` reads them from the environment / its own context config.

## Phase 4 — dt-evals (trace-sourced LLM-as-judge)

The **dt-evals** CLI pulls `gen_ai.*` spans from Dynatrace and writes
`gen_ai.evaluation.result` events back. It uses its **own** token — distinct
from the Phase-2 OTLP ingest token:

| Variable | Purpose | Example / format |
|----------|---------|------------------|
| `DYNATRACE_API_TOKEN` | Dedicated dt-evals token. Scopes: **`storage:spans:read` + `storage:events:write`** (read spans, write eval events). | `dt0c01.XXXX...` |
| `DT_ENV_URL` / `DT_ENVIRONMENT_URL` | dt-evals tenant URL. If unset, `run-dt-eval.sh` derives it from `DT_TENANT_URL`. | `https://abc12345.live.dynatrace.com` |
| `DT_EVAL_SERVICE` | `service.name` of the agent to evaluate — **discovered**, not a secret (optional; see `evals/dt-evals/README.md`). | `sre-agent` |

See `evals/.env.example` and `evals/dt-evals/.env.example` for the full
eval-path env files.

## Optional secrets

| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | If you switch the agents back to OpenAI (`secret/kagent-openai`). |
| `ANTHROPIC_API_KEY` | If agents target Anthropic models (`secret/kagent-anthropic`). |

## How secrets flow into the cluster

The bootstrap only **verifies presence**. The platform install consumes them, e.g.:

```bash
# Example only — the platform install owns the real manifests/Helm values.
kubectl -n dynatrace create secret generic dynatrace-tokens \
  --from-literal=apiToken="$DT_API_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
```

Secrets must be referenced from env/Helm values at install time — **never** baked
into committed manifests or the devcontainer image.

## Rotation

Rotate in the GitHub Codespaces secrets UI, then rebuild the Codespace
(`Codespaces: Rebuild Container`). Re-run `bash .devcontainer/bootstrap/check-secrets.sh`
to confirm the new values are visible.
