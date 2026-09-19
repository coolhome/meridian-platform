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
