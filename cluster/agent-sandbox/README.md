# cluster/agent-sandbox — agent isolation

Isolates agent execution so a (possibly untrusted) agent workload cannot roam the
cluster or network. This is the other half of module 5 (securing agents),
alongside Tetragon.

| File | Role |
|------|------|
| `isolation.yaml` | Namespace with Pod Security Admission **restricted** + a **default-deny** NetworkPolicy (DNS + OTel egress only). |

## What Phase 2 ships

A **self-contained isolation baseline** that needs no external project, so the
acceptance criteria are met today:

- **Pod Security Admission `restricted`** on the `agent-sandbox` namespace — pods
  must run non-root, drop all capabilities, no privilege escalation, seccomp
  `RuntimeDefault`.
- **Default-deny NetworkPolicy** — a sandboxed agent can reach only DNS and the
  OTel gateway (so it stays observable); everything else is blocked.

Verify:

```bash
kubectl get ns agent-sandbox -o jsonpath='{.metadata.labels}' ; echo
kubectl -n agent-sandbox get networkpolicy
```

## Future hardening — which upstream sandbox?

Beyond this baseline, two upstream projects can provide stronger, runtime-level
isolation for Phase 3+:

| Option | Summary | Trade-off |
|--------|---------|-----------|
| **kagent `substrate`** | kagent's built-in worker/sandbox layer (`substrate.enabled`, `substrateWorkerPool`). | Tightest integration with kagent; scope limited to kagent-run code. |
| **kubernetes-sigs/agent-sandbox** | Dedicated CRD + controller for isolated agent sandboxes (gVisor/Kata-backed pods). | More general and Kubernetes-native; extra controller to run. |

A reasonable default is to keep this PSA + NetworkPolicy baseline for Phase 2 and
adopt **kagent `substrate`** in Phase 3, since kagent is already the runtime and
substrate needs no extra controller — unless you want the stronger, runtime-level
isolation of kubernetes-sigs/agent-sandbox (gVisor). Either choice layers on top
of this baseline without removing it.
