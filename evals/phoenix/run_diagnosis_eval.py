#!/usr/bin/env python3
"""Phase 4 / module-05 — grade SRE-agent *diagnoses* against the scenario answer keys.

This is the diagnostic-module (module 04) companion to `run_phoenix_eval.py`.
Where that script runs generic hallucination/relevance judges, this one grades
a diagnosis against its scenario's **ground truth** — `scenarios/<id>/expected-
diagnosis.md`, registered as fixtures under `evals/ground-truth/` (ISI-6850).

The grading check (parent issue):

    Did the agent cite >= pass_threshold of the answer key's required signals
    (root cause + evidence channel), and avoid the forbidden cross-channel
    confabulations?

Two evaluators:

  * diagnosis_correctness  — DETERMINISTIC (no judge key, no deps beyond stdlib
    + the sibling `ground_truth.py`). Runs everywhere, including offline against
    the bundled dataset — that alone satisfies the module-05 acceptance.
  * root_cause_grounded    — OPTIONAL LLM-as-judge (same DeepSeek judge as the
    rest of evals/). Only runs when OPENAI_API_KEY is set; checks the diagnosis
    matches an acceptable root-cause phrasing given the answer key as context.

Sources:
  * default         — bundled `data/sample_diagnoses.jsonl` (golden + confab per
    scenario), works offline.
  * --from-phoenix  — pull agent spans from a running Phoenix server, infer which
    scenario each diagnosis belongs to, grade, and log labels back as annotations.

Usage:
    python phoenix/run_diagnosis_eval.py                 # bundled dataset (offline)
    python phoenix/run_diagnosis_eval.py --llm-judge     # + LLM root-cause judge
    uv run python phoenix/run_diagnosis_eval.py --from-phoenix
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # evals/phoenix
EVALS = HERE.parent                              # evals/
sys.path.insert(0, str(EVALS))
import ground_truth as gt  # noqa: E402

DATA = HERE / "data" / "sample_diagnoses.jsonl"
OUT = HERE / "out"

# Needles that tie a live diagnosis span back to a scenario (the faulted
# workload / entity each scenario is built around). Used only by --from-phoenix.
SCENARIO_NEEDLES = {
    "01-crashloopbackoff": ["billing-worker"],
    "02-imagepullbackoff": ["report-renderer"],
    "03-oomkilled": ["image-resizer"],
    "12-intermittent-5xx": ["product-catalog", "productcatalog"],
}


def infer_scenario(text: str, fixtures) -> str | None:
    tl = text.lower()
    for scenario, needles in SCENARIO_NEEDLES.items():
        if scenario in fixtures and any(n in tl for n in needles):
            return scenario
    return None


# --- data sources ------------------------------------------------------------
def load_bundled() -> list[dict]:
    rows = [json.loads(l) for l in DATA.read_text().splitlines() if l.strip()]
    print(f"Loaded {len(rows)} bundled diagnoses from {DATA.name}")
    return rows


def load_from_phoenix(fixtures) -> list[dict]:
    """Pull agent spans from Phoenix and keep the ones we can map to a scenario."""
    from phoenix.client import Client

    endpoint = os.environ.get("PHOENIX_ENDPOINT", "http://localhost:6006")
    project = os.environ.get("PHOENIX_PROJECT", "default")
    client = Client(base_url=endpoint)
    spans = client.spans.get_spans_dataframe(project_identifier=project, limit=500)
    if spans is None or spans.empty:
        sys.exit(f"No spans in Phoenix project '{project}' at {endpoint}. "
                 "Run a scenario diagnosis first (scenarios/run.sh inject <id>).")

    import pandas as pd

    def pick(row, *keys):
        for k in keys:
            if k in row and pd.notna(row[k]) and str(row[k]).strip():
                return str(row[k])
        return ""

    rows = []
    for span_id, row in spans.iterrows():
        out = pick(row, "attributes.output.value", "attributes.gen_ai.completion",
                   "attributes.llm.output_messages")
        inp = pick(row, "attributes.input.value", "attributes.gen_ai.prompt")
        if not out:
            continue
        scenario = infer_scenario(f"{inp}\n{out}", fixtures)
        if not scenario:
            continue  # not a scenario diagnosis span
        rows.append({"scenario": scenario, "label": "live",
                     "input": inp, "context": "", "output": out,
                     "span_id": str(span_id)})
    if not rows:
        sys.exit("Found spans but none mapped to a known scenario "
                 f"({', '.join(SCENARIO_NEEDLES)}). Diagnose a scenario first.")
    print(f"Mapped {len(rows)} diagnosis spans to scenarios from Phoenix.")
    return rows


# --- optional LLM-as-judge root-cause grader ---------------------------------
def llm_root_cause_label(diagnosis: str, fx: gt.Fixture) -> tuple[float | None, str | None]:
    """Judge whether the diagnosis states an acceptable root cause for the answer key."""
    from phoenix.evals import create_classifier, evaluate_dataframe
    from phoenix.evals.llm import LLM
    import pandas as pd

    model = os.environ.get("JUDGE_MODEL", "deepseek-chat")
    if not os.environ.get("OPENAI_BASE_URL"):
        os.environ["OPENAI_BASE_URL"] = "https://api.deepseek.com/v1"
    llm = LLM(provider="openai", model=model)
    classifier = create_classifier(
        name="root_cause_grounded",
        llm=llm,
        prompt_template=(
            "You are grading an SRE agent's incident diagnosis against an answer "
            "key. The single correct root cause is:\n\n[Answer key root cause]\n"
            "{reference}\n\n[Agent diagnosis]\n{output}\n\n"
            "Respond 'correct' if the diagnosis identifies the same root cause as "
            "the answer key (wording may differ), otherwise 'incorrect'."
        ),
        choices={"correct": 1.0, "incorrect": 0.0},
    )
    df = pd.DataFrame([{"reference": fx.reference_answer, "output": diagnosis}])
    res = evaluate_dataframe(dataframe=df, evaluators=[classifier])
    cell = res.iloc[0].get("root_cause_grounded_score")
    if isinstance(cell, dict):
        return cell.get("score"), cell.get("label")
    return None, None


# --- run ---------------------------------------------------------------------
def main() -> None:
    try:
        from dotenv import load_dotenv
        load_dotenv(EVALS / ".env")
    except ModuleNotFoundError:
        pass  # deterministic path needs no .env

    ap = argparse.ArgumentParser(description="Grade SRE diagnoses vs scenario answer keys")
    ap.add_argument("--from-phoenix", action="store_true",
                    help="grade live diagnosis spans from a running Phoenix server")
    ap.add_argument("--llm-judge", action="store_true",
                    help="also run the optional LLM-as-judge root-cause grader (needs OPENAI_API_KEY)")
    args = ap.parse_args()

    fixtures = gt.load_fixtures()
    if not fixtures:
        sys.exit("No ground-truth fixtures found under evals/ground-truth/.")

    rows = load_from_phoenix(fixtures) if args.from_phoenix else load_bundled()
    use_llm = args.llm_judge and bool(os.environ.get("OPENAI_API_KEY"))
    if args.llm_judge and not use_llm:
        print("(--llm-judge ignored: OPENAI_API_KEY not set — deterministic grade only)")

    OUT.mkdir(exist_ok=True)
    results = []
    print(f"\n{'scenario':<22} {'label':<7} {'det':<5} signals  root  verdict")
    print("-" * 78)
    passed = 0
    for r in rows:
        fx = fixtures.get(r["scenario"])
        if fx is None:
            print(f"{r['scenario']:<22} (no fixture — skipped)")
            continue
        g = gt.grade(r["output"], fx)
        rc_label = None
        if use_llm:
            try:
                _, rc_label = llm_root_cause_label(r["output"], fx)
            except Exception as exc:  # noqa: BLE001
                rc_label = f"err:{type(exc).__name__}"
        verdict = "PASS" if g.passed else "FAIL"
        passed += int(g.passed)
        print(f"{r['scenario']:<22} {r.get('label',''):<7} "
              f"{g.score:<5.1f} {len(g.signals_cited)}/{g.pass_threshold:<6} "
              f"{'Y' if g.root_cause_cited else 'N':<5} {verdict}"
              + (f"  llm={rc_label}" if use_llm else ""))
        results.append({
            "scenario": r["scenario"], "label": r.get("label", ""),
            "deterministic_score": g.score, "passed": g.passed,
            "signals_cited": ";".join(g.signals_cited),
            "signals_missed": ";".join(g.signals_missed),
            "signals_count": len(g.signals_cited), "pass_threshold": g.pass_threshold,
            "root_cause_cited": g.root_cause_cited,
            "negatives_hit": ";".join(g.negatives_hit),
            "llm_root_cause": rc_label if use_llm else "",
            "reason": g.reason(),
        })

    csv_path = OUT / "diagnosis_eval_results.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)
    print("-" * 78)
    print(f"{passed}/{len(results)} diagnoses PASS the answer-key grade.")
    print(f"Full results: {csv_path}")

    if args.from_phoenix:
        try:
            log_back_to_phoenix(rows, results)
        except Exception as exc:  # noqa: BLE001
            print(f"(Could not annotate Phoenix spans: {exc}) — CSV above is still valid.")


def log_back_to_phoenix(rows, results) -> None:
    from phoenix.client import Client
    endpoint = os.environ.get("PHOENIX_ENDPOINT", "http://localhost:6006")
    client = Client(base_url=endpoint)
    by_scenario = {(r["scenario"], i): res for i, (r, res) in enumerate(zip(rows, results))}
    annotations = []
    for i, (r, res) in enumerate(zip(rows, results)):
        if not r.get("span_id"):
            continue
        annotations.append({
            "name": "diagnosis_correctness",
            "span_id": r["span_id"],
            "annotator_kind": "CODE",
            "result": {"label": "PASS" if res["passed"] else "FAIL",
                       "score": float(res["deterministic_score"])},
        })
    if annotations:
        client.spans.log_span_annotations(span_annotations=annotations)
        print(f"Logged {len(annotations)} diagnosis_correctness annotations back to Phoenix.")


if __name__ == "__main__":
    main()
