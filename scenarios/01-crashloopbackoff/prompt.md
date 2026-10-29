# CrashLoopBackOff in workshop-faults

A workload in the `workshop-faults` namespace is unhealthy. Ask the SRE agent to
investigate — **do not tell it the root cause**; let it gather evidence (status,
events, logs) and reach the "Findings → Root cause → Action → Verify" conclusion.

## Drive it from the kagent UI

Open the kagent UI (`http://localhost:8080`), pick **sre-agent**, and paste:

> A pod in the `workshop-faults` namespace keeps restarting. Investigate what is
> wrong with the workload there, find the root cause, and tell me the exact
> evidence (status, events, and logs) that supports it.

## Drive it over A2A (curl)

```bash
kubectl run a2a --rm -i --restart=Never --image=curlimages/curl:8.10.1 -n kagent \
  --command -- curl -s -m 300 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":"m1","kind":"message","parts":[{"kind":"text","text":"A pod in the workshop-faults namespace keeps restarting. Investigate the workload there, find the root cause, and cite the exact status, events, and log lines that support it."}]}}}' \
  http://kagent-controller.kagent:8083/api/a2a/kagent/sre-agent
```

## What a correct answer looks like

The agent should report the `billing-worker` pod in **CrashLoopBackOff**, cite the
non-zero **exit code (1)** from `lastState.terminated`, the `Back-off restarting
failed container` event, and the **fatal log line** (`BILLING_DB_URL is not set`)
— concluding the start command fails on launch. Grade against
[`expected-diagnosis.md`](./expected-diagnosis.md).

## Inject / clean up

```bash
bash scenarios/run.sh inject  01      # apply the fault
bash scenarios/run.sh cleanup 01      # remove it (deletes the workshop-faults ns)
```
