# cluster/

Helm values + manifests for the workshop platform stack, plus the orchestration
to install it. Phase 1 ships the cluster-engine configs; the Phase 2 platform
install fills in the component directories and the install scripts.

## Layout

| Path | What |
|------|------|
| `kind-config.yaml` | Local kind cluster definition (Phase 1). |
| `versions.env` | Pinned chart/image versions — bump here to upgrade the stack. |
| `secrets.sh` | Creates the k8s secrets from Codespace env vars (never committed). |
| `install.sh` | Installs the whole stack, idempotently, in dependency order. |
| `uninstall.sh` | Tears the stack back down (keeps namespaces). |
| `dynatrace/` | Dynatrace Operator (k8smonitoring mode) + DynaKube CR. |
| `otel/` | OpenTelemetry Operator + gateway collector (Dynatrace + Phoenix fan-out) + BindPlane walkthrough. |
| `kagent/` | kagent runtime — clean base, **no** default agents/tools. |
| `tetragon/` | Tetragon eBPF runtime security. |
| `agent-sandbox/` | Agent isolation baseline (PSA restricted + default-deny NetworkPolicy). |
| `phoenix/` | Phoenix (Arize) LLM eval/trace UI. |

## Install

```bash
# Prereqs: a running cluster (.devcontainer/postCreate.sh) and the Codespace
# secrets from .devcontainer/SECRETS.md (DT_TENANT_URL, DT_API_TOKEN, LLM_API_KEY).
bash cluster/install.sh
```

The script is idempotent (`helm upgrade --install` + `kubectl apply`). Missing
secrets degrade gracefully: a component is skipped or warns rather than crashing.
Skip a component with `INSTALL_<NAME>=false`, e.g. `INSTALL_DYNATRACE=false bash cluster/install.sh`.

## Verify (acceptance)

```bash
kubectl get pods -A                                   # all operators/components Ready
kubectl get dynakube -n dynatrace                     # Dynatrace k8s monitoring
kubectl get otelcol -n opentelemetry-operator-system  # gateway collector
kubectl -n phoenix get svc phoenix                    # NodePort 30606 -> http://localhost:6006
```

Telemetry flows once agents run (Phase 3): agent/LLM spans → `otel-gateway-collector`
→ fan-out to the Dynatrace tenant **and** Phoenix.

## Telemetry pipeline

```
 kagent agents / instrumented workloads
      │ OTLP 4317/4318
      ▼
 otel-gateway-collector ──▶ Dynatrace tenant (OTLP ingest)   — observe (cost/tokens/latency)
 (ns opentelemetry-        └▶ Phoenix :4317                   — eval/trace UI
  operator-system)
```

Open questions tracked for later phases: BindPlane live-vs-illustrated (see
`otel/bindplane-illustrated.md`) and the Agent Sandbox upstream project (see
`agent-sandbox/README.md`).
