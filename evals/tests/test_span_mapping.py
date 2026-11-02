"""Offline tests for the Phoenix span-attribute mapper (ISI-6955 / ISI-6951).

No Phoenix, no cluster, no judge key — build a dataframe shaped exactly like
``client.spans.get_spans_dataframe()`` output (attributes flattened into
``attributes.<key>`` columns) and assert that every convention our agents might
emit maps to input/output/context:

  1. OTel GenAI semconv indexed form  (gen_ai.prompt.N.content / completion.N)
  2. OTel GenAI semconv structured form (gen_ai.input.messages / output.messages)
  3. OpenInference form                (input.value / output.value)
  4. GenAI log-events on the span      (events column)
  5. the regression: OTel-only spans used to map to ZERO records

Run: `cd evals && uv run --group dev pytest tests/ -q`.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "phoenix"))
import span_mapping as sm  # noqa: E402


def _row(d: dict) -> pd.Series:
    """One dataframe row as Phoenix yields it in iterrows()."""
    return pd.Series(d)


def test_otel_genai_indexed_form():
    row = _row({
        "attributes.gen_ai.prompt.0.role": "user",
        "attributes.gen_ai.prompt.0.content": "Why is checkout slow?",
        "attributes.gen_ai.completion.0.role": "assistant",
        "attributes.gen_ai.completion.0.content": "The cart service is CPU-bound.",
        "attributes.input.value": float("nan"),   # OpenInference key absent/NaN
        "attributes.output.value": float("nan"),
    })
    assert sm.extract_input(row) == "Why is checkout slow?"
    assert sm.extract_output(row) == "The cart service is CPU-bound."


def test_indexed_form_concatenates_in_numeric_order():
    # 10 must sort after 2, not lexically before it.
    row = _row({
        "attributes.gen_ai.prompt.0.content": "sys",
        "attributes.gen_ai.prompt.2.content": "two",
        "attributes.gen_ai.prompt.10.content": "ten",
    })
    assert sm.extract_input(row) == "sys\ntwo\nten"


def test_otel_genai_structured_messages_form():
    row = _row({
        "attributes.gen_ai.input.messages": [
            {"role": "user", "content": "ping"}],
        "attributes.gen_ai.output.messages": [
            {"role": "assistant", "content": "pong"}],
    })
    assert "ping" in sm.extract_input(row)
    assert "pong" in sm.extract_output(row)


def test_openinference_form_still_works():
    row = _row({
        "attributes.input.value": "hello",
        "attributes.output.value": "world",
        "attributes.retrieval.documents": "doc-1",
    })
    assert sm.extract_input(row) == "hello"
    assert sm.extract_output(row) == "world"
    assert sm.extract_context(row) == "doc-1"


def test_genai_log_events_fallback():
    row = _row({
        "attributes.foo": "not-llm",
        "events": [
            {"name": "gen_ai.user.message", "attributes": {"content": "q"}},
            {"name": "gen_ai.choice", "attributes": {"content": "a"}},
        ],
    })
    assert sm.extract_input(row) == "q"
    assert sm.extract_output(row) == "a"


def test_priority_prefers_openinference_value_over_indexed():
    row = _row({
        "attributes.input.value": "canonical",
        "attributes.gen_ai.prompt.0.content": "indexed",
    })
    assert sm.extract_input(row) == "canonical"


def test_non_llm_span_maps_to_empty():
    row = _row({"attributes.http.method": "GET", "attributes.db.system": "postgres"})
    assert sm.extract_input(row) == ""
    assert sm.extract_output(row) == ""


def test_regression_dataframe_level_otel_spans_now_map():
    """The ISI-6951 symptom: a frame of OTel GenAI spans used to yield 0 records."""
    df = pd.DataFrame([
        {"attributes.gen_ai.prompt.0.content": "Q1",
         "attributes.gen_ai.completion.0.content": "A1"},
        {"attributes.gen_ai.input.messages": [{"role": "user", "content": "Q2"}],
         "attributes.gen_ai.output.messages": [{"role": "assistant", "content": "A2"}]},
        {"attributes.http.method": "GET"},  # non-LLM, correctly skipped
    ])
    mapped = [
        (sm.extract_input(r), sm.extract_output(r))
        for _, r in df.iterrows()
        if sm.extract_input(r) or sm.extract_output(r)
    ]
    assert len(mapped) == 2  # both LLM spans mapped; the HTTP span skipped


def test_attribute_columns_lists_present_keys_for_diagnostics():
    df = pd.DataFrame([{"attributes.gen_ai.system": "deepseek",
                        "attributes.http.method": "GET",
                        "name": "span"}])
    cols = sm.attribute_columns(df)
    assert cols == ["attributes.gen_ai.system", "attributes.http.method"]


# --- fetch_llm_spans: server-side LLM filter + graceful fallback (ISI-6962) ---
import types as _types  # noqa: E402


class _FakeSpans:
    """Stand-in for client.spans — records how get_spans_dataframe was called."""

    def __init__(self, filtered_df, unfiltered_df, raise_on_filter=False):
        self._filtered_df = filtered_df
        self._unfiltered_df = unfiltered_df
        self._raise_on_filter = raise_on_filter
        self.calls = []

    def get_spans_dataframe(self, *, project_identifier, limit, query=None):
        self.calls.append({"query": query, "limit": limit})
        if query is not None:
            if self._raise_on_filter:
                raise RuntimeError("filter DSL unsupported in this version")
            return self._filtered_df
        return self._unfiltered_df


class _FakeClient:
    def __init__(self, spans):
        self.spans = spans


@pytest.fixture
def fake_spanquery(monkeypatch):
    """Inject a phoenix.client.types.spans.SpanQuery so the filtered path runs
    without the real phoenix-client installed. Returns a list that captures the
    .where() conditions so a test can assert the exact DSL used."""
    captured = []

    class _SpanQuery:
        def where(self, condition):
            captured.append(condition)
            return self

    mod = _types.ModuleType("phoenix.client.types.spans")
    mod.SpanQuery = _SpanQuery
    monkeypatch.setitem(sys.modules, "phoenix", _types.ModuleType("phoenix"))
    monkeypatch.setitem(sys.modules, "phoenix.client", _types.ModuleType("phoenix.client"))
    monkeypatch.setitem(sys.modules, "phoenix.client.types",
                        _types.ModuleType("phoenix.client.types"))
    monkeypatch.setitem(sys.modules, "phoenix.client.types.spans", mod)
    return captured


def test_fetch_llm_spans_filters_server_side(fake_spanquery):
    df = pd.DataFrame([{"attributes.input.value": "q", "attributes.output.value": "a"}])
    spans = _FakeSpans(filtered_df=df, unfiltered_df=pd.DataFrame())
    out, filtered = sm.fetch_llm_spans(_FakeClient(spans), "default", limit=200)

    assert filtered is True
    assert len(out) == 1
    # The exact DSL went through SpanQuery().where(...) once.
    assert fake_spanquery == [sm.LLM_SPAN_FILTER] == ["span_kind == 'LLM'"]
    # Only the filtered query ran — no wasteful second (unfiltered) pull.
    assert len(spans.calls) == 1
    assert spans.calls[0]["query"] is not None
    assert spans.calls[0]["limit"] == 200


def test_fetch_llm_spans_falls_back_when_filter_empty(fake_spanquery):
    all_traffic = pd.DataFrame([{"attributes.http.method": "GET"}])
    spans = _FakeSpans(filtered_df=pd.DataFrame(), unfiltered_df=all_traffic)
    out, filtered = sm.fetch_llm_spans(_FakeClient(spans), "default", limit=200)

    assert filtered is False          # caller warns the result is unfiltered
    assert len(out) == 1
    assert [c["query"] is None for c in spans.calls] == [False, True]  # tried filter, then fell back


def test_fetch_llm_spans_falls_back_when_filter_errors(fake_spanquery):
    all_traffic = pd.DataFrame([{"attributes.http.method": "GET"}])
    spans = _FakeSpans(filtered_df=pd.DataFrame(), unfiltered_df=all_traffic,
                       raise_on_filter=True)
    out, filtered = sm.fetch_llm_spans(_FakeClient(spans), "default", limit=500)

    assert filtered is False
    assert len(out) == 1
    assert spans.calls[-1]["query"] is None  # unfiltered fallback still ran


def test_fetch_llm_spans_falls_back_without_phoenix_client():
    """No phoenix-client importable (the real offline env) → unfiltered pull."""
    all_traffic = pd.DataFrame([{"attributes.gen_ai.prompt.0.content": "Q"}])
    spans = _FakeSpans(filtered_df=pd.DataFrame(), unfiltered_df=all_traffic)
    # phoenix.client.types.spans is NOT injected here → import raises → fallback.
    out, filtered = sm.fetch_llm_spans(_FakeClient(spans), "default", limit=200)

    assert filtered is False
    assert len(out) == 1
    assert spans.calls == [{"query": None, "limit": 200}]  # went straight to unfiltered


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
