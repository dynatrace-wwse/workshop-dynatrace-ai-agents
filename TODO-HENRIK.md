# Open questions for Henrik

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

## 10. Scenario 12 uses opentelemetry-demo-light

**Context.** The enablement framework is adding **AstroShop Lite** (built from
your `opentelemetry-demo-light` images) as a framework app (`deployApp
astroshop-lite`, framework 1.20.0). Scenario 12 still installs your chart
directly (`deployOtelDemoLight`).
**Suggested.** Switch scenario 12 to the framework app once 1.20.0 is released,
so one copy of the demo is maintained.

## 11. Upstream keeps moving

**Context.** You merged PRs #30–#33 on the day of the import. The migration
branch was merged with your `main` at the time it was opened, but the docs were
restructured (renamed `NN-*.md`, front matter, checks).
**Suggested.** Agree where content changes land from now on — here (then the
original can point to it) or upstream with a periodic sync.
