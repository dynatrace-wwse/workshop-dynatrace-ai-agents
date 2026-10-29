# ISI-6835 — Codespace bootstrap remediation plan

**Status:** awaiting board approval (planning mode — no code changed yet)
**Author:** Winston (Architect) · 2026-10-29
**Scope:** `.devcontainer/**` + `cluster/**` bootstrap only. No workshop content, no platform source.

---

## 1. What actually broke

The image **built fine** (`devcontainer process exited with exit code 0`) and the
container started. The failure is in `postCreate.sh`:

```
[ fail ] tool MISSING: mkdocs
[ warn ] kagent CLI not on PATH
[ warn ] dt-evals CLI not on PATH — falls back to npx
[ fail ] required tools missing; aborting
postCreateCommand ... failed with exit code 1
```

`postCreate.sh:13` puts `mkdocs` in the **hard-required** tool loop. The build-time
`uv tool install … mkdocs` in `install-tools.sh:95` did not land on PATH, so the
gate at `postCreate.sh:18` aborts **before the cluster is ever created**. Result:
the attendee gets a Codespace with no cluster and a red error, even though
`mkdocs` is only needed to preview the docs site locally (and the docs are already
published). `kagent` and `dt-evals` were non-fatal warnings — not the blocker.

**One-line root cause:** a non-essential, best-effort tool (`mkdocs`) sits in the
fatal required-tools gate, so a soft install miss hard-fails the whole bootstrap.

## 2. Board directive (decoded)

From the issue + "please lead":

1. **"kagent should be deployed … not CLI but directly helm."** The kagent CLI is
   vestigial — `cluster/install.sh` already deploys kagent via **OCI Helm charts**
   (`install.sh` step 4). Remove the kagent CLI from the image and from every gate.
2. **"devcontainer should install kubectl, dtctl, dt-evals, then kind."** Make
   **kind the one cluster engine**; drop k3d. Keep `helm` + `node` as implied deps
   (helm deploys the stack; dt-evals is a Node CLI).
3. **"once the cluster up start the deployment of our cluster."** `postCreate`
   should **deploy the full stack** (`cluster/install.sh`), not just pre-stage
   namespaces/repos.
4. **"expose as nodeport the kagent ui, phoenix."** Switch those Services to
   **NodePort** and map the NodePorts to the forwarded Codespace ports via kind
   `extraPortMappings` — no ingress, no manual `port-forward`.

## 3. Target bootstrap flow

```
image build (Dockerfile → install-tools.sh)
  → tools: kubectl, helm, kind, yq, dtctl, uv, node, dt-evals, mkdocs(best-effort)
      (REMOVED: k3d, kagent CLI)
onCreate : check-resources.sh                      (unchanged)
postCreate:
  1. verify REQUIRED tools: kubectl, helm, kind, dtctl, node   ← mkdocs/dt-evals = soft warn
  2. create-cluster.sh   (kind, with NodePort port-mappings)
  3. cluster/install.sh  (deploy the full platform — NEW: was prep-stack only)
  4. check-secrets.sh    (non-fatal)
postStart: ensure kind nodes are up                (unchanged logic, kind branch)
```

Exposure, end state:

| UI        | Service type | nodePort | kind hostPort | Codespace forward |
|-----------|--------------|----------|---------------|-------------------|
| Phoenix   | NodePort     | 30606    | 6006          | 6006              |
| kagent UI | NodePort     | 30080    | 8080          | 8080              |
| mkdocs    | n/a (bare `mkdocs serve` process, not in cluster) | — | — | 8000 |

## 4. File-by-file change list (for the implementation ticket)

1. **`.devcontainer/bootstrap/postCreate.sh`**
   - Required loop → `kubectl helm kind dtctl node` (drop `mkdocs`, drop `$CLUSTER_TOOL`→kind is already in the list).
   - `mkdocs` and `dt-evals` become soft `warn` (like dt-evals already is).
   - Delete the `kagent` CLI warn line.
   - Step 3: call `bash cluster/install.sh` instead of `prep-stack.sh` (install.sh
     self-creates namespaces + repos, so prep-stack is redundant). Keep it
     non-fatal so a single component failure doesn't brick the Codespace.
2. **`.devcontainer/bootstrap/lib.sh`** — default `CLUSTER_TOOL=kind` (was k3d).
3. **`.devcontainer/bootstrap/install-tools.sh`** — delete the **k3d** block
   (lines ~35-39) and the **kagent CLI** block (lines ~59-69); drop them from the
   header comment + the final `versions:` echo. Keep mkdocs install but it is no
   longer gating.
4. **`.devcontainer/Dockerfile`** — remove `K3D_VERSION` / `KAGENT_VERSION` ARGs,
   drop them from the `install-tools.sh` env, and remove the `k3d completion` line
   from `.bashrc`. Update the toolchain comment.
5. **`.devcontainer/devcontainer.json`** — `containerEnv.CLUSTER_TOOL` → `"kind"`;
   update the k3d/kind comment. `forwardPorts` stay `[8000, 6006, 8080, 8001]`.
6. **`cluster/kind-config.yaml`** — replace the 80→8000 / 443→8443 ingress
   mappings with NodePort mappings:
   ```yaml
   extraPortMappings:
     - { containerPort: 30606, hostPort: 6006, protocol: TCP }   # Phoenix
     - { containerPort: 30080, hostPort: 8080, protocol: TCP }   # kagent UI
   ```
   (Drop the `ingress-ready` label — no ingress controller in this model.)
7. **`cluster/phoenix/phoenix.yaml`** — Service → `type: NodePort`, set
   `nodePort: 30606` on the `ui-http` (6006) port. Leave `otlp-grpc` 4317 as
   ClusterIP-internal (in-cluster only).
8. **`cluster/kagent/values.yaml`** — set the UI service to `type: NodePort` with
   `nodePort: 30080`. **VERIFY** the kagent chart exposes `ui.service.type` /
   `nodePort` knobs (chart 0.10.4). If it does not, ship a tiny companion
   `NodePort` Service in `cluster/kagent/` and `kubectl apply` it from `install.sh`
   step 4. ← flagged open item, see §6.
9. **`cluster/install.sh`** — update the closing banner: kagent UI is now
   `http://localhost:8080` (NodePort), not a `port-forward` hint.
10. **`.devcontainer/DECISIONS.md`** — rewrite §1 (engine = **kind**, NodePort
    exposure rationale), trim §3 toolchain, add a note that `postCreate` now
    deploys the stack.
11. **Retire** `cluster/k3d-config.yaml`, the k3d branches in `create-cluster.sh` /
    `postStart.sh` / `lib.sh`, and k3d/kagent-CLI mentions in READMEs. (Low churn,
    reduces the "which engine?" confusion the board is removing.)

## 5. Verification (acceptance)

Smallest proof the fix works, run in a fresh Codespace (or `devcontainer up`):

- `postCreate` exits **0**; `kubectl get nodes` shows the kind `workshop` cluster Ready.
- `kubectl get pods -A` → Dynatrace/OTel/Tetragon/kagent/Phoenix reconciled (or
  cleanly skipped when a secret is absent — never a hard crash).
- `curl -sf localhost:6006` (Phoenix) and `curl -sf localhost:8080` (kagent UI)
  both answer from inside the Codespace.
- Re-run `postCreate.sh` by hand → still idempotent, still exits 0.

## 6. Trade-offs & open items (board input welcome)

- **First-boot time ↑ (main risk).** Deploying the whole stack on `postCreate`
  adds several minutes of `helm --wait` on a cold cluster, and a prebuild **cannot**
  cache cluster state (only the image). Mitigation: run `install.sh` non-fatally so
  partial failures don't brick the Codespace, and keep the `INSTALL_<component>=false`
  toggles. **Decision needed:** full deploy on create (per directive) vs. deploy on
  first explicit `install.sh` run. Plan assumes full deploy, as directed.
- **kind RAM > k3d.** k3d was the default precisely for memory headroom on 4c/16GB.
  kind + full stack is tighter but fits; `check-resources.sh` already warns under floor.
- **kagent UI NodePort knob** (§4.8) — needs a 5-min chart-values check; companion
  Service is the fallback. Not a blocker to approving the plan.
- **mkdocs** stays best-effort for local preview; attendees normally read the
  published site, so it is correctly out of the fatal gate.

## 7. Out of scope

Workshop content/modules, Phase 2-5 component internals, Paperclip platform source.
