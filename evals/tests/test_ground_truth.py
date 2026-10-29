"""Offline tests for the module-05 eval ground truth (ISI-6850).

No judge key, no cluster, no network — these assert that:

  1. every scenario answer key is registered as a fixture (and vice versa),
  2. fixtures never drift from the authoritative `expected-diagnosis.md`
     (pass_threshold, scenario id, fault family, namespace, root-cause line),
  3. the deterministic grader passes the golden diagnoses and fails the
     confabulated ones in the bundled Phoenix dataset,
  4. the digit-boundary matcher does not confuse `exit 1` with `exit 137`.

Run: `cd evals && python -m pytest tests/ -q`  (or `uv run pytest`).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

EVALS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVALS))

import ground_truth as gt  # noqa: E402

FIXTURES = gt.load_fixtures()
SCENARIO_DIRS = sorted(p for p in gt.SCENARIO_DIR.iterdir() if p.is_dir() and p.name[0].isdigit())
SAMPLE = EVALS / "phoenix" / "data" / "sample_diagnoses.jsonl"


# --- 1. coverage: every answer key is registered -----------------------------
def test_every_expected_diagnosis_has_a_fixture():
    with_key = {p.name for p in SCENARIO_DIRS if (p / "expected-diagnosis.md").exists()}
    registered = set(FIXTURES)
    assert with_key, "no scenarios/*/expected-diagnosis.md found"
    assert with_key == registered, (
        f"ground-truth fixtures out of sync with answer keys: "
        f"unregistered={with_key - registered}, orphan={registered - with_key}"
    )


# --- 2. drift guard: fixture must agree with the markdown --------------------
@pytest.mark.parametrize("scenario", sorted(FIXTURES))
def test_fixture_matches_markdown(scenario):
    fx = FIXTURES[scenario]
    assert fx.md_path.exists(), f"missing answer key {fx.ground_truth_md}"
    fm = gt.parse_expected_diagnosis(fx.md_path)
    assert fm["scenario"] == fx.scenario
    assert fm["pass_threshold"] == fx.pass_threshold, "pass_threshold drifted from the answer key"
    assert fm["fault_family"] == fx.fault_family
    assert fm["namespace"] == fx.namespace
    assert gt.norm(fm["root_cause"]) == gt.norm(fx.reference_answer), (
        "reference_answer drifted from the answer key's 'Root cause' line"
    )


@pytest.mark.parametrize("scenario", sorted(FIXTURES))
def test_fixture_is_well_formed(scenario):
    fx = FIXTURES[scenario]
    assert fx.pass_threshold >= 1
    assert len(fx.required_signals) >= fx.pass_threshold, "cannot cite more signals than exist"
    assert fx.root_cause_any_of, "root_cause_any_of must be non-empty"
    assert fx.must_not_claim, "must_not_claim must be non-empty (negative signals)"
    ids = [s.id for s in fx.required_signals]
    assert len(ids) == len(set(ids)), "duplicate required-signal ids"


# --- 3. grading: goldens pass, confabs fail ----------------------------------
def _rows():
    return [json.loads(l) for l in SAMPLE.read_text().splitlines() if l.strip()]


def test_sample_dataset_covers_every_scenario():
    labels = {(r["scenario"], r["label"]) for r in _rows()}
    for s in FIXTURES:
        assert (s, "golden") in labels, f"no golden sample for {s}"
        assert (s, "confab") in labels, f"no confab sample for {s}"


@pytest.mark.parametrize("row", _rows(), ids=lambda r: f"{r['scenario']}-{r['label']}")
def test_grader_label_matches_expectation(row):
    fx = FIXTURES[row["scenario"]]
    res = gt.grade(row["output"], fx)
    if row["label"] == "golden":
        assert res.passed, f"golden should PASS but failed: {res.reason()}"
        assert len(res.signals_cited) >= fx.pass_threshold
        assert not res.negatives_hit
    else:
        assert not res.passed, f"confab should FAIL but passed: {res.reason()}"


# --- 4. the matcher is digit-boundary safe -----------------------------------
def test_contains_digit_boundary():
    assert gt.contains("the container exited with exit 137", "137")
    assert not gt.contains("the container exited with exit 137", "exit 1")
    assert gt.contains("start command returned exit 1 on launch", "exit 1")
    assert not gt.contains("latency was 1370ms", "137")
    assert gt.contains("status is crashloopbackoff now", "crashloopbackoff")
