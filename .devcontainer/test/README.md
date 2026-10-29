# Fresh-Codespace validation harness (T0–T9)

`run-tests.sh` is the scripted, repeatable validation for the workshop Codespace,
one explicit pass/fail gate per test (ISI-6744 plan §5). It proves a Codespace built
**only** from the committed `.devcontainer` scripts + the documented Codespace secrets
boots a working environment end-to-end.

```bash
bash .devcontainer/test/run-tests.sh                    # full T0–T9 (auto-detect)
bash .devcontainer/test/run-tests.sh --markdown out.md  # append the results table to out.md
bash .devcontainer/test/run-tests.sh --static           # T0 lint + T1 presence + T2 contract only
bash .devcontainer/test/run-tests.sh --help
```

| Test | Gate |
|------|------|
| T0 | clean build — onCreate/postCreate/postStart exit 0 (all hook scripts also `bash -n` clean) |
| T1 | toolchain on PATH incl. `dtctl` + `dt-evals` |
| T2 | `check-secrets.sh` covers the full §3 matrix, no value leakage (canary test) |
| T3 | cluster up — nodes Ready, 6 namespaces staged |
| T4 | Phase 2 install — operator Running + test signal reaches tenant |
| T5 | Phase 3 agents + MCP — live GitHub read + live Dynatrace query + a kagent answer |
| T6 | `dtctl` authenticates + one read |
| T7 | `dt-evals doctor` OK + one eval written back; Phoenix on 6006 |
| T8 | `mkdocs serve` on 8000 |
| T9 | stop/resume — cluster back via `postStart` |

The harness **auto-detects** Docker/cluster/secret availability and degrades to
`SKIP`/`PARTIAL` with a recorded reason when run outside a real Codespace, so it is
safe to run anywhere. Exit code is non-zero only on a hard `FAIL`. See the latest run
in [`../TEST-RESULTS.md`](../TEST-RESULTS.md).
