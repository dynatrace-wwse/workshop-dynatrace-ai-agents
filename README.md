# Dynatrace AI Agent Workshop

[![Integration tests](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/actions/workflows/integration-tests.yaml/badge.svg)](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/actions/workflows/integration-tests.yaml)

A hands-on workshop on building, securing, observing, evaluating and
**cost-optimizing AI agent workflows** with **BMAD, kagent, Kubernetes and
Dynatrace AI Observability**.

> **Author: [Henrik Rexed](https://github.com/henrikrexed)** (Dynatrace, *Is It
> Observable*). This repository is the Dynatrace enablement-framework edition of
> his [`dynatrace-AI-Agent-Workshop`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop),
> imported with its full history. The content, agents, scenarios and evals are
> Henrik's; the migration added the framework environment (k3d, app registry,
> per-learner tokens), quizzes, checks and self-solving steps so it runs in the
> Dynatrace Enablement App.

## How to take it

| Where | How |
|---|---|
| **Dynatrace Enablement App** | Pick *AI Agent Workshop* in the training catalog. Tokens, tenant and cluster are provisioned for you. |
| **GitHub Codespace** | *Code → Codespaces → Create* (4-core / 16 GB). Secrets: [`.devcontainer/SECRETS.md`](.devcontainer/SECRETS.md). |
| **Locally** | `cd .devcontainer && make start` |

Read online: **[dynatrace-wwse.github.io/workshop-dynatrace-ai-agents](https://dynatrace-wwse.github.io/workshop-dynatrace-ai-agents/)**.

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

## Workshop modules

The workshop follows a single learning arc: **why → runtime → build → deploy →
secure → observe → diagnose → evaluate → optimize.**

| Module | What you do |
|--------|-------------|
| 1. kagent in 5 minutes | The agentic runtime on Kubernetes, in one page. |
| 2. Setup | Your k3d cluster, the apps, the LLM backend. |
| 3. Platform install | Operators, OTel gateway, kagent, Phoenix. |
| 4. Agents & MCP | Deploy the SRE agent + BMAD crew, ask over A2A. |
| 5. Secure | Tetragon + Agent Sandbox. |
| 6. Observe | Cost, tokens, latency in Phoenix and Dynatrace. |
| 7. Diagnose | Inject a fault; let the agent find the root cause; grade it. |
| 8. Evaluate | Phoenix + dt-evals + the deterministic diagnosis grader. |
| 9. Optimize | Cut the waste, keep the quality. |

Every hands-on step has a check, every section a quiz, and every step a
*Run solution* (functions in [`.devcontainer/util/my_functions.sh`](.devcontainer/util/my_functions.sh)).

Running the workshop live? The
**[Run of show (guided demo)](https://dynatrace-wwse.github.io/workshop-dynatrace-ai-agents/run-of-show/)**
stitches the modules into one top-to-bottom 13-step script, with a link back to
each module for the depth behind every step. Stuck? The
**[Troubleshooting](https://dynatrace-wwse.github.io/workshop-dynatrace-ai-agents/troubleshooting/)**
page collects the common fixes per module.

## Repository layout

```
.devcontainer/   # devcontainer.json (framework image), post-create, util/my_functions.sh,
                 # yaml/dt-tokens.yaml (tokens Orbital mints), test/integration.sh
cluster/         # versions.env + per-component helm values / manifests
  dynatrace/ otel/ kagent/ tetragon/ agent-sandbox/ phoenix/
agents/
  mcp/           # ModelConfigs (DeepSeek / Ollama), GitHub + Dynatrace MCP servers
  sre/           # SRE agent (+ sre-agent-lean.yaml, module 9)
  bmad-crew/     # BMAD crew, adapted from isItObservable/Kagent
evals/           # Phoenix + dt-evals + ground-truth diagnosis grader
scenarios/       # module 7 fault injection
docs/            # mkdocs content (mkdocs.yaml inherits the framework base)
```

## Published site

`.github/workflows/deploy-ghpages.yaml` (framework template) builds the MkDocs
site from `mkdocs.yaml` and publishes it to `gh-pages`.

## Key docs

- [Secrets contract](.devcontainer/SECRETS.md)
- [Environment decisions (k3d, sizing, LLM backend)](.devcontainer/DECISIONS.md)
- [Open questions for the author](TODO-HENRIK.md)
