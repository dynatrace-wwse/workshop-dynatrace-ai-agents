# Test summary — module-05 eval ground truth (ISI-6850)

Registers each `scenarios/<id>/expected-diagnosis.md` as module-05 diagnosis-grading
ground truth. All tests run **offline** (no judge key, no cluster, no network).

## How to run

```bash
cd evals
python -m pytest tests/ -q            # or: uv run --group dev pytest tests/
python phoenix/run_diagnosis_eval.py  # smoke: grade the bundled golden/confab set
```

## Coverage (`tests/test_ground_truth.py` — 19 tests, all passing)

| Test | Asserts |
|------|---------|
| `test_every_expected_diagnosis_has_a_fixture` | every scenario answer key is registered (and no orphan fixtures). |
| `test_fixture_matches_markdown` (×4) | fixture `scenario`, `pass_threshold`, `fault_family`, `namespace`, and `reference_answer` never drift from the `expected-diagnosis.md` front matter / root-cause line. |
| `test_fixture_is_well_formed` (×4) | `pass_threshold ≥ 1`, enough signals to meet it, non-empty root-cause + negative sets, unique signal ids. |
| `test_sample_dataset_covers_every_scenario` | the Phoenix dataset has a golden **and** a confab per scenario. |
| `test_grader_label_matches_expectation` (×8) | **goldens PASS, confabs FAIL** — the grading check works both ways. |
| `test_contains_digit_boundary` | the matcher does not confuse `exit 1` with `exit 137`, nor `137` with `1370`. |

## Grader smoke (deterministic, `phoenix/run_diagnosis_eval.py`)

```
scenario               label   det   signals  root  verdict
01-crashloopbackoff    golden  1.0   4/3      Y     PASS
01-crashloopbackoff    confab  0.0   0/3      N     FAIL
02-imagepullbackoff    golden  1.0   4/3      Y     PASS
02-imagepullbackoff    confab  0.0   1/3      Y     FAIL
03-oomkilled           golden  1.0   4/3      Y     PASS
03-oomkilled           confab  0.0   1/3      N     FAIL
12-intermittent-5xx    golden  1.0   5/4      Y     PASS
12-intermittent-5xx    confab  0.0   1/4      N     FAIL
4/8 PASS — a clean golden/confab spread.
```

## Not covered here (needs live credentials — out of scope for this PR)

- The optional LLM-as-judge root-cause grader (`--llm-judge`) — needs a judge key.
- `--from-phoenix` live span grading — needs a running Phoenix with diagnosis spans.
- dt-evals custom-evaluator run — needs a Dynatrace tenant + `dt-evals evaluators add`.

These are the same live-credential gates the existing Phase-4 suite already carries.
