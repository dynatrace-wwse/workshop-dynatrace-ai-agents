# 00 — Setup (Codespace)

This module gets you from zero to a running local Kubernetes cluster inside a
GitHub Codespace, with the full workshop toolchain installed.

!!! tip "Start here first"
    If you haven't forked the repo and created your tokens yet, begin with
    **[Start the benchmark](start-benchmark.md)** — it walks fork → Codespace →
    secrets end to end. This module is the detailed Codespace reference.

## 1. Open the Codespace

1. On **your fork**, click **Code → Codespaces → Create codespace on `main`**.
2. **Machine type:** choose **4-core / 16 GB** or larger. The default
   2-core/4GB is *not* enough for the full stack (see
   [`.devcontainer/DECISIONS.md`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/.devcontainer/DECISIONS.md)).

The devcontainer builds, then `postCreate` automatically:

- verifies the toolchain (`kubectl`, `helm`, `kind`, `k3d`, `kagent`, `uv`, `mkdocs`),
- creates a local Kubernetes cluster (k3d by default),
- stages namespaces + Helm repos for the platform install,
- reports which secrets are present.

## 2. Configure secrets

All required tokens — what each is, the exact permissions, and where to create
each one — live on a single page:
**[Start the benchmark → Create the required tokens](start-benchmark.md#4-create-the-required-tokens)**.
Set them as **Codespace secrets** (scoped to your fork) as described there, then
rebuild or restart the Codespace. Full machine-readable contract:
[`.devcontainer/SECRETS.md`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/.devcontainer/SECRETS.md).

Verify presence (values are never printed):

```bash
bash .devcontainer/bootstrap/check-secrets.sh
```

## 3. Verify the cluster

```bash
kubectl get nodes
kubectl get namespaces
```

You should see a Ready node and the staged namespaces (`dynatrace`, `kagent`,
`tetragon`, `phoenix`, …).

## 4. Re-running the bootstrap (idempotent)

Everything is safe to re-run:

```bash
bash .devcontainer/postCreate.sh     # full bootstrap (reuses an existing cluster)
bash .devcontainer/postStart.sh      # restart the cluster after a resume
```

## 5. Serve this site locally

```bash
mkdocs serve -a 0.0.0.0:8000
```

Open the forwarded port **8000**.

## Next

Phase 2 installs the platform (Dynatrace Operator, OpenTelemetry Operator,
kagent, Tetragon, Agent Sandbox, Phoenix).
