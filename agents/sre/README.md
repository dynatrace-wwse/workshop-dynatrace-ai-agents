# agents/sre — SRE agent

A single kagent `Agent` (`sre-agent`) that **investigates** and, on request,
**operates** the workshop cluster, correlating cluster state with Dynatrace.

| Tool surface | How it is wired |
|--------------|-----------------|
| `kubectl` / k8s | `kagent-tool-server` k8s_* tools (get/describe/logs/events/apply/patch/scale/rollout/exec) |
| `k8s-networking` | `kagent-tool-server` `k8s_check_service_connectivity` |
| `dynatrace` | `dynatrace-mcp-remote` (all discovered Dynatrace tools) |

Model: `workshop-llm` (shared, `agents/mcp/00-modelconfig.yaml`).

Tool names are enumerated for least privilege: read/investigate tools plus a
focused, non-destructive-by-default operate set. No `k8s_delete_resource` is
granted — deletions are intentionally off the SRE agent's menu.

## Apply

```bash
kubectl apply -k agents/sre      # needs agents/mcp + kagent-tool-server first
kubectl -n kagent get agent sre-agent
```

(`agents/install-agents.sh` applies this in the right order.)

## Sample prompt (A2A)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"List the pods in the kagent namespace and tell me if any are unhealthy."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

Or drive it from the kagent UI (`kubectl -n kagent port-forward svc/kagent-ui 8080:8080`).
Spans land in Phoenix + Dynatrace via the OTel gateway.
