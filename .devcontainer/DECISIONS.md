# Architecture Notes — Devcontainer & Codespace Bootstrap

Why the devcontainer and bootstrap are set up the way they are — cluster engine,
machine type, and tooling choices for the Codespace that runs the workshop.

## 1. Cluster engine: **k3d** (default), kind supported as a fallback

**Decision:** default `CLUSTER_TOOL=k3d`. `kind` is fully supported — set
`CLUSTER_TOOL=kind` in `devcontainer.json` `containerEnv` (or export it before
re-running `postCreate.sh`).

**Rationale:**

| Factor | k3d (k3s) | kind (kubeadm) |
|--------|-----------|----------------|
| Memory footprint | **Lowest** — k3s is a single lightweight binary; best fit for the heavy Phase 2 stack. | Higher — full kubeadm control plane per node. |
| Boot time | **Seconds.** | ~1 min. |
| Built-in LoadBalancer | **Yes** (klipper servicelb) + Traefik ingress → workshop UIs reachable with no extra install. | No service LB; needs an ingress controller or `port-forward`. |
| Docker-in-Docker | Works well. | Works well; the de-facto standard for CI. |
| Ubiquity / portability | Common. | Most widely used for local k8s demos. |

Given the Codespace runs the **entire** stack (Dynatrace operator + OTel + kagent +
Tetragon + Agent Sandbox + Phoenix + agent workloads), the deciding factor is the
**memory headroom** and the built-in LB. k3d wins on both. kind stays available
because some attendees/CI may prefer it and Tetragon eBPF behavior can differ.

> **Tetragon/eBPF note:** Tetragon needs host-kernel eBPF. Both k3d and kind run
> nodes as containers sharing the Codespace host kernel. The platform install
> validates that Tetragon loads its BPF programs in the Codespace kernel; if
> blocked, it falls back to Tetragon's limited/monitoring mode.

## 2. Recommended Codespace machine type: **4-core / 16 GB** (min), prebuild on

**Decision:** recommend a **4-core / 16 GB / 32 GB-storage** machine type for the
full workshop. Declared in `devcontainer.json` `hostRequirements`. Enable a
**Codespace prebuild** on the repo so the devcontainer image + pinned tools are
cached (fast, reliable boots for attendees).

**Rationale (resource ceiling):**

- The default **2-core / 4 GB** Codespace is **insufficient** once the platform
  stack is installed. The cluster + toolchain alone fit a small machine, but the
  Dynatrace operator,
  OTel collectors, kagent, Tetragon, Phoenix, and the two agent sets together need
  well over 4 GB. `onCreate` runs `check-resources.sh`, which warns when under the
  recommended floor.
- A prebuild removes the multi-minute first-boot tool download from the attendee's
  experience and avoids rate-limit/download flakiness mid-workshop.

## 3. Tool install strategy: pinned binaries in the Dockerfile + features for DinD/gh

**Decision:** pin every tool version in `.devcontainer/Dockerfile`
(`install-tools.sh`); use official devcontainer **features** only for
Docker-in-Docker and the GitHub CLI (complex to hand-roll).

**Rationale:** reproducible prebuilds, explicit upgrade control, arch-aware
(`amd64`/`arm64`) downloads for both Intel and ARM Codespaces.

## 4. Idempotency model

`postCreate.sh` (once) and `postStart.sh` (every resume) are both re-runnable:
cluster creation checks existence first; namespace/helm-repo prep is
create-if-missing; `postStart` restarts stopped k3d/kind node containers rather
than recreating the cluster. Re-running `postCreate` by hand is safe.

## Open questions deferred to later phases

- BindPlane live vs. illustrated — platform install.
- LLM provider powering agents + attendee key distribution — agent wiring
  (secrets contract scaffolded in `SECRETS.md`).
- Dynatrace tenant shared vs. per-attendee — evaluation/optimization modules.
- Agent Sandbox implementation choice — platform install.
