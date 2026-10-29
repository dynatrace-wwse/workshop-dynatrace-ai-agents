# TEST-RESULTS — Fresh-Codespace validation (T0–T9)

**Issue:** ISI-6788 (T0–T9 harness + run) · **Parent:** ISI-6744 · **Plan:** ISI-6744 §5
**Harness:** [`.devcontainer/test/run-tests.sh`](./test/run-tests.sh) — scripted, repeatable, one gate per test
**Pre-test fixes depended on:** ISI-6787 (F1–F4) — `dtctl` + `dt-evals` install, `check-secrets.sh` full matrix, docs reconcile (merged `done`)
**Last run:** 2026-10-28

---

## How to run (repeatable)

Inside a **fresh Codespace** (rebuilt container, 4-core/16GB/32GB, all §3 secrets set):

```bash
bash .devcontainer/test/run-tests.sh                       # full T0–T9, auto-detect
bash .devcontainer/test/run-tests.sh --markdown out.md     # also append the results table
bash .devcontainer/test/run-tests.sh --static              # T0 lint + T1 presence + T2 contract only (CI/pre-commit)
```

The harness auto-detects capabilities and degrades gracefully:

- no Docker / no cluster → live cluster tests **SKIP** (reason recorded);
- secrets set but tenant offline → live tenant tests report **PARTIAL**;
- static gates (script syntax, secrets-matrix coverage, no-value-leakage canary) **always run**.

Exit code is `0` unless a test hard-**FAIL**s; `SKIP`/`PARTIAL` are the documented offline reality, not failures.

---

## Run environment (this run)

> ⚠️ **This run was NOT executed in a real GitHub Codespace.** It ran in the shared
> local agent workspace (`local_fs`, `/mnt/nas/projects/dynatrace-workshop-aiagents`),
> which is **not** the devcontainer image and has **no Docker-in-Docker, no cluster,
> and none of the real §3 secret values** (board/ops owns those — plan §6/§8). This
> is the *secrets-present-but-offline* partial the issue explicitly allows. It proves
> the harness runs and discriminates; it does **not** substitute for a live Codespace run.

| Fact | Value |
|------|-------|
| Executor | local shared workspace (not a Codespace) |
| Host | 9 vCPU · ~11.4 GiB RAM (not the 4c/16GB Codespace target) |
| Docker-in-Docker | **absent** |
| Cluster | **none** (`k3d`/`kind` not installed) |
| Tools present (coincidental) | `kubectl` v1.36, `helm`, `uv`, `mkdocs` 1.6.1, `dtctl` 0.17.0, `node` v22.23, `npx`, `jq`, `git`, `envsubst` |
| Tools absent | `docker`, `yq`, `k3d`, `kind`, `kagent`, `dt-evals` (→ not the pinned Codespace image) |
| §3 secrets | none set in this env |
| Repo rev | `2704133` (`phase5/optimization-module`) |

---

## Results — T0–T9 (this offline run)

| Test | Gate | Status | Detail |
|------|------|--------|--------|
| T0 | lifecycle hooks exit 0 | PARTIAL | all hook scripts parse (`bash -n`); no full rebuild executed (Docker daemon not available) — needs a fresh Codespace to prove onCreate/postCreate/postStart exit 0 |
| T1 | toolchain on PATH | FAIL* | missing in this env: `docker yq k3d kind kagent dt-evals` (present: `kubectl helm uv mkdocs dtctl`). *FAIL is an artifact of running **outside** the Codespace image; in the built image all 11 are installed by `install-tools.sh` (F1/F2 verified by code review). |
| T2 | check-secrets contract | PARTIAL | **all 15 contract vars covered** + **no value leakage** (canary test passed); required secrets not set in THIS env: `DT_TENANT_URL DT_API_TOKEN DT_PLATFORM_TOKEN DEEPSEEK_API_KEY\|LLM_API_KEY GH_DEMO_REPO` |
| T3 | cluster Ready + namespaces | SKIP | no reachable cluster (requires Docker-in-Docker Codespace + postCreate) |
| T4 | platform install + signal | SKIP | no cluster (see T3); with secrets-but-offline this reports PARTIAL |
| T5 | agents + MCP live calls | SKIP | no cluster (see T3) |
| T6 | dtctl auth + read | PARTIAL | `dtctl` present but `DT_PLATFORM_TOKEN`/`DT_ENVIRONMENT` unset — cannot authenticate |
| T7 | dt-evals doctor + eval | PARTIAL | `doctor=npx-fallback`; Phoenix(6006)=down; dt-evals token/env unset |
| T8 | mkdocs serve :8000 | PARTIAL | serve probe failed (port busy in this host) but **`mkdocs build` succeeds** — site renders |
| T9 | resume via postStart | SKIP | true stop/resume is a Codespaces-platform action; automatable proxy (postStart→cluster back) needs a live cluster |

**Summary (offline run):** PASS=0 · PARTIAL=5 · SKIP=4 · FAIL=1 (T1, explained above).

### What this run *did* positively prove (environment-independent gates)

- ✅ **Every** devcontainer / cluster / agents / evals shell script parses (`bash -n` clean) — T0 static layer.
- ✅ **Secrets contract is complete**: `check-secrets.sh` references all 15 §3 variables (F3 verified).
- ✅ **No secret-value leakage**: canary values injected into every token var were **not** printed by `check-secrets.sh` (T2 (b)).
- ✅ **Workshop site builds**: `mkdocs build` succeeds (T8 fallback).
- ✅ `dtctl` and `dt-evals`/`npx` paths resolve and the harness exercises them.

---

## What a live Codespace run still needs (handoff)

A fully-green T0–T9 requires a **real GitHub Codespace on `main`** plus the real §3
secret **values**, which are owned by the board/ops (plan §6/§8 — out of scope for
agents to provision/rotate). The harness is ready; the gaps are purely environmental:

| Test | Still needs a live run to confirm |
|------|-----------------------------------|
| T0 | Rebuild container; assert onCreate/postCreate/postStart all exit 0 |
| T1 | Confirm all 11 tools present in the **built image** (expected PASS — installed by `install-tools.sh`) |
| T2 | Set the 5 required secrets → expected PASS (coverage + no-leakage already proven) |
| T3 | `postCreate` builds the k3d cluster → nodes Ready + 6 namespaces |
| T4 | `DT_TENANT_URL`/`DT_API_TOKEN` → operator Running **+ a DQL check that the test signal reached the tenant** |
| T5 | `GH_PAT`+`GH_DEMO_REPO`+`DT_PLATFORM_TOKEN`+DeepSeek → one live GitHub read + one live DT query + a kagent answer |
| T6 | `DT_PLATFORM_TOKEN`+`DT_ENVIRONMENT` → `dtctl` authenticates + one read |
| T7 | dt-evals token/env + a discovered `DT_EVAL_SERVICE` → `dt-evals doctor` OK + one eval written back; Phoenix on 6006 |
| T8 | (expected PASS) `mkdocs serve` on forwarded port 8000 |
| T9 | A real Codespace **stop then resume**; `postStart` brings the cluster back |

**Owner of the live run:** DevOps Engineer can execute it once given a Codespace on the
repo + the real secret values (or a scratch Dynatrace tenant). Until those secret values
are available, T4–T7 remain *secrets-present-but-offline* partials by design.

---

## Fixes needed / observations from authoring the harness

- **No code fixes required** against the ISI-6787 (F1–F4) output — `install-tools.sh`,
  `check-secrets.sh`, `postCreate.sh`, `Dockerfile`, and `versions.env` are internally
  consistent and match the §3 contract. The harness found **no defects** in the shipped
  devcontainer; all gates are blocked only by the absence of a live Codespace + secrets.
- **T1 presence gate is strict by design**: any missing tool is a real FAIL in a real
  Codespace. The FAIL here is solely because this run is outside the devcontainer image.
- **T4 "signal reaches tenant"** and **T5 "live GitHub/DT read + kagent answer"** cannot
  be auto-asserted from inside the cluster alone — they require a tenant-side DQL/API
  check. The harness marks them PARTIAL after the install succeeds and records exactly
  what to verify on the tenant to flip them to PASS.
- **T9** can only ever be a PARTIAL from inside the box: a genuine stop/resume is a
  Codespaces-platform action. The harness runs the automatable proxy (`postStart` →
  cluster reachable) and flags the manual step.
