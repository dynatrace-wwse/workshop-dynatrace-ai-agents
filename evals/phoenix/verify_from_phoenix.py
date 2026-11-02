#!/usr/bin/env python3
"""Live verification of the `--from-phoenix` LLM-span filter (ISI-6966 / ISI-6962).

The offline tests (`tests/test_span_mapping.py`) prove `fetch_llm_spans` *builds*
the right query and falls back correctly, but they never touch a real Phoenix
server. This harness closes that gap end-to-end — no cluster, no Dynatrace, no
judge key required, so it runs on a plain GitHub-hosted runner
(`.github/workflows/phoenix-from-phoenix.yaml`, the CI-as-live pattern from
ISI-6957/ISI-6955):

  1. launch a real Phoenix server in-process,
  2. ingest an otel-demo-style *flood* of infra spans (http/db/rpc/net) plus a
     handful of sparse agent `call_llm` spans — the LLM spans FIRST (oldest) so a
     newest-N pull cannot include them,
  3. assert the OLD behaviour (newest-N of everything) buries the LLM spans →
     maps **zero**, reproducing the ISI-6962 dead-end, and
  4. assert the NEW behaviour (`span_mapping.fetch_llm_spans` → server-side
     `span_kind == 'LLM'`) returns exactly the LLM spans with their
     input/output intact.

This proves the *query* fix is real on a live server. The scoring path (the LLM
judge) is already covered by the bundled dataset, so no judge key is needed here.

Run:  uv run python phoenix/verify_from_phoenix.py   (in a venv with arize-phoenix +
      arize-phoenix-client + the opentelemetry OTLP/http exporter installed)
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import span_mapping  # noqa: E402

N_INFRA = 250   # > the 200 limit, so LLM spans ingested first fall out of the window
N_LLM = 3
EXPECT_IN = "checkout"
EXPECT_OUT = "OOMKilled"


def _ingest(endpoint: str) -> None:
    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

    provider = TracerProvider()
    provider.add_span_processor(
        SimpleSpanProcessor(OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces")))
    tracer = provider.get_tracer("isi6966-verify")

    # LLM spans FIRST (oldest) so a bare newest-200 pull cannot reach them.
    for i in range(N_LLM):
        with tracer.start_as_current_span("call_llm") as s:
            # exactly what the gateway OTTL stamps (ISI-6960)
            s.set_attribute("openinference.span.kind", "LLM")
            s.set_attribute("input.value", f"Why is {EXPECT_IN} failing? (q{i})")
            s.set_attribute("output.value",
                            f"The product-catalog service is {EXPECT_OUT} (a{i})")

    # then the otel-demo microservice flood (newest) — pure infra noise.
    for i in range(N_INFRA):
        with tracer.start_as_current_span(f"GET /api/{i}") as s:
            s.set_attribute("http.method", "GET")
            s.set_attribute("db.system", "postgres")
            s.set_attribute("rpc.service", "frontend")
            s.set_attribute("net.peer.name", "cart")

    provider.force_flush()


def main() -> int:
    import phoenix as px

    session = px.launch_app()
    endpoint = f"http://localhost:{session.port}"
    print(f"Phoenix up at {endpoint}")

    _ingest(endpoint)
    time.sleep(8)  # let Phoenix index the OTLP batch

    from phoenix.client import Client
    client = Client(base_url=endpoint)

    # OLD behaviour — newest-200 of all traffic (what ISI-6962 hit).
    old = client.spans.get_spans_dataframe(project_identifier="default", limit=200)
    old_llm = sum(
        1 for _, r in old.iterrows()
        if span_mapping.extract_input(r) or span_mapping.extract_output(r))
    print(f"[OLD newest-200]     total={len(old):>4}  mapped-LLM={old_llm}")

    # NEW behaviour — server-side span_kind=='LLM' filter.
    new, filtered = span_mapping.fetch_llm_spans(client, "default", limit=200)
    records = []
    for _, r in new.iterrows():
        inp, out = span_mapping.extract_input(r), span_mapping.extract_output(r)
        if inp or out:
            records.append((inp, out))
    print(f"[NEW span_kind==LLM] total={len(new):>4}  mapped-LLM={len(records)}  "
          f"filtered={filtered}")
    for inp, out in records:
        print(f"    in={inp!r}  out={out!r}")

    failures = []
    if old_llm != 0:
        failures.append(f"old newest-200 unexpectedly mapped {old_llm} LLM spans "
                        "(flood too small to reproduce the bury?)")
    if not filtered:
        failures.append("fetch_llm_spans fell back to unfiltered — the server-side "
                        "span_kind=='LLM' filter did not match / errored")
    if len(records) != N_LLM:
        failures.append(f"expected {N_LLM} LLM spans, got {len(records)}")
    if not all(EXPECT_IN in i and EXPECT_OUT in o for i, o in records):
        failures.append("extracted input/output did not carry the expected content")

    if failures:
        print("\nRESULT: FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("\nRESULT: PASS — the server-side filter returns the LLM spans the "
          "newest-N query buried, with input/output intact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
