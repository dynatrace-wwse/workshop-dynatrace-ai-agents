# 5. Secure agents (Tetragon + Agent Sandbox)

An AI agent is, by design, *given tools and told to act*. That is exactly what
makes it useful — and exactly what makes it risky. A prompt-injected or
mis-behaving agent will happily run whatever tool it can reach. This module adds
two independent layers of defence that were installed in module 3:

- **Agent Sandbox** — *contain* where an agent can go (namespace isolation).
- **Tetragon** — *observe and optionally enforce* what an agent's processes do
  at runtime (eBPF).

!!! info "Defence in depth"
    Neither layer replaces the other. The sandbox is a **static** boundary
    (admission + network policy); Tetragon is a **runtime** sensor that sees the
    actual syscalls/exec/network events — and can kill on policy violation. Use
    both.

---

## Part A — Agent Sandbox (isolation baseline)

The `agent-sandbox` namespace ships a self-contained isolation baseline — no
external project required. It lives in
[`cluster/agent-sandbox/isolation.yaml`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/agent-sandbox/isolation.yaml)
and enforces two things on anything scheduled into it:

| Control | What it does |
|---------|--------------|
| **Pod Security Admission `restricted`** | Pods must run **non-root**, drop **ALL** Linux capabilities, forbid privilege escalation, and use the `RuntimeDefault` seccomp profile. |
| **Default-deny `NetworkPolicy`** | All ingress is blocked; egress is allowed **only** to DNS (port 53) and the OTel gateway (4317/4318) — so a sandboxed agent can still be observed but cannot roam the cluster or call out to the internet. |

### Verify the sandbox

```bash
# PSA labels enforce the "restricted" profile
kubectl get ns agent-sandbox -o jsonpath='{.metadata.labels}'; echo

# the default-deny policy is present
kubectl -n agent-sandbox get networkpolicy
```

You should see `pod-security.kubernetes.io/enforce: restricted` in the labels and
a `default-deny-all` NetworkPolicy.

<!-- LAB_QUESTION
type: shell-verification
question: "Verify the agent-sandbox namespace enforces the restricted baseline"
buttonText: "Check sandbox"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkSandboxRestricted"
expect:
  operator: exit-zero
hint: "Run `installAgentSandbox` in the Terminal, then check again."
explanation: "The namespace carries the PSA restricted label and the default-deny NetworkPolicy."
-->

### Prove it actually blocks

Try to schedule a privileged, root pod into the sandbox — admission must reject
it:

```bash
kubectl -n agent-sandbox run rogue --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"rogue","image":"busybox:1.36","securityContext":{"privileged":true,"runAsUser":0},"command":["sleep","3600"]}]}}' \
  --command -- sleep 3600
```

!!! success "Expected"
    The API server refuses the pod with a `violates PodSecurity "restricted"`
    error (privileged, runAsUser=0, missing seccomp, capabilities not dropped).
    That's admission control doing its job — the rogue workload never starts.

<!-- LAB_QUESTION
type: shell-verification
question: "Prove admission refuses a privileged root pod in the sandbox"
buttonText: "Try the rogue pod"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkSandboxRejectsRogue"
expect:
  operator: exit-zero
hint: "The check submits the rogue pod as a server-side dry run. If it was admitted, the namespace lost its PSA label — run `installAgentSandbox`."
explanation: "The API server answered `violates PodSecurity \"restricted\"` — nothing privileged can start in the sandbox."
-->

Now prove the network boundary from a *compliant* pod:

```bash
# a compliant (non-root, no caps) pod lands, but egress is denied except DNS + OTel
kubectl -n agent-sandbox run probe --image=curlimages/curl:8.10.1 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"probe","image":"curlimages/curl:8.10.1","securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":65534,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}},"command":["sleep","120"]}]}}' \
  --command -- sleep 120

kubectl -n agent-sandbox exec probe -- curl -s -m 5 https://example.com || echo "BLOCKED (expected)"
kubectl -n agent-sandbox delete pod probe rogue --ignore-not-found
```

The external `curl` times out → the default-deny egress policy is working.

!!! note "Stronger isolation later"
    The baseline is PSA + NetworkPolicy, which needs no extra controller. For
    runtime-level isolation (gVisor/Kata-backed pods) you can layer on
    **kagent `substrate`** or **kubernetes-sigs/agent-sandbox** — both are
    *additive* and don't remove this baseline. See
    [`cluster/agent-sandbox/README.md`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/blob/main/cluster/agent-sandbox/README.md).

---

## Part B — Tetragon (eBPF runtime security)

[Tetragon](https://tetragon.io) attaches eBPF programs to the kernel to observe —
and optionally **enforce** — process execution and network behaviour, with
almost no overhead. It was installed as a DaemonSet in module 3
([`cluster/tetragon/`](https://github.com/dynatrace-wwse/workshop-dynatrace-ai-agents/tree/main/cluster/tetragon)).

### Verify Tetragon is running

```bash
kubectl -n tetragon get pods            # tetragon DaemonSet + tetragon-operator Ready
```

<!-- LAB_QUESTION
type: shell-verification
question: "Verify Tetragon is running on your node"
buttonText: "Check Tetragon"
command: "source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkTetragon"
expect:
  operator: exit-zero
hint: "Run `installTetragon`. If the pod crash-loops, see Troubleshooting → Tetragon: eBPF depends on the host kernel."
explanation: "The Tetragon DaemonSet is Ready and is attaching its eBPF programs to the node's kernel."
-->

### Watch what your agents actually do

Stream live process/network events with the `tetra` CLI that ships inside the
DaemonSet pod. Leave this running in one terminal, then send a prompt to the SRE
agent (module 4) in another:

```bash
kubectl -n tetragon exec ds/tetragon -c tetragon -- \
  tetra getevents -o compact
```

You'll see a line for every `process_exec` and network connection across the
node — including the processes the kagent agents spawn when they run a tool. This
is your ground-truth audit log: *what did the agent's container actually execute?*

!!! tip "Filter to the interesting bits"
    `tetra getevents -o compact --pods <pod>` narrows the stream to a single pod.
    Pipe to `grep` for a specific binary (e.g. `grep curl`) to catch an agent
    reaching for the network.

### Optional: enforce, don't just observe

Tetragon can turn an observation into a kill. A `TracingPolicy` can, for example,
`Sigkill` any process in the sandbox that tries to execute an unexpected binary.
This is powerful but **kernel-dependent** on a shared Codespace host — see the
troubleshooting note below before relying on enforcement.

```yaml
# Illustrative — a policy that kills shells spawned inside the sandbox namespace.
apiVersion: cilium.io/v1alpha1
kind: TracingPolicyNamespaced
metadata:
  name: no-shell-in-sandbox
  namespace: agent-sandbox
spec:
  kprobes:
    - call: "sys_execve"
      syscall: true
      args:
        - index: 0
          type: "string"
      selectors:
        - matchArgs:
            - index: 0
              operator: "Postfix"
              values: ["/bin/sh", "/bin/bash"]
          matchActions:
            - action: Sigkill
```

!!! warning "eBPF on a Codespace kernel"
    k3d/kind nodes share the **Codespace host kernel**. Observation
    (`getevents`) works on most hosts; **enforcement** (`Sigkill`) may be
    unavailable on a restricted host kernel. If Tetragon pods CrashLoop, see
    [Troubleshooting → Tetragon](troubleshooting.md#tetragon-not-ready-or-crashlooping).

---

## What you achieved (acceptance)

- The `agent-sandbox` namespace **rejects** privileged/root pods and **blocks**
  egress except DNS + telemetry.
- Tetragon streams **real exec/network events** from your running agents, giving
  you a runtime audit trail (and an optional enforcement hook).

Your agents can now act — but only inside a box you drew, under a sensor that
watches.

<!-- LAB_QUESTION
type: multiple-choice
question: "A prompt-injected agent tries to curl an external URL from a pod in agent-sandbox. Which layer stops it?"
options:
  - "Tetragon, by default — it kills every outbound connection"
  - "The default-deny NetworkPolicy — egress is allowed only to DNS and the OTel gateway"
  - "Pod Security Admission — it blocks network calls"
  - "Nothing — the sandbox only restricts privileges"
correct: 1
explanation: "PSA restricts what a pod may BE (non-root, no caps). The NetworkPolicy restricts where it may GO. Tetragon observes the attempt and can enforce, but only with a TracingPolicy you add."
-->

<!-- LAB_SOLUTION
commands:
  - installAgentSandbox
  - installTetragon
verify:
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkSandboxRestricted
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkSandboxRejectsRogue
  - source .devcontainer/util/source_framework.sh >/dev/null 2>&1 && checkTetragon
reveal: |
  Both layers were installed with the platform; the solution re-applies them
  (idempotent). The rogue-pod check is a server-side dry run, so it proves
  admission without leaving a pod behind.
-->

<div class="grid cards" markdown>
- [6. Observe with Dynatrace :octicons-arrow-right-24:](6-observe.md)
</div>
