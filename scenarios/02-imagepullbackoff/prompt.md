# ImagePullBackOff in workshop-faults

A workload in the `workshop-faults` namespace will not start. Ask the SRE agent to
investigate — **do not tell it the root cause**; let it gather evidence (status,
events) and reach the "Findings → Root cause → Action → Verify" conclusion.

## Drive it from the kagent UI

Open the kagent UI (`http://localhost:8080`), pick **sre-agent**, and paste:

> A deployment in the `workshop-faults` namespace is not coming up — its pod never
> becomes Ready. Investigate the workload there, find the root cause, and show me
> the exact status and events that prove it.

## Drive it over A2A (curl)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"A deployment in the workshop-faults namespace never becomes Ready. Investigate the workload there, find the root cause, and cite the exact status and events that prove it."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

## What a correct answer looks like

The agent should report the `report-renderer` pod stuck in **ImagePullBackOff**,
cite the `Failed to pull image` event with `manifest ... not found`, and name the
**bad image tag** (`busybox:v0-does-not-exist-9q9q9q`) as the cause — not an auth
problem. Grade against [`expected-diagnosis.md`](./expected-diagnosis.md).

## Inject / clean up

```bash
bash scenarios/run.sh inject  02      # apply the fault
bash scenarios/run.sh cleanup 02      # remove it (deletes the workshop-faults ns)
```
