# Dynatrace AI Agent Workshop — devcontainer base image
#
# Base: Microsoft devcontainers Ubuntu 22.04 (jammy). Provides the `vscode`
# non-root user, common CLI utilities, and good Codespace/prebuild support.
# Docker-in-Docker and gh are layered in via devcontainer features (see devcontainer.json).
#
# All versions are pinned so prebuilds are reproducible. Bump deliberately.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# ----- Pinned tool versions (override via --build-arg if needed) -----
ARG KUBECTL_VERSION=v1.31.4
ARG HELM_VERSION=v3.16.3
ARG KIND_VERSION=v0.25.0
ARG YQ_VERSION=v4.44.6
ARG DTCTL_VERSION=v0.45.0
ARG UV_VERSION=0.5.11
ARG NODE_VERSION=v22.11.0
# dt-evals CLI — KEEP IN SYNC with DT_EVALS_PKG in cluster/versions.env.
ARG DT_EVALS_PKG=@dynatrace-oss/dt-evals@0.3.4-alpha

ENV DEBIAN_FRONTEND=noninteractive

# ----- Base OS packages -----
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git jq gnupg bash-completion \
      apt-transport-https lsb-release make \
    && rm -rf /var/lib/apt/lists/*

# ----- Toolchain install (kubectl, helm, kind, yq, dtctl, uv, node, dt-evals, mkdocs) -----
# kind is the single cluster engine; kagent ships via its OCI Helm chart (no CLI).
COPY bootstrap/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh \
    && KUBECTL_VERSION="${KUBECTL_VERSION}" HELM_VERSION="${HELM_VERSION}" \
       KIND_VERSION="${KIND_VERSION}" YQ_VERSION="${YQ_VERSION}" \
       DTCTL_VERSION="${DTCTL_VERSION}" UV_VERSION="${UV_VERSION}" \
       NODE_VERSION="${NODE_VERSION}" DT_EVALS_PKG="${DT_EVALS_PKG}" \
       /tmp/install-tools.sh \
    && rm -f /tmp/install-tools.sh

# ----- Shell completions for the vscode user -----
RUN mkdir -p /home/vscode/.kube \
    && chown -R vscode:vscode /home/vscode/.kube \
    && printf '%s\n' \
       'source <(kubectl completion bash)' \
       'source <(helm completion bash)' \
       'source <(kind completion bash 2>/dev/null)' \
       'source <(dtctl completion bash 2>/dev/null)' \
       'alias k=kubectl' \
       'complete -o default -F __start_kubectl k' \
       >> /home/vscode/.bashrc \
    && chown vscode:vscode /home/vscode/.bashrc

USER vscode
