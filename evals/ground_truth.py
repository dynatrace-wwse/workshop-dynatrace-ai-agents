#!/usr/bin/env python3
"""Module-05 eval ground truth — the scenarios' answer keys, made machine-gradable.

The diagnostic module (module 04) breaks a real Kubernetes fault, the SRE agent
investigates, and its diagnosis is graded against the scenario's **answer key**:
`scenarios/<id>/expected-diagnosis.md` (authored in ISI-6848). This module
*registers* those answer keys as module-05 ground truth (ISI-6850): it loads a
machine-readable fixture per scenario and grades an agent diagnosis against it.

The grading check (exactly what the parent issue asks):

    Did the agent's diagnosis cite the signals the answer key requires
    (root cause + evidence channel), and avoid the cross-channel confabulations
    the key forbids?

Two consumers, one source of truth:

  * Phoenix path  — `phoenix/run_diagnosis_eval.py` uses `grade()` as a
    deterministic evaluator (no judge key needed) and, when a judge key is
    present, an LLM-as-judge root-cause classifier.
  * dt-evals path — `dt-evals/gen_diagnosis_evaluators.py` renders each
    fixture into a dt-evals custom-evaluator rubric + a `factual-accuracy`
    reference answer.

The fixtures (`ground-truth/<id>.json`) are kept honest by `tests/` which assert
they never drift from the `expected-diagnosis.md` front matter / root-cause line.

Pure stdlib — the deterministic grader runs offline with no judge key and no
extra deps, so it is testable in CI.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

HERE = Path(__file__).resolve().parent          # evals/
REPO_ROOT = HERE.parent                          # repo root
FIXTURE_DIR = HERE / "ground-truth"
SCENARIO_DIR = REPO_ROOT / "scenarios"


# --- fixture model -----------------------------------------------------------
def contains(text_lc: str, token: str) -> bool:
    """Case-insensitive substring match, but digit-boundary safe.

    Plain `"exit 1" in "exit 137"` is True — a false positive that would make an
    OOM diagnosis (exit 137) trip the crash-loop grader. Guard tokens against
    adjacent digits so `exit 1` matches `exit 1` / `exit 1.` but never `exit 137`,
    and `137` never matches inside `1370`. Letters stay loose (`image pull`
    still matches `image pulling`) — only numeric collisions are the real hazard.
    """
    tok = token.lower()
    pattern = r"(?<!\d)" + re.escape(tok) + r"(?!\d)"
    return re.search(pattern, text_lc) is not None


@dataclass(frozen=True)
class Signal:
    """One gradeable signal: matched if ANY of its tokens appear in the answer."""
    id: str
    desc: str
    any_of: tuple[str, ...]

    def matched(self, text_lc: str) -> bool:
        return any(contains(text_lc, tok) for tok in self.any_of)


@dataclass(frozen=True)
class Fixture:
    scenario: str
    title: str
    fault_family: str
    namespace: str
    requires: tuple[str, ...]
    pass_threshold: int
    ground_truth_md: str
    reference_answer: str
    required_signals: tuple[Signal, ...]
    root_cause_any_of: tuple[str, ...]
    must_not_claim: tuple[Signal, ...]

    @property
    def md_path(self) -> Path:
        return REPO_ROOT / self.ground_truth_md


@dataclass
class GradeResult:
    scenario: str
    pass_threshold: int
    signals_total: int
    signals_cited: list[str] = field(default_factory=list)
    signals_missed: list[str] = field(default_factory=list)
    root_cause_cited: bool = False
    negatives_hit: list[str] = field(default_factory=list)

    @property
    def signals_pass(self) -> bool:
        return len(self.signals_cited) >= self.pass_threshold

    @property
    def passed(self) -> bool:
        return self.signals_pass and self.root_cause_cited and not self.negatives_hit

    @property
    def score(self) -> float:
        """1.0 if the diagnosis passes, else 0.0 — a binary correctness label."""
        return 1.0 if self.passed else 0.0

    def reason(self) -> str:
        bits = [
            f"signals {len(self.signals_cited)}/{self.pass_threshold} "
            f"(of {self.signals_total})",
            f"root_cause={'yes' if self.root_cause_cited else 'NO'}",
        ]
        if self.negatives_hit:
            bits.append(f"FORBIDDEN={','.join(self.negatives_hit)}")
        return "; ".join(bits)


# --- loading -----------------------------------------------------------------
def _signals(raw: Iterable[dict]) -> tuple[Signal, ...]:
    return tuple(
        Signal(id=s["id"], desc=s.get("desc", ""), any_of=tuple(s["any_of"]))
        for s in raw
    )


def load_fixture(path: Path) -> Fixture:
    d = json.loads(path.read_text())
    return Fixture(
        scenario=d["scenario"],
        title=d["title"],
        fault_family=d["fault_family"],
        namespace=d["namespace"],
        requires=tuple(d.get("requires", [])),
        pass_threshold=int(d["pass_threshold"]),
        ground_truth_md=d["ground_truth_md"],
        reference_answer=d["reference_answer"],
        required_signals=_signals(d["required_signals"]),
        root_cause_any_of=tuple(d["root_cause_any_of"]),
        must_not_claim=_signals(d["must_not_claim"]),
    )


def load_fixtures(directory: Path = FIXTURE_DIR) -> dict[str, Fixture]:
    fixtures = {}
    for p in sorted(directory.glob("*.json")):
        fx = load_fixture(p)
        fixtures[fx.scenario] = fx
    return fixtures


# --- grading -----------------------------------------------------------------
def grade(diagnosis: str, fx: Fixture) -> GradeResult:
    """Grade an agent diagnosis string against a scenario fixture.

    Deterministic, case-insensitive substring matching — the infra scenarios sit
    on *distinct evidence channels* on purpose (see scenarios/README.md), so a
    cross-channel mention is an unambiguous fail. A correct diagnosis stays on
    its own channel, so it never trips a `must_not_claim` token; that is the
    property this grader exploits to stay judge-free.
    """
    text_lc = diagnosis.lower()
    res = GradeResult(
        scenario=fx.scenario,
        pass_threshold=fx.pass_threshold,
        signals_total=len(fx.required_signals),
    )
    for sig in fx.required_signals:
        (res.signals_cited if sig.matched(text_lc) else res.signals_missed).append(sig.id)
    res.root_cause_cited = any(contains(text_lc, tok) for tok in fx.root_cause_any_of)
    res.negatives_hit = [neg.id for neg in fx.must_not_claim if neg.matched(text_lc)]
    return res


# --- parsing the authoritative markdown (drift guard for the tests) ----------
_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def parse_expected_diagnosis(md_path: Path) -> dict:
    """Pull the fields the fixture must agree with from the answer-key markdown.

    Returns {scenario, fault_family, namespace, requires, pass_threshold,
    root_cause}. Minimal front-matter parser (no PyYAML dep): the answer keys
    use flat `key: value` plus one inline `requires: [a, b]` list.
    """
    text = md_path.read_text()
    m = _FRONTMATTER.match(text)
    if not m:
        raise ValueError(f"{md_path}: no YAML front matter")
    fm: dict = {}
    for line in m.group(1).splitlines():
        if not line.strip() or ":" not in line:
            continue
        key, _, val = line.partition(":")
        key, val = key.strip(), val.strip()
        if val.startswith("[") and val.endswith("]"):
            fm[key] = [x.strip() for x in val[1:-1].split(",") if x.strip()]
        elif val.isdigit():
            fm[key] = int(val)
        else:
            fm[key] = val
    body = text[m.end():]
    fm["root_cause"] = _extract_section(body, "Root cause")
    return fm


def _extract_section(body: str, heading_starts_with: str) -> str:
    """Return the first paragraph under the `## <heading...>` section."""
    lines = body.splitlines()
    out: list[str] = []
    capturing = False
    for line in lines:
        if line.startswith("## "):
            if capturing:
                break
            capturing = line[3:].strip().startswith(heading_starts_with)
            continue
        if capturing:
            if line.strip():
                out.append(line.strip())
            elif out:
                break
    return " ".join(out).strip()


def norm(s: str) -> str:
    """Normalise for drift comparison: drop backticks, collapse whitespace."""
    return re.sub(r"\s+", " ", s.replace("`", "")).strip()
