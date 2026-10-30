# Open questions for Henrik

> **How we work together (owner decision, 2026-10-30):** this repository is the
> source of truth for the enablement edition. Henrik works from a **fork** and
> sends pull requests; changes we need land here directly, and Henrik pulls them
> into his fork. This file is the list of open questions — there are no separate
> GitHub issues.

Raised while migrating the workshop to the Dynatrace enablement framework
(2026-10-30). Each item: context → what is missing → a suggested answer. Nothing
here blocks the migration; each one is a decision that belongs to the author.

## 1. License

**Context.** The original repository has no `LICENSE` file. This copy is private
in `dynatrace-wwse` with full history and credits you in the README and on the
landing page.
**Missing.** Terms under which the content may be published and reused (the
enablement trainings are public).
**Suggested.** Apache-2.0, like the rest of `dynatrace-wwse`; add it upstream so
both copies agree.

## 2. Which LLM do learners get?

**Context.** The agents are tuned for DeepSeek. The Enablement App provisions
Dynatrace tokens per learner, but has no way to hand out a third-party LLM key —
and a shared key in a workshop would be spent by everyone. The migration
therefore falls back to **Ollama in the cluster** (`qwen2.5:3b`) when
`DEEPSEEK_API_KEY` is absent. Measured on 4 cores: an SRE-agent answer takes
1–5 min and pins all 4 cores; `qwen2.5:1.5b` answers in ~20 s but invents pod
names (graded FAIL on scenario 01), `3b` found the right root cause.
**Missing.** Your call on the default experience in a live workshop.
**Suggested.** Keep Ollama as the self-paced default; for instructor-led
deliveries use a trainer-provided, budget-capped DeepSeek key set per session.
Could module 9 use the Ollama-vs-DeepSeek gap as its "model choice" lesson?

## 3. Tetragon cannot run in the Enablement App runtime

**Context.** The App runs each learner in a Sysbox container, which does not
allow BPF map creation: Tetragon crash-loops with `map create: operation not
permitted`. `checkTetragon` passes with a warning there; in a Codespace it runs.
**Missing.** A module 5 path that teaches runtime security without eBPF in the
learner's container.
**Suggested.** Mark the Tetragon half "Codespace only" and keep Agent Sandbox
(works everywhere) as the graded part; or show recorded Tetragon events.

## 4. The local Dynatrace MCP server is deprecated

**Context.** `@dynatrace-oss/dynatrace-mcp-server@2.1.2` prints a deprecation
notice ("Last release: v2.1.2") and points to the **remote** Dynatrace MCP server
or dtctl. Without a platform token it exits, and kagent then fails *every* call
of the agent (not just Dynatrace ones) — the migration drops the Dynatrace tool
block when no token is present.
**Missing.** A decision on the long-term tool server.
**Suggested.** Move the SRE agent to the remote Dynatrace MCP server
(`RemoteMCPServer` with the tenant's MCP URL + platform token) — one less pod and
no npx cold start (we measured the first call timing out at 60 s).

## 5. OTel gateway did not degrade without credentials

**Context.** The collector comment said a missing Dynatrace secret degrades
gracefully; in fact the `otlphttp/dynatrace` exporter with an empty endpoint
fails validation and the gateway crash-loops, taking Phoenix traces with it.
**Fixed in the migration** by removing the exporter (marked block) when no
tenant is present. **Suggested:** take the same change upstream.

## 6. `ModelConfig` used a field kagent 0.10 does not have

**Context.** `agents/mcp/00-modelconfig.yaml` set `apiKeySecretRef`; the
`v1alpha2` field is `apiKeySecret`, so the key was silently ignored.
(`cluster/kagent/values.yaml` is fine — the chart maps its `apiKeySecretRef`
value onto `apiKeySecret`.) **Fixed in the migration.** Suggested: upstream too.

## 7. Agent Sandbox is installed from `main`

**Context.** `AGENT_SANDBOX_REF="main"` in `cluster/versions.env` — every
environment installs whatever `kubernetes-sigs/agent-sandbox` has on `main`.
**Missing.** A pinned release.
**Suggested.** Pin to the latest tag you have tested.

## 8. dt-evals token scopes

**Context.** `evals/dt-evals` documents a `dt0c01` token with `storage:*` scopes,
which are platform (OAuth/`dt0s16`) scopes, not classic token scopes.
**Missing.** Which token type dt-evals 0.3.4-alpha actually needs.
**Suggested.** If platform: reuse `DT_PLATFORM_TOKEN` (now minted per learner,
scopes in `.devcontainer/yaml/dt-tokens.yaml`) and drop the separate token.

## 9. BMAD crew needs a writable demo repo

**Context.** The crew's write demo needs a fine-grained `GH_PAT` on one repo;
the App does not provide one, so learners there run the crew read-only.
**Missing.** A demo-repo story for the App.
**Suggested.** A template repo the learner forks, with the PAT as an optional
step — or keep the write demo instructor-only.

## 10. Scenario 12 now runs on AstroShop Lite — but is not intermittent

**Context.** Scenario 12 now deploys **AstroShop Lite** (`deployApp
astroshop-lite`, codespaces-framework 1.20.1, built from your `opentelemetry-demo-light`
and published as `ghcr.io/dynatrace-wwse/astroshop-lite/*:0.2.0`, pinned by digest; payment
spans now join the checkout trace) in namespace `astroshop-lite`. The services export
to the workshop's OTel gateway. Inject and cleanup work: the faulty backend joins
the Service (2 endpoints) and leaves cleanly.
**Missing.** `validate-live.sh` measured **0/38 failed** frontend requests: the
frontend's gRPC (HTTP/2) channel stays pinned to the healthy product-catalog pod,
which is the stickiness case your validator already flags as "ESCALATE". A
restarted frontend would pin to one pod at random, giving 0% or 100% errors,
never a fraction.
**Suggested.** Inject the fault *inside* the one product-catalog pod (an env
flag or feature flag that fails N% of calls) instead of adding a second
endpoint. It is intermittent whatever the connection pinning. Until then,
scenario 12 stays optional and ungraded.

## 11. Upstream keeps moving

**Context.** Henrik merged PRs #30–#33 upstream on the day of the import; they were
merged into the migration before it landed. The docs here are restructured
(numbered pages, checks, solutions), so upstream content no longer applies as-is.
**Decided.** New content lands here via PRs from Henrik's fork (see the note at
the top). **Open for Henrik:** whether the original repository should point here.
