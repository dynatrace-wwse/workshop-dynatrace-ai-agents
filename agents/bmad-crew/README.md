# agents/bmad-crew — BMAD software-building crew

Six kagent `Agent`s that run a full software-delivery chain on GitHub, adapted
from [isItObservable/Kagent `manifests/bmad-crew`](https://github.com/isItObservable/Kagent/tree/main/manifests/bmad-crew).

| Agent | Role | GitHub access (per-agent `toolNames`) |
|-------|------|----------------------------------------|
| `bmad-analyst` (Mary) | Requirements → issues | issues RO/RW (scope) |
| `bmad-pm` (John) | Milestone & planning | issues RW, repo RO |
| `bmad-architect` (Winston) | Design → dev-task issues | issues RW, repo RO |
| `bmad-developer` (Amelia) | Code → branch → PR | repo RW, PRs RW, issues RO |
| `bmad-qa` (Quinn) | PR review | PRs RW, issues RW |
| `bmad-orchestrator` (BMad Master) | Conducts the chain over A2A | issues RO; delegates to the five |

**No agent is granted a merge tool** — merge stays a human/CI step. The "crew"
is the orchestrator's `type: Agent` reference graph (kagent has no Team/Ensemble
CRD).

## Workshop deltas vs upstream

- **Model**: every agent uses the shared **`workshop-llm`** ModelConfig
  (**DeepSeek**, `agents/mcp/00-modelconfig.yaml`) instead of the upstream
  Mac-Studio Ollama one.
- **GitHub MCP**: provided once by `agents/mcp/10-github-mcp.yaml`
  (`github-mcp-remote`); this folder no longer ships its own copy.

## Apply

```bash
export GITHUB_PAT='<fine-grained PAT, demo repo only: Contents/Issues/PRs RW>'
bash ../install-agents.sh                     # applies mcp + sre + this crew
# or, once agents/mcp is applied:
kubectl apply -k agents/bmad-crew
kubectl -n kagent get agents -l app.kubernetes.io/part-of=bmad-crew
```

## Run the demo (A2A)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"Build a simple Todo app in <owner>/<repo>. Run the full BMAD workflow: scope requirements, plan, design, implement on a branch, open a PR, review it."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/bmad-orchestrator
```

Expected: requirement issues, a milestone, dev-task issues, a feature branch, a
PR, and a QA review — with the live PR URL in the orchestrator's final answer.
Multi-hop runs can take a few minutes; keep the client timeout generous.
