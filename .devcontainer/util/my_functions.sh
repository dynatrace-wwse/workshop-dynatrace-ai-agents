#!/bin/bash
# ======================================================================
# Dynatrace AI Agent Workshop — lab functions
# ----------------------------------------------------------------------
# Sourced into every terminal by the framework, so functions `return`,
# never `exit`. Every hands-on step in docs/ has three kinds of helper
# here:
#   install*/deploy*/inject*  — what the LAB_SOLUTION runs
#   check*                    — what the shell-verification button runs
#   (bounded waits)           — so a solution never races async work
#
# The platform pieces (kagent, OTel gateway, Phoenix, Tetragon, Agent
# Sandbox) keep Henrik's manifests under cluster/ and agents/; only the
# plumbing moved onto the framework: k3d via startK3dCluster, Dynatrace
# via dynatraceDeployOperator + deployDynatrace (k8s-only), UIs via the
# app registry (registerApp) instead of NodePorts + kind port mappings.
# ======================================================================

# Pinned chart / image versions live in one place (Henrik's file).
_AIW_VERSIONS="${REPO_PATH}/cluster/versions.env"
[ -f "$_AIW_VERSIONS" ] && source "$_AIW_VERSIONS"

# Offline LLM fallback. Orbital injects Dynatrace tokens only, never a model
# key, so without DEEPSEEK_API_KEY / LLM_API_KEY the agents run on a small
# tool-calling model served in-cluster by Ollama. Good enough to prove the
# wiring, the traces and the evals; not a substitute for DeepSeek's answers.
: "${AIW_OLLAMA_IMAGE:=ollama/ollama:0.12.6}"
: "${AIW_OLLAMA_MODEL:=qwen2.5:3b}"
# Inference threads. Ollama sizes its pool from the host's core count, and
# under Sysbox nproc reports the HOST (16 on a 4xlarge) while the slot may be
# capped at 4, or — the Orbital default — share every core with its
# neighbours. Either way the default oversubscribes. Cap at 4: what one seat
# is planned to use, measured 12x faster than the default under a 4-core cap.
: "${AIW_OLLAMA_THREADS:=$(n=$(nproc); [ "$n" -gt 4 ] && n=4; echo "$n")}"

# ----------------------------------------------------------------------
# Session identity — per-learner isolation in a shared tenant
# ----------------------------------------------------------------------
# The framework names the cluster (DynaKube) "<repo>-<session-id>" so a
# DQL filter `endsWith(k8s.cluster.name, "{{DT_SESSION_ID}}")` returns only
# this learner's data. The gateway collector stamps the same name on every
# agent span, so gen_ai.* spans are isolated the same way.
aiwClusterName(){
  local sid; sid="$(getDtSessionId 2>/dev/null)"
  local base; base="$(echo "${RepositoryName:-workshop}" | tr '[:upper:]' '[:lower:]')"
  base="${base#enablement-}"
  if [ -n "$sid" ]; then
    local budget=$(( 37 - ${#sid} - 1 ))
    local part="${base:0:$budget}"; part="${part%-}"
    echo "${part:+${part}-}${sid}"
  else
    echo "${base:0:37}"
  fi
}

aiwHasLlmKey(){ [ -n "${DEEPSEEK_API_KEY:-}${LLM_API_KEY:-}" ]; }

# ======================================================================
# Section 1 — Setup (post-create runs these; the step only verifies)
# ======================================================================
checkClusterReady(){
  kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready' \
    && { printInfo "✅ k3d cluster is up: $(kubectl get nodes --no-headers | wc -l) node(s) Ready"; return 0; } \
    || { printError "Cluster not reachable — run: startK3dCluster"; return 1; }
}

# ======================================================================
# Section 2 — Platform install
# ======================================================================
_aiwHelmRepos(){
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
  helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || printWarn "helm repo update had warnings"
}

_aiwNamespaces(){
  local ns
  for ns in dynatrace opentelemetry-operator-system kagent tetragon phoenix; do
    kubectl get ns "$ns" >/dev/null 2>&1 || kubectl create ns "$ns" >/dev/null
  done
}

# Dynatrace Operator + DynaKube in Kubernetes-monitoring mode (ActiveGate,
# no OneAgent). Henrik's hand-written dynakube.yaml is replaced by the
# framework's generator, which also handles platform-token tenants, the
# sprint image swap and the per-learner cluster name.
installDynatrace(){
  if [ -z "${DT_ENVIRONMENT:-}" ] || [ -z "${DT_OPERATOR_TOKEN:-}" ]; then
    printWarn "DT_ENVIRONMENT / DT_OPERATOR_TOKEN not set — skipping Dynatrace (agents still run, telemetry goes to Phoenix only)"
    return 0
  fi
  kubectl -n dynatrace get dynakube 2>/dev/null | grep -q . && { printInfo "DynaKube already present"; return 0; }
  dynatraceDeployOperator
  deployDynatrace k8s-only
}

# OpenTelemetry Operator + Henrik's gateway collector. The collector fans
# out every agent span to Dynatrace (OTLP, DT_INGEST_TOKEN) and Phoenix.
installOtelGateway(){
  printInfoSection "OpenTelemetry Operator + gateway collector"
  _aiwHelmRepos; _aiwNamespaces
  helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
    --version "${OTEL_OPERATOR_CHART_VERSION}" --namespace opentelemetry-operator-system \
    -f "${REPO_PATH}/cluster/otel/operator-values.yaml" --wait --timeout 5m

  if [ -n "${DT_ENVIRONMENT:-}" ] && [ -n "${DT_INGEST_TOKEN:-}" ]; then
    parseDynatraceEnvironment "$DT_ENVIRONMENT" >/dev/null 2>&1
    kubectl -n opentelemetry-operator-system create secret generic dynatrace-otlp \
      --from-literal=endpoint="${DT_OTEL_ENDPOINT}" \
      --from-literal=authHeader="$(case "$DT_INGEST_TOKEN" in dt0s16.*) echo Bearer;; *) echo Api-Token;; esac) ${DT_INGEST_TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    printInfo "secret/dynatrace-otlp written (OTLP → ${DT_OTEL_ENDPOINT})"
  else
    printWarn "DT_INGEST_TOKEN not set — gateway exports to Phoenix only"
  fi

  local i rendered
  export K8S_CLUSTER_NAME; K8S_CLUSTER_NAME="$(aiwClusterName)"
  rendered="$(envsubst '${K8S_CLUSTER_NAME}' < "${REPO_PATH}/cluster/otel/collector-gateway.yaml")"
  if [ -z "${DT_ENVIRONMENT:-}" ] || [ -z "${DT_INGEST_TOKEN:-}" ]; then
    rendered="$(printf '%s\n' "$rendered" | sed '/# >>> dynatrace-exporter/,/# <<< dynatrace-exporter/d; s#otlphttp/dynatrace, ##')"
  fi
  for i in $(seq 1 20); do
    printf '%s\n' "$rendered" | kubectl apply -f - >/dev/null 2>&1 \
      && { printInfo "Gateway collector applied (k8s.cluster.name=${K8S_CLUSTER_NAME})"; break; }
    sleep 5
  done
  kubectl -n opentelemetry-operator-system rollout status deploy/otel-gateway-collector --timeout=180s
}

installTetragon(){
  printInfoSection "Tetragon (eBPF runtime security)"
  _aiwHelmRepos; _aiwNamespaces
  helm upgrade --install tetragon cilium/tetragon --version "${TETRAGON_CHART_VERSION}" \
    --namespace tetragon -f "${REPO_PATH}/cluster/tetragon/values.yaml" --wait --timeout 5m \
    || printWarn "Tetragon reported issues — see Troubleshooting (eBPF on a container node)"
}

installKagent(){
  printInfoSection "kagent ${KAGENT_CHART_VERSION}"
  _aiwNamespaces
  aiwLlmSecret
  helm upgrade --install kagent-crds "${KAGENT_OCI_REPO}/kagent-crds" \
    --version "${KAGENT_CHART_VERSION}" --namespace kagent --wait --timeout 5m
  helm upgrade --install kagent "${KAGENT_OCI_REPO}/kagent" \
    --version "${KAGENT_CHART_VERSION}" --namespace kagent \
    -f "${REPO_PATH}/cluster/kagent/values.yaml" --wait --timeout 8m
  registerApp kagent kagent kagent-ui 8080
}

installPhoenix(){
  printInfoSection "Phoenix (LLM trace + eval UI)"
  _aiwNamespaces
  kubectl apply -f "${REPO_PATH}/cluster/phoenix/phoenix.yaml"
  kubectl -n phoenix rollout status deploy/phoenix --timeout=300s
  registerApp phoenix phoenix phoenix 6006
}

installAgentSandbox(){
  printInfoSection "Agent Sandbox (isolation baseline)"
  kubectl apply -f "${REPO_PATH}/cluster/agent-sandbox/isolation.yaml"
}

# The whole of section 2 in one call — what the LAB_SOLUTION runs, and
# what post-create runs when AIW_PREINSTALL is on (the default).
installPlatform(){
  installDynatrace
  installOtelGateway
  installPhoenix
  installKagent
  installTetragon
  installAgentSandbox
  aiwLlmBackend
}

checkPlatform(){
  local fail=0 d
  for d in opentelemetry-operator-system/opentelemetry-operator \
           opentelemetry-operator-system/otel-gateway-collector \
           kagent/kagent-controller kagent/kagent-ui phoenix/phoenix; do
    if kubectl -n "${d%%/*}" get deploy "${d##*/}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qE '^[1-9]'; then
      printInfo "✅ ${d} ready"
    else
      printError "❌ ${d} not ready"; fail=1
    fi
  done
  kubectl get ns agent-sandbox >/dev/null 2>&1 || { printError "❌ agent-sandbox namespace missing"; fail=1; }
  return $fail
}

# Dynatrace is optional off-Orbital; on Orbital it is always injected.
checkDynatrace(){
  if [ -z "${DT_ENVIRONMENT:-}" ]; then
    printInfo "No Dynatrace tenant configured — step not applicable"; return 0
  fi
  local phase
  phase="$(kubectl -n dynatrace get dynakube -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
  [ "$phase" = "Running" ] \
    && { printInfo "✅ DynaKube phase: Running"; return 0; } \
    || { printError "DynaKube phase is '${phase:-absent}' — run installDynatrace"; return 1; }
}

# ======================================================================
# LLM backend — DeepSeek when a key exists, in-cluster Ollama otherwise
# ======================================================================
aiwLlmSecret(){
  local key="${DEEPSEEK_API_KEY:-${LLM_API_KEY:-}}"
  [ -n "$key" ] || return 0
  kubectl -n kagent create secret generic kagent-deepseek \
    --from-literal=DEEPSEEK_API_KEY="$key" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  printInfo "secret/kagent-deepseek written (DeepSeek key present)"
}

deployOllama(){
  printInfoSection "Ollama (offline LLM: ${AIW_OLLAMA_MODEL})"
  export AIW_OLLAMA_IMAGE AIW_OLLAMA_MODEL
  envsubst '${AIW_OLLAMA_IMAGE} ${AIW_OLLAMA_MODEL}' < "${REPO_PATH}/agents/mcp/ollama.yaml" | kubectl apply -f -
  kubectl -n ollama rollout status deploy/ollama --timeout=300s
  # Pull the model once; the pod's PVC keeps it across restarts.
  local i
  for i in $(seq 1 60); do
    kubectl -n ollama exec deploy/ollama -- ollama list 2>/dev/null | grep -q "${AIW_OLLAMA_MODEL%%:*}" && break
    kubectl -n ollama exec deploy/ollama -- ollama pull "${AIW_OLLAMA_MODEL}" >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl -n ollama exec deploy/ollama -- ollama list 2>/dev/null | grep -q "${AIW_OLLAMA_MODEL%%:*}" \
    && printInfo "Model ${AIW_OLLAMA_MODEL} ready" || printWarn "Model pull did not finish — re-run deployOllama"
}

aiwLlmBackend(){
  if aiwHasLlmKey; then
    printInfo "LLM backend: DeepSeek (key present)"
  else
    printWarn "No DEEPSEEK_API_KEY / LLM_API_KEY — agents will use the in-cluster Ollama model"
    deployOllama
  fi
}

aiwModelConfigFile(){
  if aiwHasLlmKey; then echo "${REPO_PATH}/agents/mcp/00-modelconfig.yaml"
  else echo "${REPO_PATH}/agents/mcp/00-modelconfig-ollama.yaml"; fi
}

# ======================================================================
# Section 3 — Agents & MCP wiring
# ======================================================================
installAgents(){
  printInfoSection "Agents & MCP wiring"
  kubectl get ns kagent >/dev/null 2>&1 || { printError "kagent not installed — run installPlatform"; return 1; }
  aiwHasLlmKey || kubectl -n ollama get deploy ollama >/dev/null 2>&1 || deployOllama
  aiwLlmSecret
  export GITHUB_MCP_IMAGE DYNATRACE_MCP_NODE_IMAGE DYNATRACE_MCP_PACKAGE AIW_OLLAMA_MODEL AIW_OLLAMA_THREADS
  export GH_PAT="${GH_PAT:-${GITHUB_TOKEN:-}}"
  export DT_PLATFORM_TOKEN="${DT_PLATFORM_TOKEN:-}"
  # The MCP server talks to the platform (apps) URL.
  export DT_ENVIRONMENT="${DT_ENVIRONMENT:-}"
  [ -n "$GH_PAT" ]            || printWarn "GH_PAT unset — BMAD crew installs, GitHub tools will not authenticate (optional)"
  [ -n "$DT_PLATFORM_TOKEN" ] || printWarn "DT_PLATFORM_TOKEN unset — SRE agent installs, Dynatrace tools will not authenticate"
  local vars='${GITHUB_MCP_IMAGE} ${GH_PAT} ${DYNATRACE_MCP_NODE_IMAGE} ${DYNATRACE_MCP_PACKAGE} ${DT_ENVIRONMENT} ${DT_PLATFORM_TOKEN} ${AIW_OLLAMA_MODEL} ${AIW_OLLAMA_THREADS}'
  local f
  for f in "$(aiwModelConfigFile)" "${REPO_PATH}/agents/mcp/10-github-mcp.yaml"; do
    envsubst "$vars" < "$f" | kubectl apply -f -
  done
  if aiwHasDynatraceMcp; then
    envsubst "$vars" < "${REPO_PATH}/agents/mcp/20-dynatrace-mcp.yaml" | kubectl apply -f -
    kubectl apply -k "${REPO_PATH}/agents/sre"
  else
    printWarn "No Dynatrace tenant/platform token — SRE agent deployed with Kubernetes tools only"
    kubectl -n kagent delete remotemcpserver dynatrace-mcp-remote --ignore-not-found >/dev/null 2>&1
    kubectl -n kagent delete mcpserver dynatrace-mcp --ignore-not-found >/dev/null 2>&1
    aiwStripDynatraceTools "${REPO_PATH}/agents/sre/sre-agent.yaml" | kubectl apply -f -
  fi
  kubectl apply -k "${REPO_PATH}/agents/bmad-crew"
  waitForAgentsAccepted
}

aiwHasDynatraceMcp(){ [ -n "${DT_ENVIRONMENT:-}" ] && [ -n "${DT_PLATFORM_TOKEN:-}" ]; }
aiwStripDynatraceTools(){ sed '/# >>> dynatrace-tools/,/# <<< dynatrace-tools/d' "$1"; }

# Accepted means "the controller parsed it"; Ready means its pod serves A2A.
# A re-apply rolls the pod, so wait for the rollout too — otherwise the first
# prompt after installAgents hits the old pod on its way out.
_aiwAgentsReady(){
  kubectl -n kagent get agents -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c True
}

waitForAgentsAccepted(){
  local i n a
  for i in $(seq 1 60); do
    n="$(_aiwAgentsReady)"
    [ "${n:-0}" -ge 7 ] && break
    sleep 5
  done
  for a in $(kubectl -n kagent get agents -o name 2>/dev/null); do
    kubectl -n kagent rollout status "deploy/${a##*/}" --timeout=180s >/dev/null 2>&1
  done
  n="$(_aiwAgentsReady)"
  [ "${n:-0}" -ge 7 ] && { printInfo "All 7 agents Accepted and Ready"; return 0; }
  printWarn "Only ${n:-0}/7 agents Ready so far"
  return 1
}

checkAgents(){
  local n
  n="$(_aiwAgentsReady)"
  [ "${n:-0}" -ge 7 ] \
    && { printInfo "✅ ${n} agents Ready (sre-agent + 6 BMAD)"; return 0; } \
    || { printError "${n:-0}/7 agents Ready — run installAgents"; return 1; }
}

checkToolsDiscovered(){
  local tools
  tools="$(kubectl -n kagent get remotemcpserver kagent-tool-server -o jsonpath='{.status.discoveredTools[*].name}' 2>/dev/null)"
  echo "$tools" | grep -q k8s_get_resources \
    && { printInfo "✅ kagent-tool-server exposes $(echo "$tools" | wc -w) tools"; return 0; } \
    || { printError "kagent-tool-server has not discovered its tools yet"; return 1; }
}

# Send one prompt to an agent over A2A. Prints the agent's text answer.
# Usage: askAgent <agent> "<prompt>" [timeout-seconds]
askAgent(){
  local agent="${1:-sre-agent}" prompt="${2:-List the pods in the kagent namespace.}" t="${3:-300}"
  local body
  body="$(python3 -c 'import json,sys;print(json.dumps({"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":sys.argv[1]}]}}}))' "$prompt")"
  kubectl -n kagent run "a2a-$RANDOM" --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 \
    --command -- curl -s -m "$t" -X POST -H 'Content-Type: application/json' --data "$body" \
    "http://kagent-controller.kagent:8083/api/a2a/kagent/${agent}" 2>/dev/null \
    | tee "/tmp/aiw-last-${agent}.json" \
    | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception: print(raw[:2000]); sys.exit(0)
r=d.get("result") or {}
texts=[]
def walk(o):
    if isinstance(o,dict):
        if o.get("kind")=="text" and "text" in o: texts.append(o["text"])
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(r.get("artifacts") or r.get("status") or r)
print(texts[-1] if texts else json.dumps(d)[:2000])'
}

askSreAgent(){ askAgent sre-agent "${1:-List the pods in the kagent namespace and tell me if any are unhealthy.}" "${2:-300}"; }

# An A2A answer came back that is a real reply, not a JSON-RPC error.
checkAgentAnswered(){
  local agent="${1:-sre-agent}" f="/tmp/aiw-last-${1:-sre-agent}.json"
  [ -s "$f" ] || { printError "No A2A reply recorded yet — run: askSreAgent"; return 1; }
  python3 - "$f" <<'PY' && { printInfo "✅ ${agent} answered over A2A"; return 0; }
import json,sys
d=json.load(open(sys.argv[1]))
r=d.get("result") or {}
# A JSON-RPC result is not an answer: a task the agent could not run comes
# back as a result with status.state "failed". Only a completed task counts.
sys.exit(0 if not d.get("error") and (r.get("status") or {}).get("state") == "completed" else 1)
PY
  printError "${agent} did not complete the task — check the model backend and tools (kubectl -n kagent logs deploy/${agent})"; return 1
}

# ======================================================================
# Section 4 — Secure
# ======================================================================
checkSandboxRestricted(){
  kubectl get ns agent-sandbox -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null | grep -qx restricted \
    && kubectl -n agent-sandbox get networkpolicy default-deny-all >/dev/null 2>&1 \
    && { printInfo "✅ agent-sandbox enforces PSA restricted + default-deny"; return 0; } \
    || { printError "agent-sandbox baseline missing — run installAgentSandbox"; return 1; }
}

# Admission must refuse a privileged root pod. A server-side dry-run proves
# it without leaving anything behind.
checkSandboxRejectsRogue(){
  local out
  out="$(kubectl -n agent-sandbox run rogue --image=busybox:1.36 --restart=Never --dry-run=server \
    --overrides='{"spec":{"containers":[{"name":"rogue","image":"busybox:1.36","securityContext":{"privileged":true,"runAsUser":0},"command":["sleep","3600"]}]}}' 2>&1)"
  echo "$out" | grep -q 'violates PodSecurity' \
    && { printInfo "✅ privileged pod refused: violates PodSecurity \"restricted\""; return 0; } \
    || { printError "privileged pod was NOT refused: $out"; return 1; }
}

# Tetragon needs to create eBPF maps in the host kernel. Inside a
# user-namespaced container runtime (Sysbox — what every Enablement App
# environment runs in) the kernel refuses with EPERM, so the agent cannot
# start there however it is configured. That is reported as "not available
# here" rather than failed: nothing the learner does can change it.
tetragonBlockedByRuntime(){
  kubectl -n tetragon logs ds/tetragon -c tetragon --tail=50 2>/dev/null \
    | grep -qE 'map create: operation not permitted|Unable to mount BPF filesystem.*operation not permitted'
}

checkTetragon(){
  if kubectl -n tetragon get ds tetragon -o jsonpath='{.status.numberReady}' 2>/dev/null | grep -qE '^[1-9]'; then
    printInfo "✅ Tetragon DaemonSet ready"; return 0
  fi
  if tetragonBlockedByRuntime; then
    printWarn "Tetragon cannot load eBPF in this environment (the container runtime denies BPF map creation) — read Part B, run it in a Codespace"
    return 0
  fi
  printError "Tetragon not ready — see Troubleshooting → Tetragon"; return 1
}

# ======================================================================
# Section 5 — Observe (Grail checks are DQL blocks in the docs)
# ======================================================================
generateAgentTraffic(){
  printInfoSection "Sending prompts to the SRE agent"
  askSreAgent "List pods in all namespaces and summarise anything not Running." 300 >/dev/null
  askSreAgent "How many deployments are in the kagent namespace?" 300 >/dev/null
  checkAgentAnswered sre-agent
}

# Spans reach Phoenix through the same gateway that feeds Dynatrace —
# a local proof that does not need a tenant.
checkPhoenixHasTraces(){
  local n
  n="$(kubectl -n phoenix exec deploy/phoenix -- python3 -c '
import json,urllib.request
q={"query":"{ projects { edges { node { name traceCount } } } }"}
r=urllib.request.urlopen(urllib.request.Request("http://localhost:6006/graphql",json.dumps(q).encode(),{"Content-Type":"application/json"}),timeout=10)
d=json.load(r)
print(sum(e["node"].get("traceCount") or 0 for e in d["data"]["projects"]["edges"]))' 2>/dev/null)"
  [ "${n:-0}" -gt 0 ] \
    && { printInfo "✅ Phoenix holds ${n} agent trace(s)"; return 0; } \
    || { printError "No traces in Phoenix yet — run generateAgentTraffic, wait ~30 s"; return 1; }
}

# ======================================================================
# Section 6 — Diagnose
# ======================================================================
injectScenario(){ bash "${REPO_PATH}/scenarios/run.sh" inject "${1:-01}"; }
cleanupScenario(){ bash "${REPO_PATH}/scenarios/run.sh" cleanup "${1:-01}"; }

# Passes while the fault is live, and keeps passing after cleanup once it
# HAS been seen live (the marker is only ever written by a live observation),
# so the step's checks still hold when the learner has already cleaned up.
checkScenarioInjected(){
  local reason marker=/tmp/aiw-fault-seen
  reason="$(kubectl -n workshop-faults get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{" "}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}' 2>/dev/null)"
  if echo "$reason" | grep -qE 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|OOMKilled'; then
    echo "$reason" | tr -s ' \n' ' ' > "$marker"
    printInfo "✅ Fault is live in workshop-faults: $(cat "$marker")"; return 0
  fi
  if [ -s "$marker" ] && ! kubectl get ns workshop-faults >/dev/null 2>&1; then
    printInfo "✅ Fault was observed live ($(cat "$marker")) and has since been cleaned up"; return 0
  fi
  printError "No broken pod in workshop-faults yet — run: injectScenario 01 (give it ~30 s)"; return 1
}

waitForScenario(){
  local i
  for i in $(seq 1 24); do checkScenarioInjected >/dev/null 2>&1 && return 0; sleep 5; done
  checkScenarioInjected
}

diagnoseScenario(){
  local id="${1:-01}" dir
  dir="$(ls -d "${REPO_PATH}"/scenarios/${id}* 2>/dev/null | head -1)"
  [ -f "$dir/prompt.md" ] || { printError "Unknown scenario $id"; return 1; }
  # The learner prompt is the first blockquote of prompt.md (the "paste this"
  # text) — never the curl example, which would hand the agent a shell script.
  local prompt
  prompt="$(awk '/^> /{sub(/^> /,""); printf "%s ", $0; f=1; next} f{exit}' "$dir/prompt.md" | tr -d '`')"
  [ -n "$prompt" ] || { printError "No prompt found in $dir/prompt.md"; return 1; }
  askSreAgent "$prompt" 420
}

checkScenarioClean(){
  kubectl get ns workshop-faults >/dev/null 2>&1 \
    && { printError "workshop-faults still exists — run: cleanupScenario 01"; return 1; } \
    || { printInfo "✅ No residue — workshop-faults removed"; return 0; }
}

# Scenario 12's app. Henrik's opentelemetry-demo-light chart, deployed into
# `otel-demo` where scenarios/12-*/inject.sh expects it.
# TODO(astroshop-lite): switch to `deployApp astroshop-lite` once framework
# 1.20.0 ships it (worker 212), and point inject.sh at its namespace.
deployOtelDemoLight(){
  printInfoSection "opentelemetry-demo-light (scenario 12 app)"
  helm upgrade --install otel-demo "${OTEL_DEMO_OCI_REPO}" --version "${OTEL_DEMO_CHART_VERSION}" \
    -n otel-demo --create-namespace -f "${REPO_PATH}/cluster/otel-demo/values-light.yaml" --wait --timeout 8m
}

# ======================================================================
# Section 7 — Evaluate
# ======================================================================
_aiwUv(){
  command -v uv >/dev/null 2>&1 && return 0
  [ -x "$HOME/.local/bin/uv" ] && export PATH="$HOME/.local/bin:$PATH" && return 0
  printInfo "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1
}

# The deterministic diagnosis grader — stdlib only, no judge key, no cluster.
runDiagnosisEval(){
  ( cd "${REPO_PATH}/evals" && python3 phoenix/run_diagnosis_eval.py "$@" )
}

checkDiagnosisEval(){
  local csv="${REPO_PATH}/evals/phoenix/out/diagnosis_eval_results.csv"
  # The bundled set holds a golden AND a confabulated answer per scenario, so
  # a grader that works must produce both verdicts — all-pass would mean it
  # grades nothing.
  [ -s "$csv" ] && grep -q ',True,' "$csv" && grep -q ',False,' "$csv" \
    && { printInfo "✅ Diagnosis grader ran: $(grep -c ',True,' "$csv") PASS / $(grep -c ',False,' "$csv") FAIL"; return 0; } \
    || { printError "No grader results yet — run: runDiagnosisEval"; return 1; }
}

# Grade the SRE agent's own last answer (from askSreAgent / diagnoseScenario)
# against a scenario's answer key. Exit 0 = PASS, 1 = FAIL. The verdict is
# also written to /tmp/aiw-grade-<id>.txt so the step's check can tell
# "graded" apart from "never graded" — a small model failing the key is a
# lesson, not a broken step.
gradeLiveDiagnosis(){
  local id="${1:-01}" f="/tmp/aiw-last-sre-agent.json"
  [ -s "$f" ] || { printError "No SRE-agent answer recorded — run: diagnoseScenario 01"; return 1; }
  ( cd "${REPO_PATH}/evals" && python3 - "$id" "$f" <<'PY'
import json, sys
import ground_truth as gt
sid, path = sys.argv[1], sys.argv[2]
fx = {k: v for k, v in gt.load_fixtures().items() if k.startswith(sid)}
if not fx:
    print(f"unknown scenario {sid}"); sys.exit(2)
fixture = next(iter(fx.values()))
texts = []
def walk(o):
    if isinstance(o, dict):
        if o.get("kind") == "text" and "text" in o: texts.append(o["text"])
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(json.load(open(path)).get("result") or {})
r = gt.grade("\n".join(texts), fixture)
print(f"{fixture.scenario}: signals {len(r.signals_cited)}/{fixture.pass_threshold} "
      f"root_cause={'yes' if r.root_cause_cited else 'NO'} -> {'PASS' if r.passed else 'FAIL'}")
sys.exit(0 if r.passed else 1)
PY
  ) | tee "/tmp/aiw-grade-${id}.txt"
  return "${PIPESTATUS[0]}"
}

checkDiagnosisGraded(){
  local id="${1:-01}" g="/tmp/aiw-grade-${1:-01}.txt"
  grep -qE 'PASS|FAIL' "$g" 2>/dev/null \
    && { printInfo "✅ Graded: $(cat "$g")"; return 0; } \
    || { printError "Not graded yet — run: gradeLiveDiagnosis ${id}"; return 1; }
}

runGroundTruthTests(){
  _aiwUv || { printError "uv not available"; return 1; }
  ( cd "${REPO_PATH}/evals" && uv run --group dev pytest -q tests/ )
}

# ======================================================================
# Section 8 — Optimize
# ======================================================================
# Re-apply the SRE agent with its Dynatrace tools pinned to the handful the
# traces show it actually calls — the "remove unused tools" cut.
applyLeanSreAgent(){
  if aiwHasDynatraceMcp; then
    kubectl apply -f "${REPO_PATH}/agents/sre/sre-agent-lean.yaml"
  else
    printWarn "No Dynatrace MCP in this session — nothing to trim; the agent keeps only its Kubernetes tools"
  fi
}

checkLeanSreAgent(){
  local n
  n="$(kubectl -n kagent get agent sre-agent -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
tools=d["spec"]["declarative"]["tools"]
print(sum(len(t.get("mcpServer",{}).get("toolNames") or []) for t in tools if t.get("mcpServer",{}).get("name")=="dynatrace-mcp-remote"))' 2>/dev/null)"
  if ! aiwHasDynatraceMcp; then
    printInfo "No Dynatrace MCP in this session — step not applicable"; return 0
  fi
  [ "${n:-0}" -gt 0 ] \
    && { printInfo "✅ sre-agent pins ${n} Dynatrace tool(s) instead of all of them"; return 0; } \
    || { printError "sre-agent still exposes every Dynatrace tool — run: applyLeanSreAgent"; return 1; }
}

# ======================================================================
# Cleanup
# ======================================================================
removeAgents(){
  kubectl delete -k "${REPO_PATH}/agents/bmad-crew" --ignore-not-found
  kubectl delete -k "${REPO_PATH}/agents/sre" --ignore-not-found
}
