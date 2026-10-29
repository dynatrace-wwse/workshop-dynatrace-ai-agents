# dt-evals custom evaluator — diagnosis-01-crashloopbackoff

> Generated from `evals/ground-truth/01-crashloopbackoff.json`
> (answer key: `scenarios/01-crashloopbackoff/expected-diagnosis.md`). Do not hand-edit — run
> `python dt-evals/gen_diagnosis_evaluators.py` after the answer key changes.

Register once (interactive — paste the prompt below when asked):

```bash
npx -y @dynatrace-oss/dt-evals@0.3.4-alpha evaluators add
#   name:           diagnosis-01-crashloopbackoff
#   scale:          binary   (1 = correct, 0 = incorrect)
#   required field: output   (dt-evals maps the gen_ai response span attribute)
```

Then enable it in a run scoped to spans from this scenario's diagnosis:

```bash
DT_EVAL_SERVICE=<sre-agent service.name> \
  ./run-dt-eval.sh --config scenario-diagnosis.dt-eval.yaml --metric diagnosis-01-crashloopbackoff
```

## Judge prompt

You are grading an SRE agent's diagnosis of a Kubernetes incident against an
answer key. Reply with exactly one word: `correct` or `incorrect`.

Answer key — the single correct root cause:
> The billing-worker container's start command exits non-zero immediately (it logs a fatal "BILLING_DB_URL is not set" config error and exit 1), so the kubelet keeps restarting it and backs the pod off into CrashLoopBackOff.

Mark the diagnosis **correct** only if ALL of the following hold:

1. It identifies that root cause (wording may differ).
2. It cites at least 3 of these required signals
   (root cause + evidence channel):
   - reason: CrashLoopBackOff on the pod/container status
   - the event 'Back-off restarting failed container'
   - lastState.terminated.exitCode = 1 / reason: Error / non-zero exit
   - the failing start command / fatal log line from the pod logs
3. It does NOT claim any of these — each is a cross-channel confabulation and
   forces an `incorrect` verdict:
   - image-pull / registry failure (scenario 02)
   - out-of-memory kill (scenario 03)
   - a liveness/readiness probe failure as the root cause
   - a node / scheduling / resource-quota problem

[Agent diagnosis]
{output}
