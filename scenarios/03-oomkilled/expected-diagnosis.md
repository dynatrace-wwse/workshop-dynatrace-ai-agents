---
scenario: 03-oomkilled
fault_family: infra
namespace: workshop-faults
requires: [cluster-state]
pass_threshold: 3
---

# Expected Diagnosis — OOMKilled

## Root cause (one sentence)
The `image-resizer` container tries to allocate far more memory (~250Mi) than its 32Mi memory limit allows, so the kernel OOM-killer terminates it (exit 137) and it restarts into a back-off loop.

## Required signals (grader checks the agent cited ≥ pass_threshold of these)
- `lastState.terminated.reason: OOMKilled` on the container status (`workshop-faults/image-resizer`)
- `lastState.terminated.exitCode: 137` (128 + SIGKILL 9)
- the container memory **limit (32Mi)** vs. the memory the workload demands, i.e. the limit is too low for the workload
- the pod is restarting / `CrashLoopBackOff` *driven by repeated OOM kills* (restart count climbing)

## Acceptable root-cause phrasings (any one satisfies the "root cause" check)
- "the container is OOMKilled because it exceeds its memory limit"
- "memory limit too low for the workload, so the kernel kills it (exit 137)"
- "out-of-memory kill: the process allocates more than the 32Mi limit"

## Must NOT claim (negative signals — catch small-model confabulation)
- a plain application crash / non-zero *application* exit code 1 with no OOM (wrong family → scenario 01)
- an image-pull / registry / `ImagePullBackOff` failure (wrong family → scenario 02)
- a liveness/readiness-probe failure as the root cause
- a node-pressure **eviction** (this is a per-container cgroup OOM kill, reason `OOMKilled`, not a node eviction)

## Expected remediation (optional step — graded only if the attendee remediates)
Raise the container memory limit to fit the workload (or reduce what it allocates) and re-apply/roll out — `k8s_patch_resource` the `resources.limits.memory`, then `k8s_rollout`. Non-destructive operate set only; no delete.
