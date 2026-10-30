#!/bin/bash
# AI Agent Workshop — integration test.
# Runs after post-create (which installs the platform). Asserts the platform is
# up, deploys the agents and exercises every module's check that needs neither
# a tenant nor an LLM answer. The full learner path — every LAB_SOLUTION and
# its verify — is the Orbital app-layer test.
source .devcontainer/util/source_framework.sh

printInfoSection "Running integration tests for $RepositoryName"

_fail=0
_run(){ "$@" || { printError "FAILED: $*"; _fail=1; }; }

_run checkClusterReady
_run checkPlatform
_run checkDynatrace
_run checkToolsDiscovered
_run installAgents
_run checkAgents
_run checkSandboxRestricted
_run checkSandboxRejectsRogue
_run checkTetragon
_run runDiagnosisEval
_run checkDiagnosisEval

# A check that cannot fail proves nothing: the grader must reject a
# confabulated diagnosis.
echo '{"result":{"status":{"state":"completed","message":{"parts":[{"kind":"text","text":"The pod is OOMKilled."}]}}}}' > /tmp/aiw-last-sre-agent.json
if gradeLiveDiagnosis 01 >/dev/null 2>&1; then
  printError "Grader PASSED a wrong diagnosis"; _fail=1
else
  printInfo "Grader rejects a wrong diagnosis (negative control)"
fi
rm -f /tmp/aiw-last-sre-agent.json /tmp/aiw-grade-01.txt

_run injectScenario 01
_run waitForScenario
_run cleanupScenario 01
for i in $(seq 1 24); do kubectl get ns workshop-faults >/dev/null 2>&1 || break; sleep 5; done
_run checkScenarioClean

if [ "$_fail" -ne 0 ]; then
  printError "Integration test FAILED — cluster state follows"
  df -h / /var/lib/docker 2>/dev/null
  kubectl describe node | grep -A8 -E '^Conditions|^Allocated'
  kubectl get pods -A -o wide | grep -vE 'Running|Completed'
  kubectl get events -A --sort-by=.lastTimestamp | grep -vi normal | tail -40
  printError "Integration test FAILED"; exit 1
fi
printInfoSection "Integration test passed"
