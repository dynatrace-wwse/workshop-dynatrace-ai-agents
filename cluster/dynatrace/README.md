# cluster/dynatrace — Dynatrace Operator (Kubernetes monitoring mode)

Installs the Dynatrace Operator via Helm and a `DynaKube` that monitors the
Codespace cluster in **k8smonitoring mode** — ActiveGate-based, **no** node
OneAgent full-stack (lightest mode, right for a single-node Codespace).

| File | Role |
|------|------|
| `values.yaml` | Helm values for `dynatrace/dynatrace-operator` (trimmed footprint). |
| `dynakube.yaml` | `DynaKube` CR (`dynatrace.com/v1beta6`); `${DT_TENANT_URL}` injected by `install.sh`. |

## Secrets

`secrets.sh` creates `secret/dynakube` in the `dynatrace` namespace from
`DT_API_TOKEN`. **The secret name must equal the DynaKube name** (`dynakube`) —
that is the operator's lookup convention.

Token scopes needed: Kubernetes monitoring / ActiveGate token
(`activeGateTokenManagement`, `entities.read`, `settings.*`) plus the OTLP ingest
scopes used by the OTel collector (`openTelemetryTrace.ingest`,
`metrics.ingest`, `logs.ingest`).

## Verify

```bash
kubectl get dynakube -n dynatrace
kubectl -n dynatrace get pods            # operator, webhook, activegate Ready
```

Cluster topology + metrics then appear under **Kubernetes** in the Dynatrace tenant.
