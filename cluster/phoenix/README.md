# cluster/phoenix — Phoenix (Arize) LLM eval/trace UI

Deploys Phoenix as a terminal OTLP backend for LLM traces + evaluations. The OTel
gateway fans traces out to it (see `../otel/collector-gateway.yaml`). Attendees
open the UI on the forwarded Codespace port **6006**.

| File | Role |
|------|------|
| `phoenix.yaml` | PVC + Deployment + Service (`arizephoenix/phoenix`, pinned in `../versions.env`). |

## Ports

- **6006** — UI **and** OTLP/HTTP ingest.
- **4317** — OTLP/gRPC ingest (the gateway's `otlp/phoenix` exporter targets this).

## Notes

- **Terminal, not a relay:** fan-out happens at the collector, not by chaining
  through Phoenix.
- **Single writer:** one RWO PVC with `strategy: Recreate` — never two pods
  mounting the same volume.
- Phase 4 (Evaluations) builds the eval walkthrough on top of this; Phase 2 only
  stands the service up and proves it's reachable.

## Verify

```bash
kubectl -n phoenix get pods            # phoenix Ready, /healthz 200
kubectl -n phoenix port-forward svc/phoenix 6006:6006   # then open http://localhost:6006
```
