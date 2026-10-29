# dt-evals custom evaluator — diagnosis-12-intermittent-5xx

> Generated from `evals/ground-truth/12-intermittent-5xx.json`
> (answer key: `scenarios/12-intermittent-5xx/expected-diagnosis.md`). Do not hand-edit — run
> `python dt-evals/gen_diagnosis_evaluators.py` after the answer key changes.

Register once (interactive — paste the prompt below when asked):

```bash
npx -y @dynatrace-oss/dt-evals@0.3.4-alpha evaluators add
#   name:           diagnosis-12-intermittent-5xx
#   scale:          binary   (1 = correct, 0 = incorrect)
#   required field: output   (dt-evals maps the gen_ai response span attribute)
```

Then enable it in a run scoped to spans from this scenario's diagnosis:

```bash
DT_EVAL_SERVICE=<sre-agent service.name> \
  ./run-dt-eval.sh --config scenario-diagnosis.dt-eval.yaml --metric diagnosis-12-intermittent-5xx
```

## Judge prompt

You are grading an SRE agent's diagnosis of a Kubernetes incident against an
answer key. Reply with exactly one word: `correct` or `incorrect`.

Answer key — the single correct root cause:
> A faulty product-catalog backend has joined the product-catalog Service's endpoints, so a fraction of the frontend's product requests are load-balanced to it and fail — surfacing as intermittent 5xx on the astronomy-shop product/browse path, which Dynatrace raises as a problem with Davis pointing at the product-catalog service.

Mark the diagnosis **correct** only if ALL of the following hold:

1. It identifies that root cause (wording may differ).
2. It cites at least 4 of these required signals
   (root cause + evidence channel):
   - an open Dynatrace problem affecting the frontend / product-catalog path
   - Davis root-cause entity = product-catalog (not the frontend)
   - failures are intermittent / a fraction of requests (not 100%)
   - 5xx / gRPC errors on the frontend -> product-catalog call path
   - product-catalog Service has more than one endpoint and one is unhealthy/faulty
3. It does NOT claim any of these — each is a cross-channel confabulation and
   forces an `incorrect` verdict:
   - the frontend itself is the root cause (Davis attributes it to product-catalog)
   - a total outage / every request failing (signal is intermittent)
   - a CrashLoopBackOff / OOMKilled / ImagePullBackOff of the healthy pod (scenarios 01-03)
   - a database / cart / checkout / payment outage as the primary cause without evidence

[Agent diagnosis]
{output}
