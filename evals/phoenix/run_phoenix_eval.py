#!/usr/bin/env python3
"""Phase 4 — Phoenix eval walkthrough.

Runs two LLM-as-judge evaluators (hallucination + answer relevance) over agent
LLM interactions and prints a scores table. Two sources:

  * default            — a bundled sample dataset (works offline, no cluster)
  * --from-phoenix     — spans pulled from the running Phoenix server; results
                         are logged back as annotations so they show up on the
                         traces in the Phoenix UI.

The judge is the same cost-efficient model that powers the agents: DeepSeek
(`deepseek-chat`, OpenAI-API compatible). Point it elsewhere by changing the
env vars below — nothing in the code is DeepSeek-specific.

    JUDGE_MODEL        default: deepseek-chat
    OPENAI_BASE_URL    default: https://api.deepseek.com/v1   (drop for real OpenAI)
    OPENAI_API_KEY     your judge key  (DeepSeek key works — it's OpenAI-compatible)
    PHOENIX_ENDPOINT   default: http://localhost:6006         (--from-phoenix only)
    PHOENIX_PROJECT    default: default                       (--from-phoenix only)

Usage:
    uv run python phoenix/run_phoenix_eval.py                 # bundled dataset
    uv run python phoenix/run_phoenix_eval.py --from-phoenix  # live Phoenix spans
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
DATA = HERE / "data" / "sample_llm_interactions.jsonl"
OUT = HERE / "out"


# --- judge + evaluators ------------------------------------------------------
def build_evaluators():
    """A hallucination and a relevance classifier, both judged by one LLM."""
    from phoenix.evals import create_classifier
    from phoenix.evals.llm import LLM

    model = os.environ.get("JUDGE_MODEL", "deepseek-chat")
    # provider="openai" uses the OpenAI SDK, which honours OPENAI_BASE_URL /
    # OPENAI_API_KEY — that's how we steer it at DeepSeek with zero code change.
    if not os.environ.get("OPENAI_BASE_URL"):
        os.environ["OPENAI_BASE_URL"] = "https://api.deepseek.com/v1"
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("ERROR: set OPENAI_API_KEY (your DeepSeek/OpenAI judge key).")

    llm = LLM(provider="openai", model=model)

    hallucination = create_classifier(
        name="hallucination",
        llm=llm,
        prompt_template=(
            "You are grading whether an AI answer is grounded in the provided "
            "context. An answer is 'hallucinated' if it states facts that are "
            "not supported by the context.\n\n"
            "[Context]\n{context}\n\n[Question]\n{input}\n\n[Answer]\n{output}\n\n"
            "Respond 'factual' if every claim is supported by the context, "
            "otherwise 'hallucinated'."
        ),
        choices={"factual": 1.0, "hallucinated": 0.0},
    )
    relevance = create_classifier(
        name="relevance",
        llm=llm,
        prompt_template=(
            "You are grading whether an AI answer actually addresses the user's "
            "question.\n\n[Question]\n{input}\n\n[Answer]\n{output}\n\n"
            "Respond 'relevant' if the answer responds to the question, "
            "otherwise 'irrelevant'."
        ),
        choices={"relevant": 1.0, "irrelevant": 0.0},
    )
    return [hallucination, relevance]


# --- data sources ------------------------------------------------------------
def load_bundled() -> pd.DataFrame:
    rows = [json.loads(line) for line in DATA.read_text().splitlines() if line.strip()]
    print(f"Loaded {len(rows)} bundled interactions from {DATA.name}")
    return pd.DataFrame(rows)


def load_from_phoenix() -> pd.DataFrame:
    """Pull LLM spans from the running Phoenix server into the eval frame.

    Maps gen_ai.* / OpenInference span attributes to the input/output/context
    columns our evaluators reference. Keeps span_id so we can annotate back.
    """
    from phoenix.client import Client

    endpoint = os.environ.get("PHOENIX_ENDPOINT", "http://localhost:6006")
    project = os.environ.get("PHOENIX_PROJECT", "default")
    client = Client(base_url=endpoint)
    spans = client.spans.get_spans_dataframe(project_identifier=project, limit=200)
    if spans is None or spans.empty:
        sys.exit(
            f"No spans in Phoenix project '{project}' at {endpoint}. "
            "Generate some agent traffic first, then retry."
        )

    def pick(row, *keys):
        for k in keys:
            if k in row and pd.notna(row[k]) and str(row[k]).strip():
                return row[k]
        return ""

    records = []
    for span_id, row in spans.iterrows():
        inp = pick(row, "attributes.input.value", "attributes.gen_ai.prompt",
                   "attributes.llm.input_messages")
        out = pick(row, "attributes.output.value", "attributes.gen_ai.completion",
                   "attributes.llm.output_messages")
        if not inp and not out:
            continue  # not an LLM/agent span
        records.append({
            "context": pick(row, "attributes.retrieval.documents",
                            "attributes.gen_ai.context") or "(no retrieval context)",
            "input": str(inp),
            "output": str(out),
            "span_id": str(span_id),
        })
    if not records:
        sys.exit("Found spans but none carried LLM input/output attributes.")
    print(f"Pulled {len(records)} LLM spans from Phoenix project '{project}'")
    return pd.DataFrame(records)


def _score_cell(row, metric):
    """evaluate_dataframe stores each score as a dict in '<metric>_score'."""
    cell = row.get(f"{metric}_score")
    if isinstance(cell, dict):
        return cell.get("score"), cell.get("label")
    return None, None


def log_back_to_phoenix(results: pd.DataFrame) -> None:
    """Best-effort: annotate the originating spans so scores show in the UI."""
    from phoenix.client import Client

    endpoint = os.environ.get("PHOENIX_ENDPOINT", "http://localhost:6006")
    client = Client(base_url=endpoint)
    annotations = []
    for _, r in results.iterrows():
        for metric in ("hallucination", "relevance"):
            score, label = _score_cell(r, metric)
            if label is None:
                continue
            annotations.append({
                "name": metric,
                "span_id": r["span_id"],
                "annotator_kind": "LLM",
                "result": {"label": str(label),
                           "score": float(score) if score is not None else None},
            })
    if annotations:
        client.spans.log_span_annotations(span_annotations=annotations)
        print(f"Logged {len(annotations)} annotations back to Phoenix — "
              "open a trace in the UI to see them.")


# --- main --------------------------------------------------------------------
def summarise(results: pd.DataFrame) -> None:
    OUT.mkdir(exist_ok=True)
    csv = OUT / "phoenix_eval_results.csv"
    results.to_csv(csv, index=False)
    print(f"\nFull results written to {csv}")

    print("\n=== Scores ===")
    for metric in ("hallucination", "relevance"):
        col = f"{metric}_score"
        if col not in results:
            continue
        vals = [
            s for s, _ in (_score_cell(r, metric) for _, r in results.iterrows())
            if s is not None
        ]
        if not vals:
            print(f"  {metric:<14} (no scores — check {OUT.name}/ CSV for errors)")
            continue
        avg = sum(vals) / len(vals)
        passed = int(sum(vals))
        print(f"  {metric:<14} avg={avg:0.2f}  ({passed}/{len(vals)} passed)")
    print()


def main() -> None:
    load_dotenv(HERE.parent / ".env")
    ap = argparse.ArgumentParser(description="Phoenix LLM-judge eval walkthrough")
    ap.add_argument("--from-phoenix", action="store_true",
                    help="evaluate live spans from the Phoenix server instead of the bundled dataset")
    args = ap.parse_args()

    from phoenix.evals import evaluate_dataframe

    df = load_from_phoenix() if args.from_phoenix else load_bundled()
    evaluators = build_evaluators()
    print(f"Judging with model={os.environ.get('JUDGE_MODEL', 'deepseek-chat')} "
          f"via {os.environ.get('OPENAI_BASE_URL')}")
    results = evaluate_dataframe(dataframe=df, evaluators=evaluators)
    summarise(results)

    if args.from_phoenix:
        try:
            log_back_to_phoenix(results)
        except Exception as exc:  # noqa: BLE001 - annotation API is version-sensitive
            print(f"(Could not log annotations back to Phoenix: {exc})")
            print("Scores above and the CSV are still valid — this step is cosmetic.")


if __name__ == "__main__":
    main()
