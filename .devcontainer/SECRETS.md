# Secrets contract

> **Never commit secrets.** They arrive as environment variables: injected per
> learner by the Dynatrace Enablement App (Orbital), or set as Codespace secrets.
> Check presence by name only — `variablesNeeded NAME:false …` never prints a value.

## Variables

| Variable | Who provides it | Used by | Without it |
|---|---|---|---|
| `DT_ENVIRONMENT` | App: injected · Codespace: secret | Operator, OTel gateway, Dynatrace MCP | Dynatrace steps report *not applicable*; everything else runs |
| `DT_OPERATOR_TOKEN` | App: minted (`dt-tokens.yaml` `operator`) | `dynatraceDeployOperator` / k8s-only DynaKube | no Kubernetes monitoring |
| `DT_INGEST_TOKEN` | App: minted (`ingest`) | OTel gateway → Dynatrace OTLP (`Api-Token`, or `Bearer` for a `dt0s16`) | gateway exports to Phoenix only |
| `DT_PLATFORM_TOKEN` | App: minted (`platform`, `kind: platform`) | Dynatrace MCP server (SRE agent), dtctl (module 9) | SRE agent keeps its Kubernetes tools only |
| `DT_HOSTGROUP` | App: injected | names the cluster `<repo>-<session>` → per-learner data isolation | `getDtSessionId` generates one |
| `WORKSHOP_DISPENSER_URL` + `WORKSHOP_ROOM_PASSWORD` | optional, Codespace secrets — **both** given by the workshop host | `.devcontainer/dispense-llm.sh` exchanges the room password for a per-attendee, budget-capped model-proxy key (written to the gitignored 0600 `.workshop-llm.env`); agents, Phoenix and the eval judge then go through the host's proxy | `DEEPSEEK_API_KEY` if set, else **Ollama**. Only one of the two set → fail-closed, same fallback |
| `WORKSHOP_LLM_BASE_URL` + `WORKSHOP_LLM_MODEL` + `WORKSHOP_LLM_API_KEY` | optional, Codespace secrets | any OpenAI-compatible endpoint, directly — a LiteLLM proxy (Henrik's home lab, a shared LLM box) with a per-attendee, budget-capped key | next row |
| `DEEPSEEK_API_KEY` (or `LLM_API_KEY`) | optional, Codespace secret | `<prefix>-workshop-llm` ModelConfig → DeepSeek directly | **Ollama** in-cluster (`qwen2.5:3b`) |
| `GH_PAT` | optional, Codespace secret | GitHub MCP for the BMAD crew's write demo — fine-grained, ONE demo repo (Contents/Issues/Pull requests RW) | BMAD crew runs read-only |
| `WORKSHOP_PREFIX` | optional, Codespace secret (not secret — Codespaces only prompts for declared names) | your label: agent names `<prefix>-sre-agent`…, span attribute `workshop.attendee` | derived: GitHub user → Enablement-App learner id → `workshop`; an invalid value is normalised, never rejected |
| `OPENAI_API_KEY` in `evals/.env` | optional | Phoenix LLM-as-a-judge (module 8 parts A/B) | use part C (deterministic) |

Which LLM the agents get, in order: the **room-password proxy** (when the host
gave you both values) → a **direct endpoint + key** (`WORKSHOP_LLM_BASE_URL` /
`WORKSHOP_LLM_MODEL` / `WORKSHOP_LLM_API_KEY`, or `DEEPSEEK_API_KEY` for DeepSeek)
→ the **in-cluster Ollama** model. Tool calling needs a capable model: the MCP
tool set is large, so prefer ≥ 30B on a shared box; `qwen2.5:3b` proves the
wiring only. The Enablement App injects none of these, so it always runs on Ollama.

## Room-password model proxy (optional)

Ported from Henrik's upstream (ISI-6996/7000). For an instructor-led delivery the
host runs a LiteLLM proxy that holds the real DeepSeek key; attendees never see
it. The dispenser URL is **not** in this repository — it is rotatable and handed
out with the room password. The contract and the guarantees of the client:

- `GET <WORKSHOP_DISPENSER_URL>` with header `X-Room-Password`, **https only**,
  TLS verified, no redirects followed, 30 s timeout. The password is passed to
  curl through a 0600 temp file, never on the command line.
- `200 {"proxy_url","virtual_key","model"}` — every field is validated against a
  strict character set before it is written; anything else (non-JSON, http
  proxy URL, missing key) fails closed and writes nothing. Response bodies are
  never printed.
- The key file is loaded by every terminal only if it is a regular file owned
  by you and not group/world-writable.
- Rotated password: run `dispenseLlmKey` (mints a new key and re-applies the agents).

Facilitators: [`HOST-RUNBOOK.md`](HOST-RUNBOOK.md).

The Dynatrace token scopes are declared in
[`yaml/dt-tokens.yaml`](yaml/dt-tokens.yaml); Orbital mints exactly those.

## Codespace

GitHub → **Settings → Codespaces → Secrets**, scoped to
`dynatrace-wwse/workshop-dynatrace-ai-agents`. Secrets apply to codespaces created
*after* they are set — rebuild the container after adding one.
