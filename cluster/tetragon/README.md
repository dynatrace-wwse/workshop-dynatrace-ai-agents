# cluster/tetragon — Tetragon (eBPF runtime security)

Installs Tetragon (`cilium/tetragon`) to observe — and optionally enforce —
process-execution and network behaviour of the agent workloads via eBPF. This is
module 5 of the workshop learning arc (securing agents).

| File | Role |
|------|------|
| `values.yaml` | Helm values for `cilium/tetragon` (DaemonSet + operator, trimmed). |
| `sensitive-file-access.yaml` | `TracingPolicyNamespaced` (observe-only) that posts an event when any process in `agent-sandbox` reads a credential path (service-account token, secrets, `/etc/shadow`, SSH keys, kubeconfig). Applied by hand in module 03. |

## eBPF on k3d (important)

k3d nodes are containers sharing the **Codespace host kernel**. Tetragon
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

For the sensitive-file detection step:

```bash
kubectl apply -f cluster/tetragon/sensitive-file-access.yaml
kubectl -n tetragon exec ds/tetragon -c tetragon -- \
  tetra getevents -o compact --namespace agent-sandbox
```

Then trigger it by reading a credential from a sandbox pod (see module 03 →
*Detect an agent reading sensitive files*).

## Verify

```bash
kubectl -n tetragon get pods    # tetragon DaemonSet + tetragon-operator Ready
```
