# 2. Setup

Your environment is already running: a single-node **k3d** Kubernetes cluster
inside a dev container built from the Dynatrace enablement framework image, with
`kubectl`, `helm`, `k9s`, `node`, `python3` and `dtctl` on the path.

How you got here depends on where you are taking the workshop:

=== "Dynatrace Enablement App (recommended)"

    Your trainer — or you, from the training catalog — started an environment.
    Everything is injected for you, per learner:

    - your tenant URL (`DT_ENVIRONMENT`),
    - an **operator** token and an **ingest** token for the Dynatrace Operator
      and the OpenTelemetry gateway,
    - a **platform** token (`DT_PLATFORM_TOKEN`) for the Dynatrace MCP server,
    - a per-learner id (`DT_HOSTGROUP`), which names your cluster so that your
      data in a shared tenant is yours alone.

    You create **no** tokens. Open the **Terminal** tab and continue.

=== "GitHub Codespace"

    1. Create a Codespace on this repository (**Code → Codespaces → Create
       codespace on `main`**). Choose **4-core / 16 GB** or larger.
    2. When prompted, set the secrets declared in `devcontainer.json`
       (full list in [`.devcontainer/SECRETS.md`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/.devcontainer/SECRETS.md)):

        | Secret | Required | What it is |
        |---|:---:|---|
        | `DT_ENVIRONMENT` | for Dynatrace | `https://<env>.apps.dynatrace.com` |
        | `DT_OPERATOR_TOKEN` | for Dynatrace | operator token (Kubernetes monitoring) |
        | `DT_INGEST_TOKEN` | for Dynatrace | OTLP ingest: traces, metrics, logs, events |
        | `DT_PLATFORM_TOKEN` | for the Dynatrace MCP | `dt0s16` platform token |
        | `DEEPSEEK_API_KEY` | optional | DeepSeek key — without it the agents use an in-cluster model |
        | `GH_PAT` | optional | fine-grained PAT, one demo repo, for the BMAD crew |

=== "Locally (Docker)"

    Put the same variables in `.devcontainer/.env`, then:

    ```bash
    cd .devcontainer && make start
    ```

!!! info "The agents' LLM"
    The agents are cost-optimized for **DeepSeek** (`deepseek-chat`). When no
    `DEEPSEEK_API_KEY` is present — the default in the Enablement App — the
    platform deploys **Ollama** with a small tool-calling model
    (`qwen2.5:3b`) inside your cluster, and the same `workshop-llm`
    `ModelConfig` points at it. Every step of the workshop works on it; answers
    are slower and less sharp than DeepSeek's, which is itself a useful lesson
    for module 9.

## 1. Look at your cluster

```bash
kubectl get nodes
kubectl get namespaces
```

One `Ready` node. The platform namespaces (`dynatrace`, `kagent`, `phoenix`,
`tetragon`, `opentelemetry-operator-system`, `agent-sandbox`, `ollama`) were
created when the environment started — module 3 walks through each.

Check which credentials your session has (names only — values are never printed):

```bash
variablesNeeded DT_ENVIRONMENT:false DT_INGEST_TOKEN:false DT_PLATFORM_TOKEN:false DEEPSEEK_API_KEY:false
```

<!-- LAB_QUESTION
type: shell-verification
question: "Verify your k3d cluster is up"
buttonText: "Check cluster"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkClusterReady"
expect:
  operator: exit-zero
hint: "The cluster is created when the environment starts. Wait a minute, or run `startK3dCluster` in the Terminal."
explanation: "Your single-node k3d cluster is Ready."
-->

## 2. The apps you will open

The workshop has two web UIs. Instead of port-forwards, they are published
through the framework's ingress and listed by one command:

```bash
listApps
```

| App | What it is |
|---|---|
| `kagent` | the kagent UI — chat with the agents, inspect their tools |
| `phoenix` | Arize Phoenix — LLM traces and evaluations |

<!-- LAB_QUESTION
type: multiple-choice
question: "No DEEPSEEK_API_KEY is set in your environment. What do the workshop agents use as their LLM?"
options:
  - "Nothing — the agents are installed but cannot answer"
  - "A small tool-calling model served by Ollama inside your cluster"
  - "The Dynatrace Davis CoPilot"
  - "OpenAI, using a key shipped in the repository"
correct: 1
explanation: "Without a DeepSeek key the platform deploys Ollama with qwen2.5:3b, and the shared workshop-llm ModelConfig points at it — so every agent works unchanged."
-->

<!-- LAB_NO_SOLUTION: the environment is built when it starts; this step only verifies it -->

<div class="grid cards" markdown>
- [3. Platform install :octicons-arrow-right-24:](3-platform-install.md)
</div>
