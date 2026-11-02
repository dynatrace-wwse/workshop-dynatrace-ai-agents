#!/usr/bin/env bash
# gen-optimization-json.sh — generate UI-importable JSON for the Phase-5
# optimization artifacts (ISI-6993).
#
# Users get two deploy paths for the same artifacts:
#   • dtctl  — apply the YAML in cluster/dynatrace/optimization/ (CI/GitOps path)
#   • UI      — upload the JSON under docs/assets/optimization/ (import-in-tenant path)
#
# The JSON is ALWAYS generated from the dtctl YAML — never hand-maintained — so
# the two paths can never drift. CI runs this and `git diff --exit-code`s the
# output (see .github/workflows/optimization-json.yaml); a YAML edit that forgets
# to regen fails the build.
#
# Mapping (what the Dynatrace UI import expects):
#   notebook  → the portable document `content` (defaultSegments/Timeframe/sections)
#   dashboard → the portable document `content` (version/variables/tiles/layouts)
#   workflow  → the whole workflow-definition doc (title/description/tasks/trigger)
#
# Usage: scripts/gen-optimization-json.sh        # regenerate all three JSON files
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/cluster/dynatrace/optimization"
out="$repo_root/docs/assets/optimization"

command -v yq >/dev/null 2>&1 || { echo "error: yq (mikefarah) not found on PATH" >&2; exit 1; }

mkdir -p "$out"

# notebooks + dashboard: emit only the portable document `content`
yq -o=json '.content' "$src/ai-agent-workflow-steps.notebook.yaml" \
  > "$out/ai-agent-workflow-steps.notebook.json"
yq -o=json '.content' "$src/ai-agent-optimization-before-after.notebook.yaml" \
  > "$out/ai-agent-optimization-before-after.notebook.json"
yq -o=json '.content' "$src/ai-agent-optimization.dashboard.yaml" \
  > "$out/ai-agent-optimization.dashboard.json"

# workflow: the whole definition is the importable document
yq -o=json '.' "$src/ai-agent-optimization.workflow.yaml" \
  > "$out/ai-agent-optimization.workflow.json"

echo "generated:"
for f in \
  ai-agent-workflow-steps.notebook.json \
  ai-agent-optimization-before-after.notebook.json \
  ai-agent-optimization.dashboard.json \
  ai-agent-optimization.workflow.json; do
  echo "  docs/assets/optimization/$f"
done
