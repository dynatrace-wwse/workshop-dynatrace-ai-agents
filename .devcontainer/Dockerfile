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
ARG K3D_VERSION=v5.7.5
ARG KAGENT_VERSION=v0.3.5
ARG YQ_VERSION=v4.44.6
ARG UV_VERSION=0.5.11

ENV DEBIAN_FRONTEND=noninteractive

# ----- Base OS packages -----
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git jq gnupg bash-completion \
      apt-transport-https lsb-release make \
    && rm -rf /var/lib/apt/lists/*

# ----- Toolchain install (kubectl, helm, kind, k3d, kagent, yq, uv, mkdocs) -----
COPY bootstrap/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh \
    && KUBECTL_VERSION="${KUBECTL_VERSION}" HELM_VERSION="${HELM_VERSION}" \
       KIND_VERSION="${KIND_VERSION}" K3D_VERSION="${K3D_VERSION}" \
       KAGENT_VERSION="${KAGENT_VERSION}" YQ_VERSION="${YQ_VERSION}" \
       UV_VERSION="${UV_VERSION}" \
       /tmp/install-tools.sh \
    && rm -f /tmp/install-tools.sh

# ----- Shell completions for the vscode user -----
RUN mkdir -p /home/vscode/.kube \
    && chown -R vscode:vscode /home/vscode/.kube \
    && printf '%s\n' \
       'source <(kubectl completion bash)' \
       'source <(helm completion bash)' \
       'source <(k3d completion bash 2>/dev/null)' \
       'source <(kind completion bash 2>/dev/null)' \
       'alias k=kubectl' \
       'complete -o default -F __start_kubectl k' \
       >> /home/vscode/.bashrc \
    && chown vscode:vscode /home/vscode/.bashrc

USER vscode
