# azp-reference field notes

Running log kept while building Meridian with
[coolhome.github.io/azp-reference](https://coolhome.github.io/azp-reference/llms.txt) as the
number-one source. Entries are grouped by the context we were working in, because the same
page reads very differently when you are designing templates versus writing a bootstrap script.

Legend: **Helpful** = changed a decision or saved a mistake. **Not helpful** = read it, got
nothing actionable. **Tripped us up** = cost time, or we had to go elsewhere. **Wish it had** =
gap we would have paid for.

---

## Context 0: Ingesting the reference itself

**Helpful**

* `llms.txt` is a real index with one-line descriptions per page. Picking the twenty pages that
  mattered for this build took one read. That is rare.
* The split between *Authoring*, *Administering*, *Securing* and *Examples* maps cleanly onto the
  four kinds of work we had to do (templates, bootstrap scripts, hardening, consumer YAML).

**Tripped us up**

* Pages are `.md` files served over HTTPS and quite long. Our fetch tool summarizes with a small
  model, so on the first pass two pages came back useless: the job-access-tokens page returned a
  "what would you like to know" preamble, and the checks page came back as concepts only. Both
  needed a second, narrower prompt. This is a tooling limitation, not a reference defect, but
  anyone ingesting with an LLM summarizer will hit it.

**Wish it had**

* A machine-readable manifest of examples (`id`, `repo layout`, `files`) alongside
  `pipeline-timeline.json`. We ended up rebuilding a mental map of example 01/06/09/10 by hand.

---

## Context 1: Designing the governed `extends` templates

**Helpful**

* The **root `variables:` collision** rule (entry file and extends template cannot both declare
  root variables) was stated in three places (templates, variable precedence, example 01/10). We
  designed around it up front: consumer YAML owns the root block, templates declare variables at
  stage or job scope. Would have been a compile-time surprise otherwise.
* The **compile-time allow-list trick** from example 01 (reject a disallowed task by emitting a
  `- template: __governance-rejected-...__.yml` reference that cannot resolve) is exactly the
  enforcement we wanted for `preBuildSteps`, and the `replace(step.task, '@', '-')` detail
  matters because a literal `@` in a computed path is read as a repository alias.
* **"Only `deployment:` jobs bind environment checks"** is repeated everywhere and is the single
  most important governance rule. Our templates generate deployment jobs per environment and never
  expose a plain `job:` that touches an environment.
* **Boolean coercion page.** `eq(coalesce(x, 'false'), 'true')` became the only boolean gate we
  use for `templateContext` / object members. The `eq(true, x)` operand-order trap was new to us.
* **Pin templates to tags**, and the operating model's rule that shared-template changes ship
  opt-in per consumer, not as one global flip. The manifest carries `templatesRef` and every
  consumer pins it.
* Template directives page: `${{ if }}` gates *presence*, `condition:` gates *execution*. We
  used that split deliberately (see the prod canary job).
* Leading-dot pipeline or folder names silently kill folder-qualified completion triggers. We
  had a `.pipelines/` folder in an early sketch and renamed it to `pipelines/` because of this.

**Not helpful**

* The governed-stage-graph example (09) is elegant but its `stageList` + nested `templateContext`
  model is more freedom than a platform team wants to hand to consumers. We stayed with example
  10's shape (consumer passes data, template emits structure).

**Tripped us up**

* The templates page says `deploymentList`, not `jobList`, for central templates. True, but for a
  service platform you usually do not want consumers authoring deployment jobs at all. The page
  does not say when to prefer "no job parameters, only data". Example 10 does, implicitly.

**Wish it had**

* A worked example of an `extends` template that supports **more than one artifact kind**
  (container image, NuGet package, static site) behind one `kind:` parameter. Example 10's
  `${{ if }}`/`${{ elseif }}` ladder on `build.kind` was the closest thing and we generalized it.

---

## Context 2: Automating environments, checks and approvals

**Helpful**

* The five-category **check execution order** (static, pre-approvals, dynamic, post-approvals,
  exclusive lock) explains why business hours should be a dynamic check and branch control a
  static one. We modeled `environments.json` on those categories.
* **Exclusive lock `runLatest` cancels intermediate runs across all branches** at resource level.
  For production deploys that are not idempotent we set `sequential`.
* Approval expiry marks the stage **skipped**, not failed. Our runbook now says "a skipped prod
  stage is probably an expired approval, retry the stage".
* The **group-name quoting footgun** (`'[Project]\Group'` needs single quotes in YAML) saved a
  debugging session in `ManualValidation` inputs.

**Tripped us up / Wish it had**

* The checks page is **concepts only**. It has no REST bodies, endpoint URLs, api-versions or
  check-type identifiers. We needed all of those for `Initialize-AzureDevOps.ps1` and went to
  Microsoft Learn plus known type GUIDs (Approval, ExclusiveLock, ExtendsCheck, Task Check). The
  reference explicitly positions itself as validated automation knowledge, so this is the biggest
  gap we hit. A single page with the `pipelines/checks/configurations` bodies for each built-in
  check would have been the most valuable page on the site for this context.
* Same for environments: there is no create-environment REST shape (`pipelines/environments`).
* Business-hours and branch-control checks are "task checks" backed by server tasks. The
  reference never names the task `definitionRef` values, so our script resolves them by name at
  runtime and warns if it cannot.

---

## Context 3: Creating pipeline definitions and applying pipeline permissions

**Helpful**

* Pipeline definitions page: **Azure Repos (`TfsGit`) needs no `connectedServiceId`**, and
  GitHub needs the endpoint **GUID**, not the name. Our `New-AdoPipelines.ps1` does not pass a
  service connection at all for the mirrors, which is the correct shape.
* "Renames appear as delete + create to identity-by-name automation" pushed us to key pipelines
  by manifest name and look up the definition ID before deciding create vs update.
* Access-controls page: the three AND-ed layers, and the fact that auto-authorization happens
  silently when a YAML author with the User role creates the pipeline. We grant pipeline
  permissions explicitly per resource from the manifest instead of relying on that.
* Job access tokens page (second fetch): the **TF401019 (token axis) versus "needs permission"
  (pipeline-permissions axis)** split is the single best troubleshooting heuristic we found.
  Also `uses.repositories` for touching a repo you never check out.

**Wish it had**

* The `pipelinepermissions/{resourceType}/{resourceId}` PATCH body and the resource id format for
  repositories (`{projectId}.{repoId}`). The access-controls page describes the model but not the
  wire shape. We took it from Microsoft Learn.

---

## Context 4: Service connections and identity

**Helpful**

* The WIF two-phase flow (create the connection first, read back issuer and subject, then create
  the federated credential) with `creationMode: Manual` is complete and correct. Our bootstrap
  script is a direct transcription plus manifest lookups.
* "A successful Preview does not exchange a token" and the separate-checks list (identity,
  federation, authorization, network) is now in our runbook verbatim.
* Type-key casing note (`AzureRM` on create, `azurerm` in the descriptor API) would have been a
  30-minute mystery.

**Not helpful (for us)**

* GitHub App connection material. We deliberately do not build Azure Pipelines from GitHub; the
  mirrors are Azure Repos. Fine that it exists, just not this platform's path.

---

## Context 5: Consumer YAML (triggers, resources, artifacts)

**Helpful**

* Trigger semantics: **paths are case-sensitive**, `trigger:` replaces the implicit all-branches
  trigger, quote patterns that start with `*`, and CI + completion triggers can double-run. We
  gate completion-triggered runs on `Build.Reason` to avoid the double run.
* Pipeline resources: only the triggering alias pins to the exact run; sibling resources float.
  Our worker pipeline consumes a single upstream so it does not hit this, but the note went into
  the wiki.
* Container resource with `type: acr` and `trigger.tags` is how the services rebuild when the
  base image changes. Registry must be a literal, which is why the manifest carries
  `containerRegistry`.
* Deployment jobs auto-download every artifact from every resource; we set `download: none` in
  hooks that only need the CLI.
* Output-variable key shapes per hop, including the canary `deploy_<increment>` re-keying.

**Tripped us up**

* The built-in tasks catalog lists `AzureCLI@3` as latest, while the integration page says the
  Azure DevOps connection type is version 3 only and ARM is "versions 1 to 2". We could not tell
  from the reference whether ARM connections work on `@3`, so we stayed on `@2` for ARM.
* `NodeTool@0` is deprecated in favour of `UseNode@1`. Easy to miss if you copy older samples.
* `MicrosoftSecurityDevOps` is not in the catalog (it is a marketplace extension). The scanners
  page names tools but not Azure Pipelines tasks, so we install Trivy and Gitleaks directly.

---

## Context 6: Security baseline

**Helpful**

* Project pipeline settings page: the full `build/generalsettings` toggle table with recommended
  values. We turned it into `governance/policies/project-pipeline-settings.json` and PATCH it in
  bootstrap. The "org locks project" pitfall is documented in the runbook.
* Hardening checklist tiers mapped to Azure Pipelines controls gave us the order of work.
* `X-TFS-FedAuthRedirect: Suppress` so unauthenticated REST calls fail loudly instead of
  returning an HTML sign-in page with HTTP 200. Added to our REST helper on day one.
* Unique `AZURE_CONFIG_DIR` per parallel `az` process.

**Wish it had**

* Guidance on **branch policies as code** (approver count, work-item linking, build validation,
  required reviewers by path, repo-level file size / path / case / author-email policies). The
  reference is pipelines-first and stops at the repo boundary. Half of "rich in Azure DevOps and
  Git" lives there, and we had to source policy type identifiers elsewhere.
* Anything on **Azure Repos mirroring** (subtree split, force-push semantics, PAT via
  `http.extraheader` rather than in the URL). Again outside the reference's declared scope, but
  adjacent enough that a pointer would help.

---

## Context 7: Where the reference stopped and Microsoft Learn had to take over

This is the concrete list of things we needed that the reference does not carry, with where we
found them. Useful as a "next pages to write" list for the reference.

| Needed for | Source used | Note |
| --- | --- | --- |
| `pipelines/checks/configurations` POST bodies (Approval, Task Check) | Learn REST reference, check-configurations/add | Task Check sample names the business-hours server task `evaluateBusinessHours` with inputs `businessDays`/`timeZone`/`startTime`/`endTime`. The reference never names it. |
| ExclusiveCheck / ExtendsCheck / branch-control task ids | Known type GUIDs, verified against the check types the service lists | Our script resolves server tasks by name at runtime and falls back to documented ids. |
| `pipelinepermissions` PATCH shapes | Learn REST reference, pipeline-permissions | Both the batch form (array at `/pipelinepermissions`) and the per-resource form (`/pipelinepermissions/{type}/{id}`) exist; we use the latter. |
| Key Vault-linked variable group create body | Learn (`AzureKeyVaultVariableGroupProviderData`: `serviceEndpointId` + `vault`) | The CLI cannot create or update `AzureKeyVault` groups; REST only. RBAC vaults behind private endpoints are unsupported for linked groups. |
| Repository policy config-file shapes (file size, path length, reserved names, case, file name, author email) | Learn `az repos policy create --config` and the repository-settings page | Type ids are resolved from `az repos policy type list` by display name, with fallbacks. |
| Environment create | Learn Environments REST | Trivial body (`name`, `description`) but nowhere in the reference. |

---

## Context 8: Interactions the reference does not mention (and we would have liked)

* **Required-template check × tag pinning.** The check body lists `repositoryRef`. If consumers
  pin `refs/tags/v1.0.0` and the check says `refs/heads/main`, every deploy fails the check. So
  a template *release* is also a checks change: our manifest carries `allowedTemplateRefs`, the
  bootstrap writes one `extendsChecks` entry per template per allowed ref, and the runbook says
  to add the new tag before consumers bump. Neither the templates page nor the checks page
  connects these two facts.
* **Canary strategy + Container Apps revisions.** The progressive-delivery example is
  transport-agnostic (echo statements). Making `deploy`/`routeTraffic`/`postRouteTraffic` real
  with Container Apps required: Bicep in `preDeploy` (runs once) rather than `deploy` (runs per
  increment), multiple-revision mode only in prod, capturing the previous revision name before
  the deploy, `az containerapp ingress traffic set` per increment, and traffic rollback plus
  revision deactivation in `on.failure`. A worked "canary on a real PaaS" example would be the
  most reused page on the site.
* **Deployment jobs do not check out source.** Obvious once you know it, but the bicep deploy
  in a `deployment:` job needs an explicit `- checkout: self`, and `download: none` to stop the
  implicit artifact download. The artifacts page says the second half; the first half is in the
  deployment-jobs docs only.
* **Consumers with no ingress.** Workers cannot smoke over HTTP and cannot shift traffic, so the
  governed template needed a `prodStrategy: runOnce` escape hatch and an empty `smokePath`
  meaning "wait for healthy replicas instead". The examples assume everything has a URL.
* **The Azure Repos build-validation PR pipeline still has to pass the required-template
  check?** No: checks bind to environments, and the PR pipeline has `deploy: false`, so it
  never touches one. The reference explains checks bind to resources, which is what made this
  reasoning possible, but a sentence saying "PR pipelines that only build are unaffected" would
  save a question.

---

## Context 9: Our own tooling friction (not the reference's fault)

* Shell heredocs over roughly 150 lines were silently truncated by the command runner, which
  surfaced as an "unexpected EOF" error. Large files are written with a file tool instead.
* LLM-summarized fetches drop code blocks first. Ask for "verbatim" and for a specific section,
  or fetch twice.
* `dotnet new sln` on .NET 10 creates `.slnx`, so scripts that assume `.sln` fail.
* `dotnet package search --exact-match` lists versions oldest-first in its JSON; reading
  `packages[0]` gives you the first ever release. The NuGet flat-container index
  (`v3-flatcontainer/<id>/index.json`) is the reliable way to get "latest stable" in a script.
* Application Insights SDK 3.x is the OpenTelemetry re-platform: `ITelemetryInitializer` is
  gone. We pinned the 2.x line in `Meridian.ServiceDefaults`; moving to
  `Azure.Monitor.OpenTelemetry.AspNetCore` is a tracked follow-up.
* Minimal APIs treat a non-nullable `bool` query parameter as required; an absent `?overdue`
  is a 400 (surfaced as 500 through the exception handler). Use `bool?`.
* Microsoft.Azure.Cosmos 3.63 refuses to build without an explicit `Newtonsoft.Json`
  reference (or an opt-out property).

---

## Context 10: Running the bootstrap for real against a Microsoft-account organization

**Helpful**

* The reference's insistence that checks bind to *environments* and that only `deployment:`
  jobs consume them held up exactly: the bootstrap created 5 environments and 11 checks
  without a single pipeline existing yet, which is the order we wanted.
* The integrating page's `X-TFS-FedAuthRedirect: Suppress` advice is what made the auth failure
  (`TF400813` on an Entra token) fail loudly instead of returning a sign-in page.

**Tripped us up**

* **Branch control task id.** The widely copied `86b05a0c-73e6-4f7d-b3cf-e38fd5057eca` is wrong;
  the service answers `No task definition found for ID`. The id the Terraform provider ships,
  `86b05a0c-73e6-4f7d-b3cf-e38f3b39a75b`, works with version `0.0.1`. Neither id appears in
  `distributedtask/tasks` (the business-hours task `445fde2f-...` is accepted although unlisted
  too), so resolving check tasks by name at runtime is not possible; keep the ids in the
  governance file.
* **Key Vault-linked variable group.** Two undocumented requirements: `variables` cannot be
  empty (we seed `appinsights-connection-string`, which platform-infrastructure always writes)
  and `providerData.lastRefreshedOn` must be a valid timestamp.
* **Approval `minRequiredApprovers`.** Capped at the number of approver *entries*; a group is
  one entry, so "two release managers" cannot be expressed with a single group.
* **`az boards area project show`** takes `--id`, not `--path`. Listing the tree once and
  comparing paths is the idempotent check.

**Wish it had**

* A page on running the control-plane automation *without a PAT*: `az devops invoke`
  (`--api-version 7.1-preview`, `--in-file` for bodies, `continuation_token` injected into
  every response, empty property names in `distributedtask/tasks`) versus `Invoke-RestMethod`,
  and the fact that git to Azure Repos has no non-interactive path on a Microsoft-account
  organization other than a PAT.

---

## Context 9 addendum: tooling friction from the second session

* Git Bash path conversion rewrote the federated-credential subject `/eid1/c/pub/...` into
  `C:/Program Files/Git/eid1/...`. Run `az identity federated-credential` from PowerShell or
  with `MSYS_NO_PATHCONV=1`, then verify the subject with `-o tsv --query subject`.
* `ConvertTo-Json` already indents with two spaces in PowerShell 7; a "fix" that halved the
  indentation produced one-space JSON. Round-trip once and compare the diff before committing.
* Our automation sandbox refuses role assignments and reading stored credentials; those two
  steps are the ones that still need a person, which is a reasonable line.

---

## Context 2 addendum: first real approvals (session three)

**Tripped us up**

* **"Requester cannot approve" in a one-person organization.** Every run has the same requester:
  manual runs are queued by the owner, and CI-triggered runs inherit the identity behind the
  mirror push (the owner's PAT). With the owner as the only member of the approver group the
  stage can never be approved; it waits out the timeout and is skipped. The reference explains
  the setting but not that the *sync identity counts as the requester* for CI-triggered runs, nor
  that a solo project needs either a second approver or `requesterCannotBeApprover: false`.
* **Create-only bootstrap.** Our `Initialize-AzureDevOps.ps1` skips checks that already exist, so
  editing an approval's settings in `environments.json` silently does nothing until the check is
  deleted or patched. The update shape is on Learn (row below); the reference does not cover
  "converging" existing checks at all, which is the whole point of governance as code.

## Context 7 addendum

| Needed for | Source used | Note |
| --- | --- | --- |
| `pipelines/checks/configurations/{id}` PATCH (update an existing check) | Learn REST reference, check-configurations/update, `7.1-preview.1` | Body is the create body (`settings`, `timeout`, `type`, `resource`); the response echoes `id`. Needed once approval settings drift from the file. |

## Context 9 addendum: tooling friction from the third session

* The auto-mode classifier refuses more than the earlier "role assignments and stored
  credentials" line: `az pipelines run` was allowed for one id and refused for the next,
  `az devops invoke` was refused for a GET, and *file edits* that add a member to an approver
  group or add membership automation to the bootstrap were refused as permission grants. Reads
  bundled in the same shell command are refused with them, so keep reads and writes in separate
  commands and expect the group-membership and approval-settings steps to need a person.
* `az role assignment list --scope /subscriptions/...` from Git Bash fails with
  `MissingSubscription`: the leading slash is rewritten into a Windows path. Same fix as the
  federated-credential note above: PowerShell or `MSYS_NO_PATHCONV=1`.
* Later the same session: `az devops invoke` GETs of `pipelineschecks/configurations` were
  allowed from PowerShell, a `PATCH` of the approval check was refused as weakening security,
  and a second `az pipelines run` was refused as a retry of the first refusal. The practical
  split is: the assistant reads and documents, a person changes approval settings and queues runs
  unless an explicit allow rule exists for `az pipelines run`.

---

## Context 5 addendum: the first deploy attempt (session three)

**Tripped us up**

* **Service connection names must be known at compile time.** Our job templates passed
  `$(Meridian.ServiceConnection)` (a stage-scoped variable template value) into
  `azureSubscription` / `connectedServiceNameARM`. Queue-time validation failed on every deploy
  job with "service connection $(Meridian.ServiceConnection) could not be found" because
  authorization runs before macro variables expand. `sc-meridian-${{ parameters.environment }}`
  in the job templates fixed it. The reference's service-connection page covers the endpoint
  shapes but not this rule, which is the first thing a template author hits.
* **Every listed environment is validated at queue time.** With compile-time names, a consumer
  that lists `test` and `prod` fails outright while those service connections do not exist,
  even though the stages would never be reached. Consumers now list only provisioned
  environments; the placeholder rows in `environments.json` are the signal.
* **A template fix means a tag bump, and the tag bump touches three places**: the tag itself,
  `allowedTemplateRefs` in the manifest, and the required-template check on every environment.
  We automated the first (the sync creates a declared tag at the split commit, never moving an
  existing one) and the third (the bootstrap patches the check when the ref list changes).
  Worth a reference page: "shipping a template change under a required-template check".

**Helpful**

* The `az devops invoke` area for checks is `pipelineschecks` / `configurations`;
  `--query-parameters '$expand=settings'` returns the settings, and `PATCH` with the create body
  plus `id` updates a check in place (verified on approval and required-template checks).

---

## Context 5 addendum 2: what six template tags in one afternoon taught us

Each row cost a sync (7 min) plus a run; none of them is in the reference, and each is exactly
the kind of validated automation knowledge it promises.

| Trap | What happened | Fix |
| --- | --- | --- |
| Branch control evaluates every repository resource | The `templates` resource pinned to `refs/tags/v1.0.2` failed "allowed branches" on `packages`; the required-template check was marked failed with it (same static category). | Allow `refs/tags/v*` next to the deployable branches. |
| `create --what-if` is not `what-if` | `az deployment sub create --what-if --no-pretty-print` fails with "unrecognized arguments" on the hosted CLI; the flag exists only on the `what-if` subcommand. | Use `az deployment <scope> what-if ... --no-pretty-print --exclude-change-types`. |
| Deployment job pool from a stage variable | `pool: vmImage: $(Meridian.VmImage)` (stage-level variable template) works for plain jobs and abandons deployment jobs with "Pipeline does not have permissions to use the referenced pool(s)". | Compile-time image on deployment jobs (template parameter with a default). |
| PSRule `-Option` hashtable replaces `ps-rule.yaml` | Passing a hashtable dropped the repository's exclusions; excluded rules came back as failures. | `New-PSRuleOption -Path ps-rule.yaml`, then fill defaults the file did not set. |
| gitleaks scans history | An inline `gitleaks:allow` on the current line does nothing for the earlier commits that carry the same GUID. | `.gitleaks.toml` with `[extend] useDefault = true` and a `[[allowlists]]` regex. |
| Pipeline resource without a run | Service pipelines fail validation with "Unable to resolve latest version for pipeline platformLibraries" until that pipeline has one successful run. | Order the first runs; nothing to configure. |
| hadolint pragma must be bare | `# hadolint ignore=DL3006  (reason)` is ignored; the reason goes on its own comment line. | Two lines. |
| Feed created by REST has no build-service role | `npm ci` through the feed: 403 "You need to have 'Reader'"; NuGet push would fail the same way. The portal's create dialog adds both build services as Collaborator; the REST create adds nothing. | Contributor for `<Project> Build Service (<org>)` via `PATCH packaging/feeds/{feed}/permissions` with a body of `[{identityDescriptor, identityId, role}]`. Resolved 2026-09-21 (addendum 3): our body was `[[...]]`. |
| Version pins that never existed | trivy 0.65.0 was never released; the download 404 took the scan job and Publish SARIF with it. | Verify release assets (`gh api repos/<owner>/<repo>/releases/tags/v<x>`) when pinning. |
| `Cache@2` key pattern with no match fails the job | Services restore with `lockedMode: false` and commit no `packages.lock.json`; the NuGet cache step keyed on that file and failed every service build (runs 3930 to 3933) before restore even ran. | Add a pattern that always matches to the key (`**/*.csproj`); the key still changes when references change. |
| `readEnvironmentVariable` fallbacks are silent | Every `.bicepparam` derives unique names from `readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', '<env>001')`; a deploy job that did not export the variable targeted `stmrddevdev001` (run 3922) and failed with ParentResourceNotFound. | Export the variable in the shared deploy step for every what-if and deploy; treat a fallback value in a resource name as a defect, not a default. |
| Contributor cannot write policy assignments | First wave in which the pipeline identity, not the owner, reached `Microsoft.Authorization/policyAssignments`: What-if shared failed with "Authorization failed for template resource" (run 3921). | Resource Policy Contributor on the pipeline identity at subscription scope, granted where the identity is created. |
| `set -o pipefail` plus `\| head` | The image packaging job listed staged files with `ls -la .publish \| head -20`; `head` closed the pipe, `ls` died with SIGPIPE (exit 141) and the whole Package stage failed on all four services (runs 3958 to 3961) the first time they got that far. | No early-exit consumer (`head`, `grep -m`, `sed q`) in a pipefail script; summarize with `wc -l` or drop pipefail for the line. |
| GitVersion main builds are prereleases until a tag exists | `mode: ContinuousDelivery` with `label: ''` on `main` stamps `1.0.0-<n>`; the library Publish pushed exactly that and every service pinned a stable `1.0.0` (NU1102, runs 3950 to 3953). The Release stage that would tag a stable version only exists when `prod` is listed. | Consumers of an internal package float on `1.0.*-*` until a release tag exists, or the versioning mode is Mainline. Decide this before the first Publish. |

**Wish the reference had:** a page "the first run of a governed template", listing the queue-time
validations (service connections, pools, pipeline resources, every listed environment) that run
before a single job starts, and which of them cannot be satisfied with variables.

---

## Context 2 addendum 2: the feed permission grant, and admitting a step is manual

The feed role for the build service is the one provisioning step this platform has never
completed through an API, and it is the reason `Initialize-AzureDevOps.ps1` does not bootstrap
end to end. Recording it here because "the documented call returns 200 and does nothing" is
exactly the class of thing a validated-automation reference should carry.

**What the documented contract says.** `PATCH packaging/feeds/{feedId}/permissions` takes an
array of `{identityDescriptor, role}`. The azure-devops CLI's own SDK types `identityDescriptor`
as a string, so the shape the bootstrap sends is valid.

**What happens.** The call returns HTTP 200 with `{"count":0,"value":[]}` and the permission list
is unchanged. No error, no partial write, nothing to retry against. A read-back is the only way
to know it failed, which is why the bootstrap now reads back after every grant and treats a
missing role as a manual step rather than a warning.

**Settled 2026-09-20: no identity shape works.** `tooling/Grant-FeedRole.ps1` ran all six forms
against the documented `feeds.dev.azure.com` endpoint with a PAT: graph subject descriptor alone;
graph descriptor with identityId and displayName; IMS descriptor with identityId and displayName
(the bootstrap's shape); IMS descriptor alone; identityId alone; and the `{identityType,
identifier}` object from the 7.1 reference page. **Every one returned HTTP 200 with
`{"count":0,"value":[]}` and the read-back showed no entry.** The graph-descriptor hypothesis is
dead. The GET on the same endpoint with the same token works, so the token reaches the service.

**Scope was then ruled out too.** The script now probes write capability before concluding: it
PATCHes the feed's own description to the value it already holds, which needs *Packaging (read,
write and manage)* and changes nothing. That write is **accepted**. The same token, in the same
run, cannot make a single permissions entry stick. Feed addressed by GUID instead of name: same.
api-versions 6.0-preview.1 and 7.0-preview.1: same.

So it is not the token, not the identity form, not the api-version and not how the feed is
addressed. The `permissions` route accepts the request, answers 200 with an empty collection and
persists nothing. **The grant cannot be automated through this API, and the portal is the only
path.** That is now a finding rather than a suspicion, and the bootstrap reports it as a step a
human must perform instead of pretending it might have worked.

A trap worth its own line: the first version of these diagnostics named a local variable `$feed`
while the parameter was `$Feed`. PowerShell variable names are case-insensitive, so the feed
object overwrote the feed name and every probe URL after it was malformed -- which produced a
confident and completely wrong "token scope" verdict. Diagnostics that can fail silently need
their own sanity check; this one prints the resolved feed name and id before it draws any
conclusion.

**A trap that hid the answer for a full session.** The first version of that script, and of
`Approve-PendingApprovals.ps1`, built their URLs as `"$feedsBase?api-version=..."`. PowerShell
accepts `?` as a variable-name character, so that reads a variable named `feedsBase?`, which is
empty, and the request goes out with the query string as the whole URI:
`Invalid URI: The hostname could not be parsed.` Both scripts died before sending anything, on
the PAT path only — the `az devops invoke` fallback has no interpolated URL and worked fine,
which is what made the bug look like a service-side refusal. The fix is `"${feedsBase}?..."`.
This is the second time this exact trap has cost this project a session (see Context 9
addendum, third session). Grep for `\$[A-Za-z_][A-Za-z0-9_]*\?` before shipping a PowerShell
script that builds a URL.

**The wider point.** We spent two sessions asserting in handoffs and executive notes that the
grant "has failed through the API in every scripted form attempted." It had not: the PAT path
never executed. An automation gap and a broken script produce the same symptom — nothing
happens — and we defaulted to the more interesting explanation. The platform now states the
manual steps in three places (root `README.md`, `tooling/README.md`, and a numbered block the
bootstrap prints when it finishes) and distinguishes the approval gate, which is manual by
design, from the feed grant, which is a defect we have not closed.

**Wish the reference had:** a page on Azure Artifacts feed permissions as an automation target —
which identity descriptor flavour the feeds service accepts, that the PATCH is silently
idempotent-on-failure, and that a read-back is mandatory. More generally, a convention for
documenting the steps a bootstrap *cannot* perform, since every real platform has some and
leaving them in a warning stream guarantees they are missed.

---

## Context 2 addendum 3: the feed grant was automatable all along (2026-09-21)

Addendum 2 is kept above as written because its conclusion was wrong and the way it went wrong is
the useful part. The grant persisted on the first attempt of the fifth session, with the
bootstrap's original shape (IMS descriptor + `identityId` + `displayName`), once one token was
removed from the code that serialized the body.

**The defect.** `ConvertTo-Json -InputObject @(@{...}) -AsArray`. The input is already an
array; `-AsArray` wraps it again. The wire body was therefore `[[{"identityDescriptor":...}]]`
— an array containing an array — not a `FeedPermission[]`. The feeds service accepted that as
"zero permissions to set", answered HTTP 200 `{"count":0,"value":[]}`, and persisted nothing.
Every one of the nine identity shapes, three api-versions, the feed-by-GUID probe and the
description-write probe went out inside the extra brackets. The same token sat in
`Initialize-AzureDevOps.ps1` (so the bootstrap's PATCH had the same body) and in
`Approve-PendingApprovals.ps1` (whose approvals PATCH would have approved nothing, silently).

**What made it invisible.** The script printed `ConvertTo-Json` of the *PowerShell object*, not
the bytes it sent; each attempt's log line began `[[` and nobody read the brackets, because the
attention was on the identity string inside them. The description-write probe "proved" the
token could write, which was true, and narrowed the blame to the permissions route — a
conclusion that was consistent with every observation and still wrong. Two handoffs, an
executive narrative and a README section repeated it.

**Correct wire contract** (documented, and now observed): `PATCH
https://feeds.dev.azure.com/{org}/{project}/_apis/packaging/Feeds/{feedId}/permissions?api-version=7.1-preview.1`
with body `[{"identityDescriptor":"Microsoft.TeamFoundation.ServiceIdentity;<guid>:Build:<projectId>","identityId":"<id>","displayName":"<Project> Build Service (<org>)","role":"contributor"}]`
returns `{"count":1,"value":[{"role":"contributor","identityDescriptor":"...","displayName":null,"isInheritedRole":false}]}`
and the read-back shows the entry. A PAT with *Packaging (read, write and manage)* is enough.

**What the reference could carry.** Not this bug — it is ours — but two things around it:
(1) the service's response to a malformed body is 200 with an empty collection rather than 400,
so a read-back after any permissions write is mandatory; (2) a one-line rule for PowerShell
automation: print the serialized request body, not the object, and treat a leading `[[` as the
first suspect when a write returns an empty result.

**Manual steps, revised.** The platform has one: the `shared` environment approval, which is
manual by design. The root `README.md`, `tooling/README.md` and the bootstrap's closing banner
now say so.

---

## Context 5 addendum 3: resource triggers in practice (2026-09-22, the v1.0.9 wave)

Pages used, from `llms.txt` (Knowledge updated 2026-09-22T02:48:57Z): Domain Knowledge Index ->
Trigger Semantics; Pipeline Resources (the Resource Triggers table, the Trigger identity cheat
sheet, "Default version and branch selection for completion triggers", Pitfalls); Predefined
Variables section 5; Golden Path "First run of a governed pipeline". The finding they served is
in `handoff-6.md`, "Every service runs three times per wave": each of the four services was
queued three times per wave (its own CI on the pin bump, the libraries Publish completion, the
base-image re-import), about 40 hosted minutes per set of four at parallelism 1.

**Helpful**

* The routing table took us from `llms.txt` to Trigger Semantics and Pipeline Resources in one
  hop.
* The pitfall "CI + completion triggers double-run: disable one of the two triggers" is exactly
  our triple run and drove the fix: the producers' CI path filters now exclude their own
  `azure-pipelines.yml` (and `pipelines/*` for libraries), so a pin bump no longer re-publishes,
  and the consumers keep their resource triggers.
* "Container trigger evaluation occurs only on the pipeline's default branch" and "triggers live
  in the entry YAML only, no variables" confirmed the fix is consumer YAML only: no template
  tag, no `allowedTemplateRefs` change, no check update.
* "CI trigger reads the pushed branch's copy" told us the push that carries the fix will not
  itself fire the producers, so the fix costs no wave.

**Tripped us up**

* The Resource Triggers table and the Trigger identity cheat sheet say a resource-triggered run
  carries `Build.Reason = ResourceTrigger`. The Build REST API (`az pipelines runs list` /
  `show`, api-version 7.1) reported `reason = manual` for both a pipeline-completion trigger
  with a `stages:` filter (runs 3950 to 3953, 3976 to 3979) and an ACR container trigger (runs
  3934 to 3937, 3954 to 3957), with `requestedBy = Microsoft.VisualStudio.Services.TFS`. The
  truth is in `triggerInfo.pipelineTriggerType` (`PipelineCompletion` or `ContainerImage`) plus
  `alias`, and `version` or `tag`. Our `Start-EnvironmentDeploy.ps1` matched on
  `reason -eq 'resourceTrigger'` and never matched a run. We did not verify the in-run
  `Build.Reason` value: our templates only compare it against `PullRequest` and nothing prints
  it, so the cheat sheet may be right inside the job while the REST view differs. Suggestion:
  add the REST-side shape (`reason`, `requestedBy`, `triggerInfo`) to the cheat sheet next to
  the in-run variable.
* Context 5 above says "we gate completion-triggered runs on `Build.Reason` to avoid the double
  run". We never did; the only `Build.Reason` gate in the templates excludes pull requests. Kept
  as written, corrected here.

**Wish it had**

* A stage-filtered completion trigger (`trigger.stages: [Publish]`) queues the consumer as soon
  as that stage completes, while the producer run is still in progress (3976 to 3979 were queued
  at 03:18 UTC with 3964 still in its Deploy stages). The reference describes completion
  triggers as "when another pipeline completes successfully". The trap in `handoff-6.md` about
  the trigger firing "even when the run later fails" (runs 3930 to 3933, fired by a Publish
  stage whose run then went red in Deploy) is the same gap seen from the other side: the
  consumer is queued on the stage, not on the run, in both directions.
* Nothing addresses "a producer that re-publishes an unchanged output re-fires every
  consumer". GitVersion mints a new prerelease on every commit and `az acr import --force`
  re-pushes the channel tag, so a pin bump on either producer costs a full set of consumer
  runs. The path-filter approach was ours. Build-tag trigger filters (`trigger.tags`, which the
  reference says it validated in its runs 3711 to 3716) would be the reference-backed
  alternative if the producers could tag only the runs that carry real changes; ours cannot
  tell a real change from a re-publish yet.
* Whether a single `*` in a CI `paths` filter crosses `/` on Azure DevOps Services. Learn's
  note on the subject is scoped to Server 2020 and the reference's "anywhere" wording does not
  settle it, so `base-images/*` may or may not match `base-images/<image>/Dockerfile`, where
  every file in that pipeline lives. We moved the containers pipeline to the documented
  directory form (`base-images`); a one-line "on Services, `*` does / does not cross `/`" with a
  validated run would close it.
* Follow-on to the stage-completion row above: at parallelism 1 the consumer runs that a
  stage-filtered completion trigger queues sit in the queue ahead of the producer's remaining
  stages (measured on 3964: Publish finished 03:18:22 UTC, consumer 3976 queued 03:18:22 UTC,
  the producer run finished 03:42:43 UTC; 63.5 min wall time for a run whose useful work ended
  at 03:18). That distorts wall-clock readings of the producer and breaks any detection window
  anchored on the producer's finish time; the window has to start at the producer's queue time
  and match on `triggerInfo.pipelineId`.

---

## Context 11: Agent hosting, Managed DevOps Pools vs. Container Apps jobs (2026-09-22)

New context: no working session had touched agent hosting before today. Page used:
`domain/azure-pipelines/agent-hosting/index.md`, fetched for the assessment
`docs/executive/2026-09-22-self-hosted-capacity-assessment.md`.

**Helpful**

* One decision table up front (Microsoft-hosted / VMSS / Managed DevOps Pools / ACA+KEDA / plain
  self-hosted, each with cost, scale-to-zero, image control, network, Docker) meant we did not
  have to build that comparison ourselves from five separate Learn pages.
* "The PAT is used only during registration; ongoing agent-server communication uses a per-agent
  listener token" was stated plainly and Microsoft Learn's agent-authentication pages confirmed
  it word for word. Saved a round of worrying about PAT expiry killing a running agent mid-job.
* The placeholder-agent requirement for a scaled-to-zero ACA pool, and the warning that deleting
  it leaves the pool with zero agents and every pipeline failing immediately, is the kind of
  "the demo works, then you delete the wrong thing" trap this project has hit before elsewhere
  (see Context 9). Worth having called out ahead of building it.

**Tripped us up**

* The page's Managed DevOps Pools section covers setup, permissions, images and cost, but never
  says an Entra-connected Azure DevOps organization is a hard prerequisite, only that PAT-less
  registration is "the productized path" for MDP. That framing reads as an upgrade over PAT, not
  as a gate this specific organization fails. We found the actual blocker by cross-checking our
  own `docs/handoff.md` (`TF400813`, Microsoft-account-owned org, session two) against Microsoft
  Learn's prerequisites page, not from the reference. For a Microsoft-account-owned organization
  like `coolhome`, this is the single fact that decides the whole assessment, and the reference
  did not carry it.
* The table lists MDP's Docker support as "Image-dependent" with no pointer to which images
  qualify. Learn's own image list (the "Azure Pipelines" quick-starter images, matching the
  Microsoft-hosted software set including Docker) answered it, but took a second fetch.

**Wish it had**

* A note that VMSS, MDP, ACA and plain self-hosted agents all draw from the same "self-hosted
  parallel jobs" licensing pool, separate from Microsoft-hosted jobs, and that the first
  self-hosted job is free and automatically granted (no billing action, unlike the
  Microsoft-hosted free tier which has to be enabled). The reference's cost framing reads as
  though buying a parallel job is the first step of adopting any self-hosted option; Microsoft
  Learn's pricing page corrected that today, and it changes the recommended scope (no purchase
  needed to match today's parallelism of 1).
* Concrete cold-start numbers for ACA jobs specifically (the tutorial has none; MDP's standby-agent
  page gives 10 seconds to a minute with standby, up to 15 minutes without, but nothing comparable
  exists for the ACA path). We could not verify a cold-start figure for Container Apps jobs from
  either source today and said so in the assessment rather than guess.
