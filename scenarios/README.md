# scenarios/ — fault-injection for the diagnostic module

This directory holds the **break-it-on-purpose** faults the workshop's SRE agent
diagnoses. The base workshop never breaks on its own (modules 02/04 only send toy
prompts); these scenarios inject a *real*, isolated Kubernetes failure so attendees
watch the **module-02 `sre-agent`** investigate and reach a root cause — the same
agent, now against a genuine incident.

Parent: [ISI-6836](../planning/ISI-6836-diagnostic-module-plan.md) ·
contract: [ISI-6846](../planning/ISI-6846-scenarios-asset-contract.md).

## The diagnosis loop

```
 run.sh inject <id>   ──▶   fault lands in the workshop-faults namespace
          │
          ▼
 paste <id>/prompt.md into the sre-agent (kagent UI or A2A curl)
          │
          ▼
 agent gathers evidence  →  Findings → Root cause → Action → Verify
          │
          ▼
 grade the answer against <id>/expected-diagnosis.md  (objective key)
          │
          ▼
 run.sh cleanup <id>  ──▶   fault removed, zero residue
```

The agent is **unchanged** — it already has read/investigate tools, a minimal
non-destructive operate set, and the Dynatrace MCP (`agents/sre/sre-agent.yaml`).
It has **no `k8s_delete_resource`**; nothing here grants new destructive power.

## Scenarios

| id | fault | evidence channel | app dep |
|----|-------|------------------|---------|
| `01-crashloopbackoff` | start command exits non-zero on launch | **pod logs** + exit code | — |
| `02-imagepullbackoff` | non-existent image tag | **pod events** (`Failed to pull image`) | — |
| `03-oomkilled` | memory limit far below demand | **`lastState.terminated.reason: OOMKilled`** | — |
| `12-intermittent-5xx` | a faulty `product-catalog` backend joins the Service | **Dynatrace problem + Davis root cause** | `otel-demo` |

The three infra scenarios sit on **distinct evidence channels** on purpose — a
cross-channel claim (e.g. "it's OOM" for the crash-loop) is an unambiguous fail, so
a small model (DeepSeek-V3) can be graded objectively. Scenario 12 is the
**Dynatrace-correlation money shot** and is opt-in (see below).

## Usage

```bash
bash scenarios/run.sh list            # enumerate scenarios (id, title, app-dep tag)
bash scenarios/run.sh inject  01      # inject a fault (id = 01 or 01-crashloopbackoff)
kubectl get pods -n workshop-faults -w # watch it break
#   ... paste scenarios/01-crashloopbackoff/prompt.md into the sre-agent ...
bash scenarios/run.sh cleanup 01      # remove the fault
```

Exit codes (downstream grades against these — ISI-6846 §2):

| code | meaning |
|------|---------|
| 0 | success |
| 1 | usage error (bad subcommand, unknown/ambiguous/missing id) |
| 2 | precondition failure (cluster unreachable, namespace-guard violation, missing otel-demo prereq) |
| 3 | runtime failure (kubectl apply/delete or a hook returned non-zero) |

## Safety & isolation (hard rules — ISI-6846 §5)

1. **One blast-radius namespace** for infra faults: `workshop-faults`. Every object
   in an infra `manifests.yaml` pins `namespace: workshop-faults`. `run.sh` creates
   it on inject.
2. **Fail-closed allowlist.** `run.sh` and the optional hooks may touch **only**
   `{workshop-faults, otel-demo}`. Any manifest or hook referencing `kagent`,
   `dynatrace`, the module-03 `agent-sandbox`, `kube-system`, `tetragon`,
   `opentelemetry-operator-system`, or `phoenix` is rejected **before anything is
   applied** (exit 2). This protects the module-03 isolation boundary and the
   platform.
3. **Cleanup is one command, no residue.** Infra: `kubectl delete ns
   workshop-faults`. Scenario 12: remove only the injected faulty backend — the
   `otel-demo` namespace and the healthy demo are never touched (Platform owns them).
4. **No new destructive capability.** Remediation (an optional module step) uses only
   the agent's existing non-destructive operate set (apply/patch/scale/rollout).

## Per-scenario files

- `manifests.yaml` — the fault (infra scenarios), every object pinned to
  `workshop-faults`.
- `expected-diagnosis.md` — the **objective answer key**: front matter +
  `Root cause` + `Required signals` + numeric `pass_threshold` + acceptable
  phrasings + `Must NOT claim`. Doubles as the module-05 eval ground truth
  (ISI-6850).
- `prompt.md` — the exact investigation prompt in two forms (kagent UI paste + A2A
  `curl`), pointed at *the namespace*, never naming the root cause.
- `inject.sh` / `cleanup.sh` — **optional** override hooks (only `12-` uses them):
  run *instead of* the default apply / namespace-delete, bound by the same allowlist.

## Scenario 12 — opt-in app dependency

Scenario 12 drives the lighter OTel Demo fork `opentelemetry-demo-light` and needs
Dynatrace to show the correlation. It is **opt-in** so the base workshop and
scenarios 01–03 fit the 4-core/16 GB Codespace floor:

```bash
INSTALL_OTEL_DEMO=true bash cluster/install.sh     # one-time: deploy the demo app (ISI-6847)
```

If `otel-demo` is not deployed, `run.sh inject 12` fails fast (exit 2) with this
exact command — so a minimum-tier attendee runs 01–03 and is told cleanly why 12 is
unavailable.

> **Mechanism note:** the asset contract (ISI-6846 §4.4) assumed scenario 12 would
> flip a **flagd** feature flag. The selected `opentelemetry-demo-light` fork ships
> **no flagd**, so `12-`'s `inject.sh` instead adds a faulty `product-catalog`
> backend to the Service (same observable: intermittent 5xx correlated in
> Dynatrace). This revised mechanism is pending live validation against the ISI-6847
> deploy.
