# Dynatrace AI Agent Workshop

[![Publish docs](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/actions/workflows/gh-pages.yml/badge.svg)](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/actions/workflows/gh-pages.yml)

A hands-on, self-paced workshop for building, securing, observing, evaluating,
and **cost-optimizing AI agent workflows** with **BMAD, kagent, Kubernetes, and
Dynatrace AI Observability**. The entire lab runs inside a single **GitHub
Codespace** — no local install — so you can go from an empty environment to a
fully observed, cost-optimized agent platform in one sitting.

## 📖 Read the workshop online

**👉 [henrikrexed.github.io/dynatrace-AI-Agent-Workshop](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/)**

The full, rendered workshop — every module, the guided demo, and the
troubleshooting reference — is published as a MkDocs Material site. Start with
the **[Start the benchmark](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/start-benchmark/)**
page, then follow the modules in order.

> You can also read it offline inside your Codespace: `mkdocs serve -a 0.0.0.0:8000`
> and open the forwarded port **8000**.

## What is this?

AI agents are evolving fast, but many teams struggle with rising token costs,
limited visibility, and unreliable behavior in production. This workshop walks
you through a realistic agent platform on Kubernetes and shows how to **see what
your agents actually do**, **prove whether they're any good**, and **cut the
waste** — using Dynatrace AI Observability end to end.

You'll run two agent sets — an **SRE agent** that investigates a broken cluster,
and the **BMAD software-building crew** — then observe, evaluate, and optimize
them.

## What's covered

- **Control AI agent cost** — understand and tame the biggest driver of spend.
- **Build structured multi-agent workflows** with BMAD.
- **Deploy AI agents on Kubernetes** using kagent.
- **Secure agents** with Tetragon runtime security and Agent Sandbox.
- **Observe** cost, tokens, latency, and quality with Dynatrace AI Observability.
- **Diagnose** a broken cluster by letting an agent find the root cause.
- **Evaluate** agents with Phoenix (Arize) + dt-evals.
- **Optimize** — find unused tools/skills and cut token spend without losing quality.

## How to start

1. **Fork this repository** to your own GitHub account (top-right **Fork**).
   Forking also publishes your own copy of this site via GitHub Pages (see below).
2. In your fork: **Code → Codespaces → Create codespace on `main`**, choosing a
   **4-core / 16 GB** (or larger) machine type.
3. Set the required Codespace secrets — your Dynatrace tokens, `GH_PAT`,
   `GH_DEMO_REPO`, and `LLM_API_KEY`. The full list and how to generate each is
   in [`.devcontainer/SECRETS.md`](.devcontainer/SECRETS.md).
4. Wait for `postCreate` to finish. You'll have a running local Kubernetes
   cluster and the full toolchain.
5. Sanity-check with `kubectl get nodes`, then open the workshop:
   `mkdocs serve -a 0.0.0.0:8000`.

Everything is idempotent — re-run `bash .devcontainer/postCreate.sh` any time.

The on-site **[Start the benchmark](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/start-benchmark/)**
page walks through these steps in full, including how to generate each token.

## Workshop modules

The workshop follows a single learning arc: **why → runtime → build → deploy →
secure → observe → diagnose → evaluate → optimize.**

| Module | What you do |
|--------|-------------|
| [kagent in 5 minutes](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/kagent-explainer/) | The agentic runtime on Kubernetes, in one page. |
| [00 — Setup (Codespace)](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/00-setup/) | Boot the cluster and toolchain. |
| [01 — Platform install](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/01-platform-install/) | Operators, kagent, Tetragon, Agent Sandbox, Phoenix. |
| [02 — Agents & MCP wiring](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/02-agents-mcp/) | Deploy the SRE agent + BMAD crew. |
| [03 — Secure agents](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/03-secure/) | Tetragon + Agent Sandbox. |
| [04 — Observe with Dynatrace](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/04-observe/) | Cost, tokens, latency, quality. |
| [05 — Diagnose a broken cluster](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/05-diagnose/) | Inject a fault; let the agent find the root cause. |
| [06 — Evaluate (Phoenix + dt-evals)](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/06-evaluate/) | Score quality + cost. |
| [07 — Optimize](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/07-optimize/) | Cut the waste, keep the quality. |

Running the workshop live? The
**[Run of show (guided demo)](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/run-of-show/)**
stitches the modules into one top-to-bottom 13-step script, with a link back to
each module for the depth behind every step. Stuck? The
**[Troubleshooting](https://henrikrexed.github.io/dynatrace-AI-Agent-Workshop/troubleshooting/)**
page collects the common fixes per module.

## Repository layout

```
.devcontainer/   # devcontainer.json, Dockerfile, bootstrap scripts, SECRETS/DECISIONS docs
cluster/         # cluster engine configs (module 01) + per-component helm/manifests
  dynatrace/ otel/ kagent/ tetragon/ agent-sandbox/ phoenix/
agents/
  sre/           # SRE agent manifest
  bmad-crew/     # BMAD crew, adapted from isItObservable/Kagent
evals/           # Phoenix + dt-evals configs & sample runs
scenarios/       # diagnose module fault-injection assets (module 05)
docs/            # mkdocs content (the published site source)
mkdocs.yml
.github/workflows/gh-pages.yml   # builds & publishes the site to GitHub Pages
```

## About the published site (GitHub Pages)

The `.github/workflows/gh-pages.yml` workflow builds the MkDocs Material site
(`mkdocs build --strict`) on every push to `main` and publishes it to the
`gh-pages` branch — no secrets required. Because the workflow runs on **your
fork**, forking this repo also publishes **your own** copy of the site at
`https://<your-username>.github.io/dynatrace-AI-Agent-Workshop/` once GitHub
Pages is enabled on the fork (**Settings → Pages → Source: Deploy from a branch →
`gh-pages` / `/ (root)`**).

## Key docs

- [Codespace secrets contract](.devcontainer/SECRETS.md)
- [Architecture notes (kind, machine type)](.devcontainer/DECISIONS.md)
</content>
</invoke>
