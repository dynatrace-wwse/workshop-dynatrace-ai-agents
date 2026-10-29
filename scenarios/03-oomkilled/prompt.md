# OOMKilled in workshop-faults

A workload in the `workshop-faults` namespace keeps dying. Ask the SRE agent to
investigate — **do not tell it the root cause**; let it gather evidence (status,
`lastState`, events) and reach the "Findings → Root cause → Action → Verify"
conclusion. This one looks like a crash loop at first glance — the discriminator is
*why* it is being killed.

## Drive it from the kagent UI

Open the kagent UI (`http://localhost:8080`), pick **sre-agent**, and paste:

> A pod in the `workshop-faults` namespace keeps getting killed and restarted.
> Investigate the workload there, determine exactly why the container is being
> terminated, and cite the evidence (container status / lastState and the
> resource limits) that supports it.

## Drive it over A2A (curl)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"A pod in the workshop-faults namespace keeps getting killed and restarted. Investigate the workload there, determine exactly why the container is being terminated, and cite the container status (lastState) and resource limits that prove it."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

## What a correct answer looks like

The agent should report the `image-resizer` container terminated with
`lastState.terminated.reason: **OOMKilled**` and **exitCode 137**, and attribute it
to the 32Mi memory limit being far below what the workload allocates — explicitly
distinguishing an OOM kill from a plain application crash. Grade against
[`expected-diagnosis.md`](./expected-diagnosis.md).

## Inject / clean up

```bash
bash scenarios/run.sh inject  03      # apply the fault
bash scenarios/run.sh cleanup 03      # remove it (deletes the workshop-faults ns)
```
