# dt-evals custom evaluator — diagnosis-02-imagepullbackoff

> Generated from `evals/ground-truth/02-imagepullbackoff.json`
> (answer key: `scenarios/02-imagepullbackoff/expected-diagnosis.md`). Do not hand-edit — run
> `python dt-evals/gen_diagnosis_evaluators.py` after the answer key changes.

Register once (interactive — paste the prompt below when asked):

```bash
npx -y @dynatrace-oss/dt-evals@0.3.4-alpha evaluators add
#   name:           diagnosis-02-imagepullbackoff
#   scale:          binary   (1 = correct, 0 = incorrect)
#   required field: output   (dt-evals maps the gen_ai response span attribute)
```

Then enable it in a run scoped to spans from this scenario's diagnosis:

```bash
DT_EVAL_SERVICE=<sre-agent service.name> \
  ./run-dt-eval.sh --config scenario-diagnosis.dt-eval.yaml --metric diagnosis-02-imagepullbackoff
```

## Judge prompt

You are grading an SRE agent's diagnosis of a Kubernetes incident against an
answer key. Reply with exactly one word: `correct` or `incorrect`.

Answer key — the single correct root cause:
> The report-renderer container references an image tag that does not exist (busybox:v0-does-not-exist-9q9q9q), so the kubelet cannot pull it and the pod is stuck in ImagePullBackOff.

Mark the diagnosis **correct** only if ALL of the following hold:

1. It identifies that root cause (wording may differ).
2. It cites at least 3 of these required signals
   (root cause + evidence channel):
   - reason: ImagePullBackOff and/or ErrImagePull on the status
   - the event 'Failed to pull image' (manifest not found)
   - the specific bad / non-existent image tag named
   - pod never reaches Running / containers waiting / 0/1 Ready
3. It does NOT claim any of these — each is a cross-channel confabulation and
   forces an `incorrect` verdict:
   - a crash loop of a running process / app exit code (scenario 01)
   - out-of-memory kill (scenario 03)
   - a private-registry auth / ImagePullSecret failure (the image is public; only the tag is missing)
   - a liveness/readiness probe failure

[Agent diagnosis]
{output}
