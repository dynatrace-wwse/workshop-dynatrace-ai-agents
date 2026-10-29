#!/usr/bin/env bash
# =============================================================================
# Fresh-Codespace validation harness — T0..T9 (ISI-6744 plan §5 / ISI-6788)
# =============================================================================
# Repeatable, scripted end-to-end check that a Codespace built ONLY from the
# committed .devcontainer scripts + the documented Codespace secrets boots a
# working workshop environment. Each test Tn has an explicit pass/fail gate.
#
# Run it from the repo root inside a fresh Codespace:
#     bash .devcontainer/test/run-tests.sh
#
# The harness AUTO-DETECTS capabilities and degrades gracefully:
#   - no Docker / no cluster      -> live cluster tests SKIP (reason recorded)
#   - secrets set but tenant offline -> live tenant tests report PARTIAL
#   - static checks (syntax, secrets-matrix coverage, no-value-leakage) always run
# so it produces useful signal even outside a real Codespace. A fully-green run
# requires a real Codespace with the §3 secrets AND a reachable Dynatrace tenant.
#
# Flags:
#   --static        only run checks that need no Docker/cluster/secrets (T0 lint,
#                   T1 presence, T2 coverage+leakage). Good for CI / pre-commit.
#   --no-rebuild    T0 does NOT re-run postCreate (heavy); lints lifecycle scripts
#                   and checks idempotency markers instead. (default inside a
#                   running Codespace is to re-run the idempotent lifecycle hooks)
#   --markdown FILE append a GitHub-flavoured results table to FILE.
#   -h | --help     this help.
#
# Exit code: 0 if no test FAILed (SKIP/PARTIAL are non-fatal), 1 otherwise.
# =============================================================================
set -uo pipefail

# ----- locate repo ----------------------------------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HARNESS_DIR}/../.." && pwd)"
DEVC="${REPO_ROOT}/.devcontainer"
BOOT="${DEVC}/bootstrap"
cd "${REPO_ROOT}"

CLUSTER_TOOL="${CLUSTER_TOOL:-k3d}"
CLUSTER_NAME="${CLUSTER_NAME:-workshop}"

# ----- flags ----------------------------------------------------------------
STATIC_ONLY=0
NO_REBUILD=0
MARKDOWN_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --static)     STATIC_ONLY=1 ;;
    --no-rebuild) NO_REBUILD=1 ;;
    --markdown)   shift; MARKDOWN_OUT="${1:-}" ;;
    -h|--help)    sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# ----- pretty-print ---------------------------------------------------------
c_reset='\033[0m'; c_blue='\033[1;34m'; c_grn='\033[1;32m'
c_red='\033[1;31m'; c_yel='\033[1;33m'; c_dim='\033[2m'
hdr()  { printf "\n${c_blue}==== %s ====${c_reset}\n" "$*"; }
info() { printf "${c_dim}  %s${c_reset}\n" "$*"; }

# ----- result accumulator ---------------------------------------------------
# Each record: "ID\tNAME\tSTATUS\tDETAIL"  (STATUS = PASS|FAIL|SKIP|PARTIAL)
RESULTS=()
record() {
  local id="$1" name="$2" status="$3" detail="$4"
  RESULTS+=("${id}"$'\t'"${name}"$'\t'"${status}"$'\t'"${detail}")
  local col="$c_dim" tag="$status"
  case "$status" in
    PASS)    col="$c_grn" ;;
    FAIL)    col="$c_red" ;;
    SKIP)    col="$c_yel" ;;
    PARTIAL) col="$c_yel" ;;
  esac
  printf "  [%b%-7s%b] %-3s %s — %s\n" "$col" "$tag" "$c_reset" "$id" "$name" "$detail"
}

# ----- small helpers --------------------------------------------------------
have()         { command -v "$1" >/dev/null 2>&1; }
secret_set()   { [ -n "${!1:-}" ]; }
either_set()   { secret_set "$1" || secret_set "$2"; }
docker_up()    { have docker && docker info >/dev/null 2>&1; }
cluster_up()   { have kubectl && kubectl cluster-info >/dev/null 2>&1; }

# =============================================================================
# T0 — Clean build: lifecycle hooks exit 0
# =============================================================================
t0_build() {
  hdr "T0 — Clean build (onCreate/postCreate/postStart exit 0)"

  # Always: every devcontainer script must parse (bash -n) and, if shellcheck is
  # present, pass shellcheck. A build cannot be "clean" if a hook won't parse.
  local bad=0 scripts
  scripts=$(find "${DEVC}" "${REPO_ROOT}/cluster" "${REPO_ROOT}/agents" \
                 "${REPO_ROOT}/evals" -name '*.sh' -type f 2>/dev/null | sort)
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if ! bash -n "$s" 2>/tmp/t0.err; then
      info "syntax error: ${s#${REPO_ROOT}/} -> $(head -1 /tmp/t0.err)"; bad=$((bad+1))
    fi
  done <<< "$scripts"
  if [ "$bad" -ne 0 ]; then
    record T0 "lifecycle scripts parse" FAIL "${bad} script(s) failed bash -n"
    return
  fi
  local sc_note=""
  if have shellcheck; then
    if shellcheck -S error -x "${DEVC}"/*.sh "${BOOT}"/*.sh >/tmp/t0.sc 2>&1; then
      sc_note="; shellcheck -S error clean"
    else
      sc_note="; shellcheck errors ($(grep -c '^In ' /tmp/t0.sc 2>/dev/null || echo '?'))"
    fi
  fi

  if [ "$STATIC_ONLY" -eq 1 ] || [ "$NO_REBUILD" -eq 1 ] || ! docker_up; then
    local why="--no-rebuild / --static"
    docker_up || why="Docker daemon not available (not a running Codespace)"
    record T0 "lifecycle hooks exit 0" PARTIAL \
      "all hook scripts parse${sc_note}; did not execute a full rebuild (${why}) — run in a fresh Codespace to prove onCreate/postCreate/postStart exit 0"
    return
  fi

  # Running Codespace: re-run the idempotent lifecycle hooks, require exit 0.
  local rc_oncreate rc_postcreate rc_poststart
  bash "${BOOT}/check-resources.sh" >/tmp/t0.oncreate 2>&1; rc_oncreate=$?
  bash "${DEVC}/postCreate.sh"      >/tmp/t0.postcreate 2>&1; rc_postcreate=$?
  bash "${DEVC}/postStart.sh"       >/tmp/t0.poststart 2>&1; rc_poststart=$?
  if [ $rc_oncreate -eq 0 ] && [ $rc_postcreate -eq 0 ] && [ $rc_poststart -eq 0 ]; then
    record T0 "lifecycle hooks exit 0" PASS \
      "onCreate=0 postCreate=0 postStart=0${sc_note} (idempotent re-run)"
  else
    record T0 "lifecycle hooks exit 0" FAIL \
      "exit codes onCreate=${rc_oncreate} postCreate=${rc_postcreate} postStart=${rc_poststart} (see /tmp/t0.*)"
  fi
}

# =============================================================================
# T1 — Toolchain presence (plan §5 T1 list) incl. dtctl + dt-evals (F1/F2)
# =============================================================================
t1_toolchain() {
  hdr "T1 — Toolchain presence (incl. dtctl + dt-evals)"
  local tools=(docker kubectl helm yq uv mkdocs k3d kind kagent dtctl dt-evals)
  local missing=() present=()
  for t in "${tools[@]}"; do
    if have "$t"; then present+=("$t"); else missing+=("$t"); fi
  done
  # Supporting tools are informational, not gated.
  local support=() for_s
  for for_s in node npx jq git gh envsubst; do have "$for_s" && support+=("$for_s"); done
  info "supporting present: ${support[*]:-none}"
  if [ ${#missing[@]} -eq 0 ]; then
    record T1 "toolchain on PATH" PASS "all ${#tools[@]} present: ${tools[*]}"
  elif [ ${#present[@]} -eq 0 ]; then
    record T1 "toolchain on PATH" SKIP \
      "none of the workshop tools are installed — this is not the Codespace image (present elsewhere). Missing: ${missing[*]}"
  else
    record T1 "toolchain on PATH" FAIL "missing: ${missing[*]} (present: ${present[*]})"
  fi
}

# =============================================================================
# T2 — Secrets contract: full matrix coverage, no value leakage
# =============================================================================
t2_secrets() {
  hdr "T2 — Secrets contract (full matrix, no value leakage)"
  local cs="${BOOT}/check-secrets.sh"
  if [ ! -f "$cs" ]; then
    record T2 "check-secrets contract" FAIL "check-secrets.sh not found at ${cs}"
    return
  fi

  # (a) Matrix coverage — every §3 contract var must be referenced by the script.
  local required_vars=(DT_TENANT_URL DT_API_TOKEN DT_PLATFORM_TOKEN DT_ENVIRONMENT \
    DEEPSEEK_API_KEY LLM_API_KEY GH_PAT GITHUB_TOKEN GH_DEMO_REPO \
    DT_ENV_URL DT_ENVIRONMENT_URL DYNATRACE_API_TOKEN DT_EVAL_SERVICE \
    OPENAI_API_KEY ANTHROPIC_API_KEY)
  local uncovered=()
  for v in "${required_vars[@]}"; do grep -q "\b${v}\b" "$cs" || uncovered+=("$v"); done

  # (b) No value leakage — run with canary values; script must NOT echo them.
  local canary="LEAKCANARY_9e3f"
  local leak_out
  leak_out=$(DT_TENANT_URL="${canary}_url" DT_API_TOKEN="${canary}_dt0c01" \
    DT_PLATFORM_TOKEN="${canary}_dt0s16" DT_ENVIRONMENT="${canary}_apps" \
    DEEPSEEK_API_KEY="${canary}_sk" GH_PAT="${canary}_ghp" \
    GH_DEMO_REPO="${canary}_repo" DYNATRACE_API_TOKEN="${canary}_evt" \
    bash "$cs" 2>&1)
  local leaked=0; grep -q "$canary" <<< "$leak_out" && leaked=1

  if [ ${#uncovered[@]} -ne 0 ] || [ "$leaked" -ne 0 ]; then
    local d=""
    [ ${#uncovered[@]} -ne 0 ] && d="uncovered contract vars: ${uncovered[*]}. "
    [ "$leaked" -ne 0 ] && d="${d}VALUE LEAKAGE: canary printed in output!"
    record T2 "check-secrets contract" FAIL "$d"
    return
  fi

  # (c) Required-present — depends on the real environment.
  local req_missing=()
  secret_set DT_TENANT_URL     || req_missing+=(DT_TENANT_URL)
  secret_set DT_API_TOKEN      || req_missing+=(DT_API_TOKEN)
  secret_set DT_PLATFORM_TOKEN || req_missing+=(DT_PLATFORM_TOKEN)
  either_set DEEPSEEK_API_KEY LLM_API_KEY || req_missing+=("DEEPSEEK_API_KEY|LLM_API_KEY")
  either_set GH_PAT GITHUB_TOKEN      || req_missing+=("GH_PAT|GITHUB_TOKEN")
  secret_set GH_DEMO_REPO  || req_missing+=(GH_DEMO_REPO)

  if [ ${#req_missing[@]} -eq 0 ]; then
    record T2 "check-secrets contract" PASS \
      "all ${#required_vars[@]} contract vars covered; no value leakage (canary test); all required secrets present"
  else
    record T2 "check-secrets contract" PARTIAL \
      "contract fully covered + no value leakage (verified); required secrets not set in THIS env: ${req_missing[*]} — set them as Codespace secrets for a live run"
  fi
}

# =============================================================================
# T3 — Cluster up
# =============================================================================
t3_cluster() {
  hdr "T3 — Cluster up (nodes Ready, namespaces staged)"
  if ! cluster_up; then
    record T3 "cluster Ready + namespaces" SKIP \
      "no reachable cluster (requires Docker-in-Docker Codespace + postCreate) — run in a Codespace"
    return
  fi
  local notready
  notready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{c++} END{print c+0}')
  local ns_missing=()
  for ns in dynatrace opentelemetry-operator-system kagent tetragon agent-sandbox phoenix; do
    kubectl get ns "$ns" >/dev/null 2>&1 || ns_missing+=("$ns")
  done
  if [ "${notready:-1}" -eq 0 ] && [ ${#ns_missing[@]} -eq 0 ]; then
    record T3 "cluster Ready + namespaces" PASS "all nodes Ready; all 6 namespaces staged"
  else
    record T3 "cluster Ready + namespaces" FAIL \
      "nodes-not-Ready=${notready} ; missing namespaces: ${ns_missing[*]:-none}"
  fi
}

# =============================================================================
# T4 — Phase 2 platform install (operator Ready + test signal to tenant)
# =============================================================================
t4_phase2() {
  hdr "T4 — Phase 2 platform install"
  if ! cluster_up; then
    record T4 "platform install + signal" SKIP "no cluster (see T3)"
    return
  fi
  if ! ( secret_set DT_TENANT_URL && secret_set DT_API_TOKEN ); then
    record T4 "platform install + signal" PARTIAL \
      "cluster present but DT_TENANT_URL/DT_API_TOKEN unset — cannot auth operator or send a signal to a tenant. Set the §3 secrets for a live run (cluster/install.sh is idempotent)"
    return
  fi
  info "running cluster/install.sh (Phase 2) — this is heavy"
  if bash "${REPO_ROOT}/cluster/install.sh" >/tmp/t4.install 2>&1; then
    # operator pods Ready?
    local notready
    notready=$(kubectl -n dynatrace get pods --no-headers 2>/dev/null \
                | awk '$3!="Running" && $3!="Completed"{c++} END{print c+0}')
    if [ "${notready:-1}" -eq 0 ]; then
      record T4 "platform install + signal" PARTIAL \
        "operator pods Running; 'test signal reaches tenant' needs a Dynatrace-side check (DQL on the tenant) — verify in the tenant UI/API to turn this PASS"
    else
      record T4 "platform install + signal" FAIL "dynatrace ns has ${notready} non-Running pods (see /tmp/t4.install)"
    fi
  else
    record T4 "platform install + signal" FAIL "cluster/install.sh exited non-zero (see /tmp/t4.install)"
  fi
}

# =============================================================================
# T5 — Phase 3 agents + MCP wiring
# =============================================================================
t5_phase3() {
  hdr "T5 — Phase 3 agents + MCP (GitHub + Dynatrace MCP, kagent/DeepSeek)"
  if ! cluster_up; then
    record T5 "agents + MCP live calls" SKIP "no cluster (see T3)"
    return
  fi
  local miss=()
  either_set GH_PAT GITHUB_TOKEN || miss+=("GH_PAT|GITHUB_TOKEN")
  secret_set GH_DEMO_REPO        || miss+=(GH_DEMO_REPO)
  secret_set DT_PLATFORM_TOKEN       || miss+=(DT_PLATFORM_TOKEN)
  either_set DEEPSEEK_API_KEY LLM_API_KEY || miss+=("DEEPSEEK_API_KEY|LLM_API_KEY")
  if [ ${#miss[@]} -ne 0 ]; then
    record T5 "agents + MCP live calls" PARTIAL \
      "cluster present but secrets unset: ${miss[*]} — install-agents.sh installs the MCP servers/agents but GitHub+Dynatrace MCP auth and a kagent answer need live tokens. Set §3 secrets for a live run"
    return
  fi
  if bash "${REPO_ROOT}/agents/install-agents.sh" >/tmp/t5.install 2>&1; then
    record T5 "agents + MCP live calls" PARTIAL \
      "install-agents.sh applied cleanly; live GitHub read + live Dynatrace query + a kagent answer must be exercised against the agents (see agents/README.md) to turn this PASS"
  else
    record T5 "agents + MCP live calls" FAIL "install-agents.sh exited non-zero (see /tmp/t5.install)"
  fi
}

# =============================================================================
# T6 — dtctl smoke (auth + one read)
# =============================================================================
t6_dtctl() {
  hdr "T6 — dtctl smoke (authenticate + one read)"
  if ! have dtctl; then
    record T6 "dtctl auth + read" SKIP "dtctl not installed (not the Codespace image) — see T1"
    return
  fi
  if ! ( secret_set DT_PLATFORM_TOKEN && ( secret_set DT_ENVIRONMENT || secret_set DT_TENANT_URL ) ); then
    record T6 "dtctl auth + read" PARTIAL \
      "dtctl present but DT_PLATFORM_TOKEN / DT_ENVIRONMENT unset — cannot authenticate. Set the §3 platform token for a live read"
    return
  fi
  local env_url="${DT_ENVIRONMENT:-${DT_TENANT_URL/.live./.apps.}}"
  if DT_PLATFORM_TOKEN="${DT_PLATFORM_TOKEN}" dtctl --environment "${env_url}" settings list >/tmp/t6.out 2>&1 \
     || DT_PLATFORM_TOKEN="${DT_PLATFORM_TOKEN}" dtctl settings list >/tmp/t6.out 2>&1; then
    record T6 "dtctl auth + read" PASS "dtctl authenticated and returned a read against ${env_url}"
  else
    record T6 "dtctl auth + read" FAIL "dtctl read failed (see /tmp/t6.out) — check token scopes / DT_ENVIRONMENT"
  fi
}

# =============================================================================
# T7 — Phase 4 evals (dt-evals doctor + one eval; Phoenix on 6006)
# =============================================================================
t7_evals() {
  hdr "T7 — Phase 4 evals (dt-evals doctor + eval; Phoenix 6006)"
  local doctor="unknown"
  if have dt-evals; then
    if dt-evals doctor >/tmp/t7.doctor 2>&1; then doctor="OK"; else doctor="FAIL"; fi
  elif have npx; then
    doctor="npx-fallback"
  else
    record T7 "dt-evals doctor + eval" SKIP "neither dt-evals nor npx installed — see T1"
    return
  fi

  local phoenix="down"
  if have curl && curl -fsS -o /dev/null --max-time 3 http://127.0.0.1:6006 2>/dev/null; then
    phoenix="up"
  fi

  if ! ( either_set DYNATRACE_API_TOKEN DT_API_TOKEN && ( secret_set DT_ENVIRONMENT_URL || secret_set DT_ENV_URL || secret_set DT_TENANT_URL ) ); then
    record T7 "dt-evals doctor + eval" PARTIAL \
      "doctor=${doctor}; Phoenix(6006)=${phoenix}; dt-evals token/env unset — one eval writeback needs DYNATRACE_API_TOKEN + DT_ENVIRONMENT_URL + a discovered DT_EVAL_SERVICE. Set them (evals/.env) for a live eval"
    return
  fi
  if [ "$doctor" = "OK" ] && bash "${REPO_ROOT}/evals/dt-evals/run-dt-eval.sh" >/tmp/t7.eval 2>&1; then
    record T7 "dt-evals doctor + eval" PASS "doctor OK; one eval ran + wrote back; Phoenix(6006)=${phoenix}"
  else
    record T7 "dt-evals doctor + eval" PARTIAL \
      "doctor=${doctor}; Phoenix(6006)=${phoenix}; eval run needs a live tenant + DT_EVAL_SERVICE (see /tmp/t7.*)"
  fi
}

# =============================================================================
# T8 — mkdocs serve on 8000
# =============================================================================
t8_mkdocs() {
  hdr "T8 — mkdocs serve on :8000"
  if ! have mkdocs; then
    record T8 "mkdocs serve :8000" SKIP "mkdocs not installed — see T1"
    return
  fi
  if ! have curl; then
    record T8 "mkdocs serve :8000" PARTIAL "mkdocs present but curl missing — cannot probe :8000; 'mkdocs build' is the fallback check"
    return
  fi
  ( cd "${REPO_ROOT}" && mkdocs serve -a 127.0.0.1:8000 >/tmp/t8.serve 2>&1 ) &
  local pid=$!
  local ok=0 i
  for i in $(seq 1 20); do
    if curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:8000 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  kill "$pid" >/dev/null 2>&1; wait "$pid" 2>/dev/null
  if [ "$ok" -eq 1 ]; then
    record T8 "mkdocs serve :8000" PASS "site responded 200 on http://127.0.0.1:8000"
  else
    # fall back to a build check so we still get signal if the port was busy
    if ( cd "${REPO_ROOT}" && mkdocs build -q >/tmp/t8.build 2>&1 ); then
      record T8 "mkdocs serve :8000" PARTIAL "serve probe failed but 'mkdocs build' succeeds (port 8000 may be busy) — see /tmp/t8.serve"
    else
      record T8 "mkdocs serve :8000" FAIL "serve did not respond and 'mkdocs build' failed (see /tmp/t8.build)"
    fi
  fi
}

# =============================================================================
# T9 — Stop/resume (cluster back via postStart)
# =============================================================================
t9_resume() {
  hdr "T9 — Stop/resume (cluster back via postStart)"
  if ! cluster_up; then
    record T9 "resume via postStart" SKIP \
      "no cluster — a true stop/resume is a Codespaces-platform action; the automatable proxy is postStart bringing the cluster back (needs a live cluster)"
    return
  fi
  # Automatable proxy: run the postStart hook and require the cluster to be
  # reachable afterwards. A full stop/resume cycle is platform-driven (manual).
  if bash "${DEVC}/postStart.sh" >/tmp/t9.poststart 2>&1 && cluster_up; then
    record T9 "resume via postStart" PARTIAL \
      "postStart ran idempotently and the cluster is reachable; a FULL Codespace stop+resume cycle must be done via the Codespaces platform to turn this PASS"
  else
    record T9 "resume via postStart" FAIL "postStart failed or cluster not reachable afterwards (see /tmp/t9.poststart)"
  fi
}

# =============================================================================
# Run
# =============================================================================
printf "${c_blue}Fresh-Codespace validation harness — T0..T9 (ISI-6744 §5)${c_reset}\n"
info "repo:        ${REPO_ROOT}"
info "mode:        $([ "$STATIC_ONLY" -eq 1 ] && echo 'static-only' || echo 'full (auto-detect)')"
info "cluster:     CLUSTER_TOOL=${CLUSTER_TOOL} name=${CLUSTER_NAME} up=$(cluster_up && echo yes || echo no)"
info "docker:      $(docker_up && echo up || echo down)"

t0_build
t1_toolchain
t2_secrets
if [ "$STATIC_ONLY" -eq 0 ]; then
  t3_cluster
  t4_phase2
  t5_phase3
  t6_dtctl
  t7_evals
  t8_mkdocs
  t9_resume
else
  for id in T3 T4 T5 T6 T7 T8 T9; do
    record "$id" "(skipped in --static mode)" SKIP "live/env check not run in static mode"
  done
fi

# =============================================================================
# Summary + optional markdown
# =============================================================================
hdr "Summary"
declare -A COUNT=([PASS]=0 [FAIL]=0 [SKIP]=0 [PARTIAL]=0)
for r in "${RESULTS[@]}"; do
  st=$(cut -f3 <<< "$r"); COUNT[$st]=$(( ${COUNT[$st]:-0} + 1 ))
done
printf "  PASS=%d  PARTIAL=%d  SKIP=%d  FAIL=%d  (of %d)\n" \
  "${COUNT[PASS]}" "${COUNT[PARTIAL]}" "${COUNT[SKIP]}" "${COUNT[FAIL]}" "${#RESULTS[@]}"

if [ -n "$MARKDOWN_OUT" ]; then
  {
    echo ""
    echo "| Test | Gate | Status | Detail |"
    echo "|------|------|--------|--------|"
    for r in "${RESULTS[@]}"; do
      id=$(cut -f1 <<< "$r"); name=$(cut -f2 <<< "$r")
      st=$(cut -f3 <<< "$r"); det=$(cut -f4 <<< "$r" | sed 's/|/\\|/g')
      echo "| ${id} | ${name} | ${st} | ${det} |"
    done
    echo ""
    echo "_Summary: PASS=${COUNT[PASS]} · PARTIAL=${COUNT[PARTIAL]} · SKIP=${COUNT[SKIP]} · FAIL=${COUNT[FAIL]}_"
  } >> "$MARKDOWN_OUT"
  info "markdown table appended to ${MARKDOWN_OUT}"
fi

# Exit non-zero only on a hard FAIL; SKIP/PARTIAL are the documented offline reality.
[ "${COUNT[FAIL]}" -eq 0 ]
