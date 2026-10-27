# Phase 5 · AI Agent Optimization artifacts (ISI-6720)

Dynatrace dashboard + notebook that turn the kagent crew's `gen_ai.*` spans into
the three optimization signals from **[`docs/06-optimize.md`](../../../docs/06-optimize.md)**:
token spend, unused tools, and inefficient loops — plus a reproducible
**before/after** story.

| File | What it is | Deploy |
|------|------------|--------|
| `ai-agent-optimization.dashboard.json` | Dashboard: spend ranking, input:output ratio, tools-used, loop detection, token trend | `bash <skill>/scripts/deploy_dashboard.sh ai-agent-optimization.dashboard.json` |
| `ai-agent-optimization-before-after.notebook.json` | Notebook: the observe → find → change → re-measure → keep/revert walkthrough | `dtctl create notebook -f ai-agent-optimization-before-after.notebook.json` |

`<skill>` = the `dt-app-dashboards` skill directory.

## Prerequisites

- A Dynatrace tenant receiving OTLP from the Phase 2/3 cluster (the kagent crew
  emits `gen_ai.*` spans under `service.namespace == "kagent"`).
- `dtctl` authenticated against that tenant
  (`dtctl config use-context <your-context>`; verify with `dtctl auth whoami`).

## Deploy

```bash
# point dtctl at the workshop tenant
dtctl config use-context <your-context>

# dashboard (validates DQL, then applies)
bash /path/to/dt-app-dashboards/scripts/deploy_dashboard.sh \
  cluster/dynatrace/optimization/ai-agent-optimization.dashboard.json

# notebook
dtctl create notebook \
  -f cluster/dynatrace/optimization/ai-agent-optimization-before-after.notebook.json
```

Both JSON files carry **no `id`** — the server assigns one on first deploy. To
*update* a dashboard later, download it first
(`dtctl get dashboard <id> -o json --plain > file.json`), edit, and redeploy —
this preserves any UI edits. See the `dt-app-dashboards` skill.

## Reference deployment (ISI-6720)

First deployed to `oat05854.dev.apps.dynatracelabs.com`:

- Dashboard `70385f20-36c4-4a82-bf33-eef1a2d03855`
- Notebook `600cc6ab-8874-40ad-8e80-8a9c24806084`

All DQL in both artifacts was validated against live crew telemetry before
deploy. The queries carry no hard-coded time filter — the dashboard time-picker
and the notebook section timeframes drive the window (that is how you switch
between the *before* and *after* windows).
