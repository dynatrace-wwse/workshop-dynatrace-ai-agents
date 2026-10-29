# evals/ground-truth — module-05 answer keys (diagnosis grading)

These fixtures **register the scenario answer keys as module-05 eval ground
truth** (ISI-6850). The diagnostic module (04) injects a real Kubernetes fault,
the SRE agent investigates, and its diagnosis is graded against the scenario's
answer key — `scenarios/<id>/expected-diagnosis.md` (authored in ISI-6848). This
closes the **04 → 05 → 06** loop: the diagnosis runs emit `gen_ai.*` spans; the
answer keys become the reference labels that grade them; and the graded runs'
token / cost / latency feed module 06 (optimize).

## The grading check

> Did the agent's diagnosis **cite ≥ `pass_threshold` of the required signals**
> (root cause + evidence channel), **identify the root cause**, and **avoid every
> forbidden cross-channel claim**?

The infra scenarios (01–03) sit on **distinct evidence channels** on purpose
(pod logs vs. events vs. `OOMKilled` status — see `scenarios/README.md`), so a
cross-channel claim is an unambiguous fail. That is what makes the diagnosis
gradeable **objectively, by a small model, or with no model at all**.

## What's here

| File | Role |
|------|------|
| `<id>.json` | Machine-readable fixture: the answer key's `pass_threshold`, required signals (with match tokens), acceptable root-cause phrases, `must_not_claim` negatives, and the root-cause `reference_answer`. |
| `../ground_truth.py` | Loader + the deterministic `grade()` check (pure stdlib — no judge key, no deps). |
| `../tests/` | Drift guard: every answer key has a fixture, and no fixture may drift from its `expected-diagnosis.md` front matter / root-cause line. |

The `.md` answer key stays the single human-readable source of truth; the `.json`
fixture is the eval wiring, and the tests fail if the two disagree.

## Two eval paths consume these fixtures

| Path | How |
|------|-----|
| **Phoenix** | `phoenix/run_diagnosis_eval.py` — deterministic grader as a Phoenix evaluator (offline-capable), plus an optional LLM-as-judge root-cause grader. |
| **dt-evals** | `dt-evals/gen_diagnosis_evaluators.py` renders each fixture into a `dt-evals evaluators add` rubric (`dt-evals/evaluators/diagnosis-<id>.md`) + a `factual-accuracy` reference answer; config `dt-evals/scenario-diagnosis.dt-eval.yaml`. |

## Keeping fixtures in sync with the answer keys

The answer keys are owned by the scenarios (ISI-6848). If one changes:

```bash
cd evals && python -m pytest tests/          # fails if a fixture drifted
python dt-evals/gen_diagnosis_evaluators.py  # regenerate the dt-evals rubrics
```

Update the matching `<id>.json` (`pass_threshold`, `reference_answer`, tokens)
until the tests pass again.

## Note on the deterministic grader

Matching is case-insensitive substring with a digit boundary (so `exit 1` never
matches `exit 137`). A *correct* diagnosis stays on its own evidence channel, so
it never trips a `must_not_claim` token — that is the property the judge-free
grader relies on. A diagnosis that explicitly *rules out* another family in prose
(“this is **not** OOMKilled”) is better graded by the optional LLM judge, which
understands negation; the deterministic grader treats any mention as a hit.
