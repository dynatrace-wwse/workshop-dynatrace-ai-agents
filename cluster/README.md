# cluster/

Helm values + manifests per platform component. **Phase 2 (ISI-6715)** fills
these in. Phase 1 ships only the cluster engine configs and empty component dirs.

- `k3d-config.yaml` / `kind-config.yaml` — local cluster definitions (Phase 1).
- `dynatrace/` — Dynatrace Operator (k8smonitoring mode).
- `otel/` — OpenTelemetry Operator + collectors.
- `kagent/` — kagent runtime (installed with NO default agents/tools).
- `tetragon/` — Tetragon eBPF runtime security.
- `agent-sandbox/` — agent isolation.
- `phoenix/` — Phoenix (Arize) eval/trace UI.
