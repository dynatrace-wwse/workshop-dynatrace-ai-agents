#!/bin/bash
# Loading the framework functions into the script
export SECONDS=0
source .devcontainer/util/source_framework.sh

setUpTerminal

# Dynatrace credentials are optional here: Orbital injects them per learner,
# a Codespace gets them from secrets. Without them the platform still comes up
# and the agents' telemetry goes to Phoenix only. Names only are ever logged.
variablesNeeded DT_ENVIRONMENT:false DT_OPERATOR_TOKEN:false DT_INGEST_TOKEN:false DT_PLATFORM_TOKEN:false

# Single-node k3d (framework default) — replaces the workshop's own kind cluster.
startK3dCluster

installK9s

# Module 01 is a verification step: the platform (Dynatrace Operator in
# Kubernetes-monitoring mode, OTel gateway, Phoenix, kagent, Tetragon, Agent
# Sandbox, LLM backend) is installed here so the learner starts on a working
# stack. AIW_PREINSTALL=false leaves it to the learner (installPlatform).
if [ "${AIW_PREINSTALL:-true}" = "true" ]; then
  installPlatform
fi

finalizePostCreation

printInfoSection "Your dev container finished creating"
