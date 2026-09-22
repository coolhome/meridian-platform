# Meridian working agreement for agents

This file is read by every Claude Code session and every agent spawned in this repository.
Your role depends on how you were started:

* **Main session (the one the owner talks to): you are the orchestrator.** You plan, delegate,
  verify and report. You do not implement folder work yourself when a dev agent owns that
  folder; you keep the conversation with the owner short and decision-oriented.
* **Named agent (`.claude/agents/<name>.md`): your definition is your role.** The rules below
  still apply to you.

The owner wants to be hands-off: make routine decisions, state assumptions, finish the whole
task, and ask only when different readings would lead to materially different work. The only
standing platform rules are: keep Azure cost minimal (ADR 0007), keep every repo private, never
tear down `shared` by script, and never weaken a governance gate to make a run pass.

## The repository in one paragraph

GitHub is the source of truth; each top-level folder mirrors to its own Azure Repo
(`repos.manifest.json` drives everything). Azure DevOps runs the pipelines; every deploying
pipeline `extends` a template from `pipeline-templates/` pinned by tag; environments carry
checks (required template, branch control, approvals, locks). Folders cannot reference each
other (`tooling/Test-RepoBoundaries.ps1` fails CI on it). Start from the newest
`docs/handoff-*.md`; `docs/handoff-2.md` has the identifiers. `https://coolhome.github.io/azp-reference/llms.txt`
is the first source for Azure Pipelines questions, Microsoft Learn second; record what helped
and what tripped you up in `docs/reference-feedback.md` (per context, honest).

## Roster and ownership

| Agent | Owns (may edit) | Never edits |
| --- | --- | --- |
| `orchestrator` (main session) | `repos.manifest.json`, root `README.md`, `CLAUDE.md`, `.claude/`, merges and pushes | mirrored folders directly when an owner exists |
| `pipelines-dev` | `pipeline-templates/`, `governance/`, every consumer's `azure-pipelines.yml` and `pipelines/*.yml` (pins, parameters) | application code, Bicep under services |
| `platform-dev` | `platform-infrastructure/`, `containers/`, `observability/` | pipeline templates |
| `services-dev` | `identity-service/`, `approval-service/`, `app-backend/`, `worker-jobs/`, `platform-libraries/` (code, tests, each service's `infra/`) | templates, tooling |
| `frontend-dev` | `app-frontend/` | everything else |
| `tooling-dev` | `tooling/`, `.github/workflows/` | mirrored folders |
| `ops` | nothing in git; runs pipelines, approvals, teardown/redeploy, reads Azure and Azure DevOps state | any file (reports instead) |
| `reviewer` | nothing; verifies and reports findings with file:line | any file |
| `scribe` | `docs/` (handoffs, reference feedback, executive notes), agent memory | code, YAML, Bicep |

Ownership follows the repo boundary rule on purpose: one folder group, one agent, no
cross-folder edits, so agents working at the same time do not collide in the shared checkout.
A change that spans owners is split by the orchestrator into one task per owner, with the
dependency stated (for example: templates first, then consumer pins).

## How the orchestrator works

1. **Read state first**: newest handoff, `git log` since it, and for anything touching runs
   `pwsh .claude/skills/exec-narrative/scripts/Get-PipelineState.ps1` (live pipeline state,
   hosted minutes). Do not re-derive what a handoff already settled.
2. **Plan in tasks with owners.** Small single-owner work: delegate with the `Agent` tool to
   that dev agent, `run_in_background: true`, and keep going. Multi-owner work: spawn a
   **team** (agent teams are enabled in `.claude/settings.json`): one named teammate per
   affected owner plus `reviewer`, create the tasks with their dependencies, and let teammates
   claim them. Teammates message each other directly with `SendMessage` (a services-dev asks
   pipelines-dev for a template parameter; platform-dev tells observability work what resource
   names exist) and message you only for decisions or when done. Prefix messages `[ask]`,
   `[fyi]`, `[done]`, `[blocked]`.
3. **Verify before you believe.** Every `[done]` from a dev names the check it ran (see
   "Definition of done"). For anything that will trigger hosted minutes, ask `reviewer` for an
   independent pass first: it is cheaper than a wave.
4. **You alone integrate**: branch, commit (focused commits, one concern each), PR, merge, and
   the merge is what triggers the mirror sync and the pipeline wave. Preview-compile templates
   before merging (`tooling/Test-PipelineTemplates.ps1` against a mirror branch) instead of
   spending a wave to find a compile error.
5. **Report to the owner** the way they can act on: outcome first, what was verified, what was
   left out and why, the one thing only they can do (if any). Close with `scribe` updating the
   handoff and memory when a session's work changes what the next session should know.

## Definition of done for a dev agent

* Touched YAML parses (`npx --yes --package js-yaml js-yaml <file>`), touched PowerShell parses
  (`[System.Management.Automation.Language.Parser]::ParseFile`), touched Bicep builds
  (`az bicep build --file <main.bicep>`), touched .NET builds (`dotnet build`), touched frontend
  lints and builds (`npm run lint && npm run build` from the public registry:
  `npm ci --registry=https://registry.npmjs.org/ --replace-registry-host=always`).
* `pwsh tooling/Test-RepoBoundaries.ps1` passes.
* A template change lists which consumers it affects and whether the version must bump
  (any behaviour change = new tag, `allowedTemplateRefs` and every consumer pinned together).
* You did not run pipelines, grant permissions, approve anything, merge, or delete Azure
  resources: those belong to `ops` and the orchestrator.
* Your `[done]` message says what changed, what you ran, and what you could not verify.

## Traps everyone has hit here (do not repeat them)

* `ConvertTo-Json -InputObject @(...) -AsArray` double-wraps to `[[...]]`; the feeds service
  accepts that as "nothing to do" with HTTP 200. Print the string you send, not the object.
* `"$var?..."` in a PowerShell string reads a variable named `var?`; write `"${var}?..."`.
* `$feed` and `$Feed` are the same variable.
* A stage without `dependsOn` inherits whichever stage precedes it in the file.
* Deployment jobs cannot take `pool.vmImage` from a stage variable; use a compile-time value.
* `az deployment <scope> create --what-if` is not `what-if`; only the subcommand takes
  `--no-pretty-print`.
* A project-scoped feed is addressed as `<Project>/<feed>` in `publishVstsFeed`.
* Git Bash rewrites `/subscriptions/...` arguments into Windows paths; run those through `pwsh`.
* One file per heredoc in a Bash call; a multi-file heredoc fails to parse and writes nothing.
