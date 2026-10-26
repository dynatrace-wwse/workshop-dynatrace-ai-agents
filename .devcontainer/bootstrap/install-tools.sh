#!/usr/bin/env bash
# Install the workshop toolchain into the devcontainer image.
# Invoked from the Dockerfile at build time (runs as root). Idempotent enough to
# re-run, but primarily a build-time step. All downloads are arch-aware.
set -euo pipefail

ARCH="$(dpkg --print-architecture)"   # amd64 | arm64
case "$ARCH" in
  amd64) GOARCH=amd64 ;;
  arm64) GOARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

log() { echo "[install-tools] $*"; }

# --- kubectl ---
log "kubectl ${KUBECTL_VERSION} (${GOARCH})"
curl -fsSL -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GOARCH}/kubectl"
chmod +x /usr/local/bin/kubectl

# --- helm ---
log "helm ${HELM_VERSION} (${GOARCH})"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${GOARCH}.tar.gz" \
  | tar -xz -C /tmp
install -m 0755 "/tmp/linux-${GOARCH}/helm" /usr/local/bin/helm
rm -rf "/tmp/linux-${GOARCH}"

# --- kind ---
log "kind ${KIND_VERSION} (${GOARCH})"
curl -fsSL -o /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${GOARCH}"
chmod +x /usr/local/bin/kind

# --- k3d ---
log "k3d ${K3D_VERSION} (${GOARCH})"
curl -fsSL -o /usr/local/bin/k3d \
  "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${GOARCH}"
chmod +x /usr/local/bin/k3d

# --- yq ---
log "yq ${YQ_VERSION} (${GOARCH})"
curl -fsSL -o /usr/local/bin/yq \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${GOARCH}"
chmod +x /usr/local/bin/yq

# --- kagent CLI ---
# Released as a per-OS/arch binary on github.com/kagent-dev/kagent.
# Best-effort with a clear failure message; Phase 2/3 need this CLI present.
log "kagent ${KAGENT_VERSION} (${GOARCH})"
KAGENT_URL="https://github.com/kagent-dev/kagent/releases/download/${KAGENT_VERSION}/kagent-linux-${GOARCH}"
if curl -fsSL -o /usr/local/bin/kagent "$KAGENT_URL"; then
  chmod +x /usr/local/bin/kagent
else
  log "WARN: could not download kagent from ${KAGENT_URL}."
  log "WARN: pin a valid KAGENT_VERSION or install via 'curl -fsSL https://kagent.dev/install.sh | bash' in postCreate."
fi

# --- uv (Python package/venv manager for dt-evals) ---
log "uv ${UV_VERSION} (${GOARCH})"
UV_TARBALL="uv-$( [ "$GOARCH" = amd64 ] && echo x86_64 || echo aarch64 )-unknown-linux-gnu.tar.gz"
curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_TARBALL}" \
  | tar -xz -C /tmp
install -m 0755 /tmp/uv-*/uv /usr/local/bin/uv
install -m 0755 /tmp/uv-*/uvx /usr/local/bin/uvx
rm -rf /tmp/uv-*

# --- mkdocs + material (workshop site) ---
# Installed into a dedicated venv exposed on PATH so `mkdocs` works for everyone.
log "mkdocs-material via uv tool"
export UV_TOOL_BIN_DIR=/usr/local/bin
uv tool install --with mkdocs-material --with pymdown-extensions mkdocs >/dev/null 2>&1 || {
  log "WARN: uv tool install for mkdocs failed; retrying with pip fallback"
  python3 -m pip install --no-cache-dir mkdocs mkdocs-material pymdown-extensions
}

log "versions:"
kubectl version --client --output=yaml 2>/dev/null | head -3 || true
helm version --short || true
kind --version || true
k3d --version || true
yq --version || true
uv --version || true
mkdocs --version || true
command -v kagent >/dev/null && kagent version 2>/dev/null || echo "kagent: (verify in postCreate)"
log "done"
