# cluster/tetragon — Tetragon (eBPF runtime security)

Installs Tetragon (`cilium/tetragon`) to observe — and optionally enforce —
process-execution and network behaviour of the agent workloads via eBPF. This is
module 5 of the workshop learning arc (securing agents).

| File | Role |
|------|------|
| `values.yaml` | Helm values for `cilium/tetragon` (DaemonSet + operator, trimmed). |

## eBPF on k3d / kind (important)

k3d/kind nodes are containers sharing the **Codespace host kernel**. Tetragon
loads its BPF programs into that kernel, which needs BTF (`/sys/kernel/btf/vmlinux`)
and permission to attach probes. On most GitHub Codespaces hosts this works.

If the DaemonSet pods CrashLoop or stay `NotReady`:

1. Check the logs: `kubectl -n tetragon logs ds/tetragon -c tetragon`.
2. Confirm host BTF: `ls /sys/kernel/btf/vmlinux` inside a node container.
3. **Fallback:** run Tetragon in process-visibility-only mode (no enforcement) or
   document it as a known Codespace-kernel limitation for the workshop. Enforcement
   (`TracingPolicy` with `Sigkill`) may be unavailable on a restricted host kernel.

## Demo (Phase 3+)

Once an agent runs in `agent-sandbox`, apply a `TracingPolicy` and watch exec/
network events with `kubectl -n tetragon exec ds/tetragon -c tetragon -- tetra getevents -o compact`.

## Verify

```bash
kubectl -n tetragon get pods    # tetragon DaemonSet + tetragon-operator Ready
```
