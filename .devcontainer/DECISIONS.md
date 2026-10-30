# Environment decisions

Superseded the original kind/Dockerfile design (Henrik Rexed, ISI-6788/6835) when
the workshop moved onto the Dynatrace enablement framework (2026-10-30). The
original reasoning is in git history before that date.

## 1. Cluster engine: **k3d**, via the framework

`startK3dCluster` (framework) creates a single-node k3d cluster with the
framework's ingress-nginx. Every enablement training uses it, and it is what
Orbital provisions in the Enablement App. The kind config, NodePort exposure and
the custom Dockerfile were removed; the framework image
(`shinojosa/dt-enablement`) carries kubectl, helm, k9s, node and python3.

UIs are published with `registerApp` (kagent, phoenix) and listed with
`listApps` — no port-forwards.

## 2. Machine size: **4 vCPU / 16 GB**, measured

Measured 2026-10-30 on a Sysbox slot capped at 4 CPU / 16 GiB (the Orbital
runtime), full run, no Dynatrace tenant:

| Phase | Memory (cgroup) | CPU |
|---|---|---|
| post-create (5 m 54 s) | peak 7.6 GiB | bursts to 4 cores |
| idle, platform + 7 agents | 4.2–4.6 GiB | 0.1–0.3 cores |
| agent answering (Ollama `qwen2.5:3b` loaded) | 7.3 GiB | **4.0 cores**, 1–5 min per answer |
| inner docker data (images + model) | 19.6 GiB disk | |

The Dynatrace Operator (k8s-only DynaKube: operator, webhook, ActiveGate) was
not part of the measurement — budget ~1 GiB more.

## 3. LLM: DeepSeek when a key is present, otherwise Ollama in-cluster

The agents were built for DeepSeek. Nothing in the Enablement App can hand a
learner a third-party LLM key, so when `DEEPSEEK_API_KEY` is absent
`aiwLlmBackend` deploys **Ollama** (`ollama/ollama:0.12.6`, model
`qwen2.5:3b`) and points the shared `workshop-llm` ModelConfig at it.

- `qwen2.5:1.5b` answers in ~20 s but invents pod names (graded FAIL on scenario
  01); `qwen2.5:3b` found the right root cause in 4.5 min. 3b is the default;
  `AIW_OLLAMA_MODEL` overrides.
- `num_thread` is pinned (default 4): Ollama sizes its thread pool from the
  HOST core count, which under Sysbox is the whole worker — measured 1.9 vs 24
  generated tokens/s.
- Ollama 0.40.x was not taken: its amd64 image is twice the size (3.6 GiB
  compressed) and Trivy still reports 50 fixable HIGH (Go stdlib).

## 4. Dynatrace MCP only with a platform token

The stdio Dynatrace MCP server (2.1.2, deprecated upstream) exits without
`DT_ENVIRONMENT` + `DT_PLATFORM_TOKEN`, and kagent fails **every** call of an
agent whose tool server is unreachable. `installAgents` therefore drops the
`dynatrace-tools` block from the SRE agent when the session has no platform
token. In the Enablement App the token is minted per learner
(`.devcontainer/yaml/dt-tokens.yaml`).

## 5. Tetragon under Sysbox

Tetragon needs to create BPF maps, which a Sysbox container (the Orbital
runtime) does not allow (`map create: operation not permitted`). It is installed
and its check passes with a warning when the runtime blocks it; in a Codespace it
runs. Module 5's Agent Sandbox half works everywhere.

## 6. Idempotency

Every `install*` function is `helm upgrade --install` / `kubectl apply` and can
be re-run; every module's *Run solution* calls exactly those functions.
