#!/usr/bin/env python3
"""Render the module-05 ground-truth fixtures into dt-evals custom evaluators.

dt-evals grades live `gen_ai.*` spans, so the scenario answer key has to travel
into the judge as a *rubric prompt* rather than a per-span reference column. This
script turns each `evals/ground-truth/<id>.json` fixture into:

  * `evaluators/diagnosis-<id>.md` — the judge rubric to register with
    `dt-evals evaluators add` (name, scale, required fields + the prompt), and
  * the `reference_answer` block reused by the built-in `factual-accuracy` metric.

Deterministic (no network) — the generated files are committed; re-run after the
answer keys change (the module-05 tests fail if the fixtures drift from the .md).

    python dt-evals/gen_diagnosis_evaluators.py        # regenerate evaluators/
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent               # evals/dt-evals
EVALS = HERE.parent
sys.path.insert(0, str(EVALS))
import ground_truth as gt  # noqa: E402

OUT_DIR = HERE / "evaluators"
PKG = "@dynatrace-oss/dt-evals@0.3.4-alpha"           # matches cluster/versions.env


def rubric(fx: gt.Fixture) -> str:
    name = f"diagnosis-{fx.scenario}"
    signals = "\n".join(f"   - {s.desc}" for s in fx.required_signals)
    negatives = "\n".join(f"   - {n.desc}" for n in fx.must_not_claim)
    return f"""# dt-evals custom evaluator — {name}

> Generated from `evals/ground-truth/{fx.scenario}.json`
> (answer key: `{fx.ground_truth_md}`). Do not hand-edit — run
> `python dt-evals/gen_diagnosis_evaluators.py` after the answer key changes.

Register once (interactive — paste the prompt below when asked):

```bash
npx -y {PKG} evaluators add
#   name:           {name}
#   scale:          binary   (1 = correct, 0 = incorrect)
#   required field: output   (dt-evals maps the gen_ai response span attribute)
```

Then enable it in a run scoped to spans from this scenario's diagnosis:

```bash
DT_EVAL_SERVICE=<sre-agent service.name> \\
  ./run-dt-eval.sh --config scenario-diagnosis.dt-eval.yaml --metric {name}
```

## Judge prompt

You are grading an SRE agent's diagnosis of a Kubernetes incident against an
answer key. Reply with exactly one word: `correct` or `incorrect`.

Answer key — the single correct root cause:
> {fx.reference_answer}

Mark the diagnosis **correct** only if ALL of the following hold:

1. It identifies that root cause (wording may differ).
2. It cites at least {fx.pass_threshold} of these required signals
   (root cause + evidence channel):
{signals}
3. It does NOT claim any of these — each is a cross-channel confabulation and
   forces an `incorrect` verdict:
{negatives}

[Agent diagnosis]
{{output}}
"""


def main() -> None:
    fixtures = gt.load_fixtures()
    OUT_DIR.mkdir(exist_ok=True)
    written = []
    for scenario, fx in sorted(fixtures.items()):
        path = OUT_DIR / f"diagnosis-{scenario}.md"
        path.write_text(rubric(fx))
        written.append(path.name)
    print(f"Wrote {len(written)} evaluator rubrics to {OUT_DIR}/:")
    for n in written:
        print(f"  - {n}")


if __name__ == "__main__":
    main()
