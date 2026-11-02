# cluster/tetragon — Tetragon (eBPF runtime security)

Installs Tetragon (`cilium/tetragon`) to observe — and optionally enforce —
process-execution and network behaviour of the agent workloads via eBPF. This is
module 5 of the workshop learning arc (securing agents).

| File | Role |
|------|------|
| `values.yaml` | Helm values for `cilium/tetragon` (DaemonSet + operator, trimmed). |
| `sensitive-file-access.yaml` | `TracingPolicyNamespaced` (observe-only) that posts an event when any process in `agent-sandbox` reads a credential path (service-account token, secrets, `/etc/shadow`, SSH keys, kubeconfig). Applied by hand in module 5. |
| `validate-live.sh` | Reproducible live check: Tetragon + the policy + a loop-snoop pod, asserting the `process_kprobe` event fires and printing the raw `getevents` line. Run it against the workshop cluster when the detection step shows nothing. |

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

Then trigger it from a sandbox pod that reads credentials **in a loop** — so the
read always lands inside the live `getevents` watch window (a one-shot `cat` can
fire before you attach, and `getevents` never replays history):

```bash
kubectl -n agent-sandbox run snoop --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"snoop","image":"busybox:1.36","securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":65534,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}},"command":["sh","-c","while true; do cat /etc/passwd /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1; sleep 2; done"]}]}}' \
  --command -- sh -c 'while true; do cat /etc/passwd /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1; sleep 2; done'

kubectl -n agent-sandbox delete pod snoop --ignore-not-found   # clean up after you see the event
```

`/etc/passwd` is a real path on the container rootfs (no symlink indirection) and
is in the policy's prefix list, so it is guaranteed to match; the service-account
token is the realistic credential-theft target. See module 5 →
*Detect an agent reading sensitive files* for the full walkthrough.

`bash cluster/tetragon/validate-live.sh` exercises this exact flow end-to-end
against the current cluster and asserts the `process_kprobe` event fires.
(Upstream also runs it in a kind-based CI job; not ported — it needs a
privileged eBPF-capable runner.)

## Verify

```bash
kubectl -n tetragon get pods    # tetragon DaemonSet + tetragon-operator Ready
```
