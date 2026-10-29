---
scenario: 02-imagepullbackoff
fault_family: infra
namespace: workshop-faults
requires: [cluster-state]
pass_threshold: 3
---

# Expected Diagnosis — ImagePullBackOff

## Root cause (one sentence)
The `report-renderer` container references an image tag that does not exist (`busybox:v0-does-not-exist-9q9q9q`), so the kubelet cannot pull it and the pod is stuck in ImagePullBackOff.

## Required signals (grader checks the agent cited ≥ pass_threshold of these)
- `reason: ImagePullBackOff` (and/or `ErrImagePull`) on the pod / container status (`workshop-faults/report-renderer`)
- the event `Failed to pull image` (with `manifest ... not found` / `not found: manifest unknown`)
- the specific bad image reference named: `busybox:v0-does-not-exist-9q9q9q` (or at least the bad/non-existent tag)
- the pod never reaches Running / containers are `waiting` (0/1 Ready), i.e. no restart loop of a *running* process

## Acceptable root-cause phrasings (any one satisfies the "root cause" check)
- "the image/tag cannot be pulled because it does not exist in the registry"
- "ImagePullBackOff due to a bad/non-existent image tag"
- "the kubelet fails to pull the container image, so the pod can't start"

## Must NOT claim (negative signals — catch small-model confabulation)
- a crash loop of a *running* process / non-zero application exit code (wrong family → scenario 01)
- an out-of-memory / `OOMKilled` kill (wrong family → scenario 03)
- a private-registry **auth**/`ImagePullSecret` failure (the image is public; the *tag* is missing — do not invent credentials as the cause)
- a liveness/readiness-probe failure (the container never starts, so no probe runs)

## Expected remediation (optional step — graded only if the attendee remediates)
Correct the image reference to a tag that exists (e.g. `busybox:1.36`) and re-apply/roll out the Deployment — `k8s_patch_resource` the container `image`, then `k8s_rollout`. Non-destructive operate set only; no delete.
