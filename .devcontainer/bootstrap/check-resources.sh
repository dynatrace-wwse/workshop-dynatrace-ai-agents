#!/usr/bin/env bash
# Validate the Codespace resource ceiling.
# Runs at onCreate. Non-fatal: warns loudly if the machine is too small for the
# full workshop stack, but never blocks the build.
set -uo pipefail

CPUS="$(nproc 2>/dev/null || echo '?')"
MEM_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_GB=$(( MEM_KB / 1024 / 1024 ))

echo "=============================================================="
echo " Codespace resources: ${CPUS} vCPU, ~${MEM_GB} GiB RAM"
echo "=============================================================="

# Phase 1 (cluster + toolchain) fits small machines. The FULL workshop stack
# (Dynatrace operator + OTel + kagent + Tetragon + Agent Sandbox + Phoenix +
# agent workloads) is memory-hungry. Recommend 4 vCPU / 16 GiB.
REC_CPUS=4
REC_MEM_GB=14   # 16gb machines report ~15.6 GiB usable

if [ "$CPUS" != "?" ] && [ "$CPUS" -lt "$REC_CPUS" ]; then
  echo "WARNING: ${CPUS} vCPU < recommended ${REC_CPUS} vCPU."
fi
if [ "$MEM_GB" -lt "$REC_MEM_GB" ]; then
  echo "WARNING: ~${MEM_GB} GiB RAM < recommended 16 GiB."
  echo "         Phase 1 (cluster + tools) will work, but the full Phase 2 stack"
  echo "         may OOM. Recreate this Codespace on a 4-core/16GB machine type"
  echo "         (see .devcontainer/DECISIONS.md)."
else
  echo "OK: resources meet the recommended floor for the full workshop stack."
fi
echo "=============================================================="
exit 0
