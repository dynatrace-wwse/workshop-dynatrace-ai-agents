---
scenario: 01-crashloopbackoff
fault_family: infra
namespace: workshop-faults
requires: [cluster-state]
pass_threshold: 3
---

# Expected Diagnosis — CrashLoopBackOff

## Root cause (one sentence)
The `billing-worker` container's start command exits non-zero immediately (it logs a fatal "BILLING_DB_URL is not set" config error and `exit 1`), so the kubelet keeps restarting it and backs the pod off into CrashLoopBackOff.

## Required signals (grader checks the agent cited ≥ pass_threshold of these)
- `reason: CrashLoopBackOff` on the pod / container status (`workshop-faults/billing-worker`)
- the event `Back-off restarting failed container`
- `lastState.terminated.exitCode` = 1 (equivalently `reason: Error`), i.e. a non-zero exit
- the failing start command / fatal log line quoted from the pod logs (e.g. `BILLING_DB_URL is not set` / `config load failed, exiting`)

## Acceptable root-cause phrasings (any one satisfies the "root cause" check)
- "the container crash-loops because its start command fails immediately"
- "the process exits with a non-zero code on startup, so it is restarted repeatedly"
- "a startup/config error (missing BILLING_DB_URL) makes the entrypoint exit 1"

## Must NOT claim (negative signals — catch small-model confabulation)
- an image-pull / registry / `ErrImagePull` / `ImagePullBackOff` failure (wrong family → scenario 02)
- an out-of-memory / `OOMKilled` kill (wrong family → scenario 03)
- a liveness/readiness-probe failure as the *root* cause (there is no probe here; the process exits on its own)
- a node, scheduling, or resource-quota problem

## Expected remediation (optional step — graded only if the attendee remediates)
Supply the missing configuration (or correct the start command) and re-apply/roll out the Deployment so the entrypoint exits 0 — e.g. `k8s_patch_resource` the container `args` to a valid long-running command, or set the `BILLING_DB_URL` env, then `k8s_rollout` restart. Stays inside the SRE agent's non-destructive operate set (patch/apply/rollout); no delete.
