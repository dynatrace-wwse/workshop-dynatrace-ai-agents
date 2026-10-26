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
| `DT_TENANT_URL` | Dynatrace tenant used by the Operator (k8smonitoring) and the Dynatrace MCP. | `https://abc12345.live.dynatrace.com` |
| `DT_API_TOKEN` | Dynatrace API token. Scopes needed by later phases: Kubernetes monitoring / ActiveGate token for the operator, plus read scopes for the MCP (metrics/problems/entities). | `dt0c01.XXXX...` |
| `GITHUB_TOKEN` | Token for the **GitHub MCP** wired into the agents (Phase 3). In Codespaces a scoped `GITHUB_TOKEN` is usually injected automatically; provide a PAT only if broader scopes are required. | `ghp_...` / `github_pat_...` |
| `LLM_API_KEY` | Model-provider key that powers the kagent agents. Which provider is chosen in Phase 3 — set whichever matches the chosen model. | provider-specific |

## Optional secrets

| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | If agents target an OpenAI-compatible endpoint. |
| `ANTHROPIC_API_KEY` | If agents target Anthropic models. |

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
