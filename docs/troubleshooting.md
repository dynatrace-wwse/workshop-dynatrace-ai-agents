# Troubleshooting

A single place for the problems attendees hit most, grouped by module. Each
component also has a deeper README under
[`cluster/`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/tree/main/cluster)
and [`agents/`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/tree/main/agents).

## First, the three catch-all checks

```bash
kubectl get pods -A | grep -vE 'Running|Completed'   # anything not healthy
kubectl get events -A --sort-by=.lastTimestamp | tail -30
bash .devcontainer/bootstrap/check-resources.sh      # CPU/memory headroom
```

!!! tip "Most failures are resources or secrets"
    On a 2-core/4GB Codespace the stack will not fit. Use **4-core / 16 GB** or
    larger (see [`.devcontainer/DECISIONS.md`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/.devcontainer/DECISIONS.md)).
    The second most common cause is a missing/misscoped secret — run
    `bash .devcontainer/bootstrap/check-secrets.sh`.

---

## Module 00 — Setup

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
bash .devcontainer/bootstrap/check-secrets.sh    # prints presence only, never values
```

---

## Module 01 — Platform install

**The install reports warnings but doesn't crash.** That's by design — missing
secrets degrade gracefully (a component is skipped or warns). Re-run after fixing
the secret: `bash cluster/install.sh`.

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
[`otel/operator-values.yaml`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/cluster/otel/operator-values.yaml).
`install.sh` retries the CR for ~60s while the webhook registers.

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
  [`cluster/tetragon/README.md`](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/blob/main/cluster/tetragon/README.md).

**Phoenix not Ready.** It uses one RWO PVC with `strategy: Recreate` — never two
pods on the same volume.

```bash
kubectl -n phoenix get pods
kubectl -n phoenix logs deploy/phoenix
```

---

## Module 02 — Agents & MCP wiring

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
  (the `.apps.dynatrace.com` URL) — **distinct** from the Phase-2 OTLP
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
(`kubectl -n kagent port-forward svc/kagent-ui 8080:8080`).

---

## Module 03 — Secure

**A pod won't schedule into `agent-sandbox`.** That's PSA `restricted` working —
pods must be non-root, drop ALL caps, no privilege escalation, seccomp
`RuntimeDefault`. Add the required `securityContext` (see the examples in
[module 03](03-secure.md)).

**A sandboxed pod can't reach a service.** Expected — the default-deny
NetworkPolicy allows egress only to DNS and the OTel gateway. Add an explicit
egress rule if a workload legitimately needs more.

---

## Module 04 — Observe

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

## Module 05 — Evaluate

**Phoenix UI empty.** Same root cause as "no traces" above — fix the OTel
pipeline, then re-send prompts. Confirm the forward:

```bash
kubectl -n phoenix port-forward svc/phoenix 6006:6006   # then http://localhost:6006
```

**dt-evals can't resolve dependencies.** Run inside `evals/` with `uv`:

```bash
cd evals && uv sync
```

The concrete suite is delivered by Phase 4 — if the config isn't there yet, that
step is expected to be pending.

---

## Still stuck?

- Re-run the idempotent installers — they reconcile, they don't duplicate:
  `bash .devcontainer/postCreate.sh`, `bash cluster/install.sh`,
  `bash agents/install-agents.sh`.
- Tear down and start clean: `bash cluster/uninstall.sh`, then reinstall.
- Open an issue on the
  [workshop repo](https://github.com/henrikrexed/dynatrace-AI-Agent-Workshop/issues).
