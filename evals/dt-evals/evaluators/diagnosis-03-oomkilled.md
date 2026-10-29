# dt-evals custom evaluator — diagnosis-03-oomkilled

> Generated from `evals/ground-truth/03-oomkilled.json`
> (answer key: `scenarios/03-oomkilled/expected-diagnosis.md`). Do not hand-edit — run
> `python dt-evals/gen_diagnosis_evaluators.py` after the answer key changes.

Register once (interactive — paste the prompt below when asked):

```bash
npx -y @dynatrace-oss/dt-evals@0.3.4-alpha evaluators add
#   name:           diagnosis-03-oomkilled
#   scale:          binary   (1 = correct, 0 = incorrect)
#   required field: output   (dt-evals maps the gen_ai response span attribute)
```

Then enable it in a run scoped to spans from this scenario's diagnosis:

```bash
DT_EVAL_SERVICE=<sre-agent service.name> \
  ./run-dt-eval.sh --config scenario-diagnosis.dt-eval.yaml --metric diagnosis-03-oomkilled
```

## Judge prompt

You are grading an SRE agent's diagnosis of a Kubernetes incident against an
answer key. Reply with exactly one word: `correct` or `incorrect`.

Answer key — the single correct root cause:
> The image-resizer container tries to allocate far more memory (~250Mi) than its 32Mi memory limit allows, so the kernel OOM-killer terminates it (exit 137) and it restarts into a back-off loop.

Mark the diagnosis **correct** only if ALL of the following hold:

1. It identifies that root cause (wording may differ).
2. It cites at least 3 of these required signals
   (root cause + evidence channel):
   - lastState.terminated.reason: OOMKilled
   - lastState.terminated.exitCode: 137 (128 + SIGKILL)
   - memory limit (32Mi) too low for the workload
   - pod restarting / CrashLoopBackOff driven by repeated OOM kills
3. It does NOT claim any of these — each is a cross-channel confabulation and
   forces an `incorrect` verdict:
   - a plain application crash / app exit code 1 with no OOM (scenario 01)
   - image-pull / registry failure (scenario 02)
   - a liveness/readiness probe failure as the root cause
   - a node-pressure eviction (this is a per-container cgroup OOM, not an eviction)

[Agent diagnosis]
{output}
