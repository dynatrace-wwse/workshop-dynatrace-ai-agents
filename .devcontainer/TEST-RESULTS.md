# ISI-6835 Codespace remediation — acceptance results (ISI-6844)

Verifier: `.devcontainer/test/verify-isi6835.sh` (maps 1:1 to `ISI-6835-remediation-plan.md` §5 / §4).

- **STATIC (A1–A12)** — contract checks against the merged implementation (PR #13 / `main`). Run anywhere; results below.
- **LIVE (L1–L5)** — §5 acceptance proper; requires a fresh Docker-in-Docker GitHub Codespace. Auto-SKIP outside one. Append with:
  `bash .devcontainer/test/verify-isi6835.sh --markdown .devcontainer/TEST-RESULTS.md`

### ISI-6835 acceptance — `verify-isi6835.sh` (PASS=12 FAIL=0 SKIP=5)

| ID | Gate | Result | Detail |
|----|------|--------|--------|
| A1 | postCreate required gate excludes mkdocs | PASS | required loop: for t in kubectl helm kind dtctl node; do |
| A2 | mkdocs/dt-evals soft-warn | PASS | soft warn present |
| A3 | no kagent-CLI reference in postCreate | PASS | none |
| A4 | postCreate deploys cluster/install.sh | PASS | 27:#    (e.g. a missing secret) must never brick the Codespace — install.sh de |
| A5 | lib.sh defaults CLUSTER_TOOL=kind | PASS | default=kind |
| A6 | devcontainer.json CLUSTER_TOOL=kind | PASS | kind |
| A7 | k3d engine retired | PASS | no k3d-config, no residual k3d refs in .devcontainer/cluster |
| A8 | kagent CLI removed from install-tools | PASS | none |
| A9 | Dockerfile drops K3D/KAGENT ARGs | PASS | none |
| A10 | kind-config NodePort mappings | PASS | 30606->6006, 30080->8080; no ingress-ready |
| A11 | phoenix Service NodePort 30606 | PASS | type NodePort + nodePort 30606 |
| A12 | kagent UI NodePort 30080 | PASS | exposed via values.yaml |
| L1 | live §5 check | SKIP | static-only run |
| L2 | live §5 check | SKIP | static-only run |
| L3 | live §5 check | SKIP | static-only run |
| L4 | live §5 check | SKIP | static-only run |
| L5 | live §5 check | SKIP | static-only run |
