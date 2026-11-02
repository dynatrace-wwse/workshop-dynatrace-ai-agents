#!/usr/bin/env bash
# ISI-6957 — reproducible live validation for the sensitive-file detection step.
#
# WHY: ISI-6953 reported the module-03 detection step fired *no* event. Two
# defects: (1) `tetra getevents` is a live tail — a one-shot `cat … ; sleep 30`
# read can land before the watch attaches, and getevents never replays history;
# (2) the projected SA-token path may resolve to a kubelet host path that never
# matches the policy's /var/run/secrets prefix. This script proves the fixed
# flow — loop-snoop + a guaranteed-match path (/etc/passwd) + the widened policy
# prefix — ALWAYS produces a `process_kprobe` event for `security_file_permission`
# on the `snoop` pod, and prints the raw getevents line as evidence.
#
# It assumes a reachable Kubernetes cluster (a kind cluster in CI) and that
# kubectl + helm are on PATH. It installs Tetragon with the SAME chart version
# and values the workshop uses, so it validates the artifacts shippers actually
# run — not a bespoke setup.
#
# USAGE:  bash cluster/tetragon/validate-live.sh
# EXIT:   0 = detection fired (evidence printed);  non-zero = it did not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pinned chart version — kept in sync with cluster/versions.env.
TETRAGON_CHART_VERSION="${TETRAGON_CHART_VERSION:-1.7.1}"
CAPTURE_SECS="${CAPTURE_SECS:-40}"
POLICY="${SCRIPT_DIR}/sensitive-file-access.yaml"
EVIDENCE="$(mktemp -t tetra-events.XXXXXX)"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; }

cleanup() {
  kubectl -n agent-sandbox delete pod snoop --ignore-not-found >/dev/null 2>&1 || true
  rm -f "$EVIDENCE" 2>/dev/null || true
}
trap cleanup EXIT

log "1/6  Namespaces (tetragon + agent-sandbox)"
kubectl create namespace tetragon --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace agent-sandbox --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "namespaces present"

log "2/6  Install Tetragon (cilium/tetragon ${TETRAGON_CHART_VERSION})"
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null 2>&1 || helm repo update >/dev/null 2>&1 || true
helm upgrade --install tetragon cilium/tetragon \
  --version "${TETRAGON_CHART_VERSION}" \
  --namespace tetragon \
  -f "${SCRIPT_DIR}/values.yaml" --wait --timeout 6m
kubectl -n tetragon rollout status ds/tetragon --timeout=5m
ok "Tetragon DaemonSet ready"

log "3/6  Apply the detection policy"
# Wait for the TracingPolicyNamespaced CRD the operator registers.
for i in $(seq 1 30); do
  kubectl get crd tracingpoliciesnamespaced.cilium.io >/dev/null 2>&1 && break
  sleep 2
done
kubectl apply -f "${POLICY}"
kubectl -n agent-sandbox get tracingpolicynamespaced detect-sensitive-file-access
ok "policy detect-sensitive-file-access accepted by the apiserver"
# Give the agent a moment to actually LOAD the kprobe selectors into the kernel.
sleep 10
# `kubectl apply` only means the apiserver stored the CR — the Tetragon agent can
# still reject it at load time (e.g. an unsupported returnArgAction), which only
# shows as a warn in the agent log and leaves the kprobe un-attached so NO event
# ever fires. That silent failure was the real ISI-6953 cause, so assert here
# that the agent did not reject the policy.
if kubectl -n tetragon logs ds/tetragon -c tetragon --tail=500 2>/dev/null \
     | grep -iE "adding tracing policy failed|failed loading policy 'detect-sensitive-file-access'"; then
  fail "Tetragon REJECTED the policy at load time (see warn above) — kprobe never attached"
  exit 1
fi
ok "Tetragon loaded the policy (no load error in agent log)"

log "4/6  Launch the loop-snoop pod (reads /etc/passwd + SA token every 2s)"
kubectl -n agent-sandbox run snoop --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"snoop","image":"busybox:1.36","securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":65534,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}},"command":["sh","-c","while true; do cat /etc/passwd /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1; sleep 2; done"]}]}}' \
  --command -- sh -c 'while true; do cat /etc/passwd /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1; sleep 2; done'
kubectl -n agent-sandbox wait --for=condition=Ready pod/snoop --timeout=120s
ok "snoop pod Running and looping"

log "5/6  Capture ${CAPTURE_SECS}s of filtered getevents (loop fires inside the window)"
# tetra ships inside the tetragon container; exec it there. The loop reads every
# 2s, so even though getevents only tails *new* events, we are guaranteed several
# hits during the capture window — proving the fix removes the timing race.
TETRA_POD="$(kubectl -n tetragon get pod -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].metadata.name}')"
timeout "${CAPTURE_SECS}" kubectl -n tetragon exec "${TETRA_POD}" -c tetragon -- \
  tetra getevents -o compact --namespace agent-sandbox > "${EVIDENCE}" 2>/dev/null || true
ok "captured $(wc -l < "${EVIDENCE}") event line(s)"

log "6/6  Assert a security_file_permission kprobe fired for the snoop pod"
# tetra's COMPACT renderer prints a security_file_permission file-read kprobe as
# a `read` action line, e.g.
#     📚 read    agent-sandbox/snoop /bin/cat /etc/passwd
# NOT the literal word "kprobe" — so match the `read` action naming the snoop
# pod + a sensitive path. The `process`/`exit` exec lines use the `process`/
# `exit` actions (and quote the command), so this will not false-match them.
MATCH="$(grep -E 'read[[:space:]]+agent-sandbox/snoop' "${EVIDENCE}" | grep -E '/etc/passwd|serviceaccount' | head -3 || true)"
if [ -n "${MATCH}" ]; then
  ok "DETECTION FIRED — raw evidence:"
  echo "----------------------------------------------------------------------"
  echo "${MATCH}"
  echo "----------------------------------------------------------------------"
  exit 0
fi

fail "no sensitive-file kprobe event captured — full stream below for triage:"
echo "----------------------------------------------------------------------"
cat "${EVIDENCE}"
echo "----------------------------------------------------------------------"
echo "Diagnostics:"
kubectl -n agent-sandbox get pod snoop -o wide || true
kubectl -n agent-sandbox describe tracingpolicynamespaced detect-sensitive-file-access || true
exit 1
