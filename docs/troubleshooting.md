# Troubleshooting

A single place for the problems attendees hit most, grouped by module. Each
component also has a deeper README under
[`cluster/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/cluster)
and [`agents/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/agents).

## First, the three catch-all checks

```bash
kubectl get pods -A | grep -vE 'Running|Completed'   # anything not healthy
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl top nodes; kubectl top pods -A | sort -k4 -h | tail   # CPU/memory headroom
```

!!! tip "Most failures are resources or secrets"
    On a 2-core/4GB Codespace the stack will not fit. Use **4-core / 16 GB** or
    larger (see [`.devcontainer/DECISIONS.md`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/.devcontainer/DECISIONS.md)).
    The second most common cause is a missing/misscoped credential — run
    `variablesNeeded DT_ENVIRONMENT:true DT_INGEST_TOKEN:true DT_PLATFORM_TOKEN:true` (names only, never values).

---

## Module 2 — Setup

**Cluster not reachable / `kubectl` hangs.** Re-create or restart the cluster:

```bash
bash .devcontainer/postCreate.sh     # full, idempotent bootstrap
bash .devcontainer/postStart.sh      # just restart the cluster after a resume
kubectl cluster-info
```

**Secrets not detected.** Codespace secrets only apply to codespaces created
*after* they're set. Set them, then **rebuild** the container (Command Palette →
*Codespaces: Rebuild Container*), and verify:

```bash
variablesNeeded DT_ENVIRONMENT:true DT_OPERATOR_TOKEN:true DT_INGEST_TOKEN:true DT_PLATFORM_TOKEN:true   # presence only, never values
```

---

## Module 3 — Platform install

**The install reports warnings but doesn't crash.** That's by design — missing
secrets degrade gracefully (a component is skipped or warns). Re-run after fixing
the secret: `installPlatform`.

**Dynatrace: no data on the tenant.** Check `DT_TENANT_URL` / `DT_API_TOKEN` and
token scopes (`openTelemetryTrace.ingest`, `metrics.ingest`, `logs.ingest`, plus
the k8s-monitoring scopes). The DynaKube secret name **must equal** the DynaKube
name (`dynakube`).

```bash
kubectl get dynakube -n dynatrace
kubectl -n dynatrace get pods            # operator, webhook, activegate Ready
```

**OTel operator hangs applying the collector CR.** The operator must use its
self-signed webhook cert (`autoGenerateCert`), already set in
[`otel/operator-values.yaml`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/otel/operator-values.yaml).
`installOtelGateway` retries the CR for ~100 s while the webhook registers.

```bash
kubectl -n opentelemetry-operator-system get otelcol
kubectl -n opentelemetry-operator-system logs deploy/opentelemetry-operator
```

### Tetragon not Ready or CrashLooping

k3d/kind nodes share the **Codespace host kernel**; Tetragon needs BTF and probe
permissions.

```bash
kubectl -n tetragon logs ds/tetragon -c tetragon
kubectl -n tetragon get pods
```

- Confirm host BTF exists: `ls /sys/kernel/btf/vmlinux`.
- **Fallback:** run observation-only (no enforcement). `TracingPolicy` with
  `Sigkill` may be unavailable on a restricted host kernel — document it as a
  known Codespace limitation rather than blocking the workshop. See
  [`cluster/tetragon/README.md`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/tetragon/README.md).

**Phoenix not Ready.** It uses one RWO PVC with `strategy: Recreate` — never two
pods on the same volume.

```bash
kubectl -n phoenix get pods
kubectl -n phoenix logs deploy/phoenix
```

---

## Module 4 — Agents & MCP wiring

**A `RemoteMCPServer` isn't `Accepted` / `discoveredTools` is empty.** The tool
server couldn't start or authenticate. Check the token and the server pod:

```bash
kubectl -n kagent get mcpserver,remotemcpserver
kubectl -n kagent describe remotemcpserver dynatrace-mcp-remote
kubectl -n kagent logs deploy/kagent-controller
```

- `GH_PAT` must be a fine-grained PAT scoped to the demo repo (Contents /
  Issues / Pull requests RW).
- Dynatrace MCP needs the **platform** token (`dt0s16.*`) and `DT_ENVIRONMENT`
  (the `.apps.dynatrace.com` URL) — **distinct** from the module 3 OTLP
  `DT_API_TOKEN`.

**An `Agent` isn't `Accepted`.** Usually a bad `ModelConfig` or missing model
secret.

```bash
kubectl -n kagent get agents
kubectl -n kagent describe agent sre-agent
kubectl -n kagent get secret kagent-deepseek    # model key present?
```

**A2A prompt times out.** Multi-hop BMAD runs take minutes — keep the client
timeout generous (`curl -m 300`). Watch progress in the kagent UI
(the **kagent** app — `listApps`).

---

## Module 5 — Secure

**A pod won't schedule into `agent-sandbox`.** That's PSA `restricted` working —
pods must be non-root, drop ALL caps, no privilege escalation, seccomp
`RuntimeDefault`. Add the required `securityContext` (see the examples in
[module 5](5-secure.md)).

**A sandboxed pod can't reach a service.** Expected — the default-deny
NetworkPolicy allows egress only to DNS and the OTel gateway. Add an explicit
egress rule if a workload legitimately needs more.

---

## Module 6 — Observe

**No agent traces in Dynatrace.** First generate traffic (send a prompt). Then
check the pipeline end to end:

```bash
kubectl -n opentelemetry-operator-system get otelcol
kubectl -n opentelemetry-operator-system logs deploy/otel-gateway-collector | tail -40
```

Confirm kagent `otel.tracing` points at
`otel-gateway-collector.opentelemetry-operator-system.svc:4317`, and that the
tenant/token scopes include `openTelemetryTrace.ingest`.

---

## Module 7 — Diagnose

**`run.sh inject 12` exits 2 with "requires the astroshop-lite app".** Scenario 12 is
the opt-in app scenario. Either skip it (run 01–03) or deploy the demo once with a
single Helm install (the platform stack is already up):
`deployOtelDemoLight`
(`deployOtelDemoLight`). Scenarios
01–03 have no such dependency.

**`unknown/ambiguous scenario id`.** Pass a numeric prefix (`01`, `12`) or the
full dir name (`01-crashloopbackoff`); run `bash scenarios/run.sh list` to see
valid ids.

**The injected pod never appears.** `run.sh` applies into the `workshop-faults`
namespace — watch there, not `default`: `kubectl get pods -n workshop-faults`.
A fail-closed allowlist rejects (exit 2) any manifest referencing a platform
namespace *before* applying, so if inject refused, check the manifest's
`namespace:` is `workshop-faults`.

**The agent cites the wrong failure class** (e.g. "OOMKilled" for the crash
loop). That's a graded *fail*, not a tooling bug — the infra scenarios sit on
distinct evidence channels on purpose. Re-run and, if it persists, confirm the
`sre-agent` has its k8s read tools (`k8s_get_pod_logs`, `k8s_get_events`) from
module 4.

**Cleanup left something behind.** `bash scenarios/run.sh cleanup <id>` is
idempotent; for infra scenarios it deletes the whole `workshop-faults`
namespace. Re-run it, or `kubectl delete ns workshop-faults --ignore-not-found`.

---

## Module 8 — Evaluate

**Phoenix UI empty.** Same root cause as "no traces" above — fix the OTel
pipeline, then re-send prompts. Confirm the forward:

```bash
listApps    # the phoenix URL
```

**dt-evals can't resolve dependencies.** Run inside `evals/` with `uv`:

```bash
cd evals && uv sync
```

The concrete suite ships in module 8 — `evals/dt-evals/workshop-agents.dt-eval.yaml`
plus the Phoenix scripts are on `main`.

---

## Still stuck?

- Re-run the idempotent installers — they reconcile, they don't duplicate:
  `installPlatform`, `installAgents`.
- Tear down and start clean: `deleteCluster && startK3dCluster && installPlatform && installAgents`.
- Open an issue on the
  [workshop repo](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/issues).

<!-- LAB_NO_SOLUTION: reference page — the module pages hold the checks and solutions -->
