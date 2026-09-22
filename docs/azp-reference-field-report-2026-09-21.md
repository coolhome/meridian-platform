# azp-reference field report — Meridian build, 2026-09-21

Meridian is a governed reference platform: one `extends` template family in a templates repo,
service consumers pinned to template tags, five environments with checks created from a
governance file, Azure Repos mirrors of a GitHub monorepo. [azp-reference](https://github.com/coolhome/azp-reference)
was the primary source for every pipeline decision, ahead of Microsoft Learn.

This report keeps only the items that change or extend a reference page or example. Gaps that
belong to the Azure DevOps control plane, to Git, or to our own tooling are listed once at the
end and otherwise left out. The running log this was distilled from is Meridian's
`docs/reference-feedback.md`.

Each item: **Goal** (what we were doing) · **What tripped us up** · **What was missing, what we
used** · **Suggested change** · **Evidence**, in the reference's own vocabulary
(documented / compiled / observed / unverified).

## Summary

| # | Item | Page or example | Kind |
|---|---|---|---|
| 1 | Examples still use `NodeTool@0`, which the catalog marks deprecated | examples 01, 10, 14 | correction |
| 2 | Service-connection name from a macro fails queue-time authorization | variable-syntax, evaluation-layers | correction (verdict scope) |
| 3 | Deployment-job `pool.vmImage` from a stage variable is rejected | templates (deployments), agent-hosting | addition |
| 4 | Every listed environment and connection is validated at queue time | pipeline-resources (pitfalls), templates | addition |
| 5 | A pipeline resource needs one successful run before consumers compile | pipeline-resources (pitfalls) | addition |
| 6 | Branch control evaluates every repository resource, tag-pinned templates included | checks-and-approvals, templates | addition |
| 7 | A template release is a checks change (required-template refs) | checks-and-approvals, templates | addition |
| 8 | Requester identity for CI-triggered runs; approver-entry cap | checks-and-approvals | addition |
| 9 | Checks page has no automation surface; the copied branch-control id is wrong | checks-and-approvals | addition |
| 10 | Scanners page names tools, not how they run in a pipeline | security-scanners, built-in-tasks | addition |
| 11 | When to expose data instead of `jobList`/`deploymentList`; multi-kind example | templates, examples | addition / example |
| 12 | Cross-links: deployment jobs skip checkout; build-only PR pipelines are outside checks | templates, artifacts, checks | minor |
| 13 | Which `AzureCLI` major for ARM | built-in-tasks | minor |
| 14 | Progressive delivery on a real PaaS; consumers without ingress | example 02 | example |

What held under load, no change needed: the root `variables:` collision rule, "only
`deployment:` jobs bind environment checks", the boolean-coercion gate, the five check
categories, `X-TFS-FedAuthRedirect: Suppress`, the leading-dot pipeline-name trap, the
TF401019 versus "needs permission" split, the WIF two-phase create flow, and the group-name
quoting footgun. Each one changed a decision or saved a debugging session.

---

## 1. Examples still use `NodeTool@0`, which the catalog marks deprecated

**Goal.** Build the Node setup step for Meridian's SPA and the Node branch of the governed
build template, starting from the reference's example shape.

**What tripped us up.** Four example files use `NodeTool@0`:

- `examples/01-monorepo-matrix-ci/templates/ci-pipeline.yml:178`
- `examples/01-monorepo-matrix-ci/templates/steps-node-setup.yml:19`
- `examples/10-multi-repo-app-platform/repos/pipelines/templates/build/node.yaml:19`
- `examples/14-central-ci-cd-config/platform/repos/central/templates/ci.yml:19`

The [built-in tasks catalog](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/built-in-tasks.md)
row for `NodeTool@0` says **Deprecated — use `UseNode@1`**. We only caught it because the
catalog row is explicit; a reader who copies the example ships a deprecated task.

**What was missing, what we used.** Nothing missing; the catalog and the examples disagree.
Meridian's Node setup step (`pipeline-templates/steps/node-setup.yml`) uses `UseNode@1`.

**Suggested change.** Replace `NodeTool@0` with `UseNode@1` in the four files. The input is
renamed: `versionSpec` on `NodeTool@0` becomes `version` on
[`UseNode@1`](https://learn.microsoft.com/azure/devops/pipelines/tasks/reference/use-node-v1).
Re-record the affected `azp-run` verdicts. A cheap gate for the future: fail the examples
check when a task the catalog marks deprecated appears under `examples/`. `UsePythonVersion@0`
in example 10 is fine; `@0` is its only major.

**Evidence.** Documented (catalog row against example source).

---

## 2. Service-connection name from a macro fails queue-time authorization

**Goal.** Meridian's job templates took the ARM connection from a stage-scoped variable
template, `azureSubscription: $(Meridian.ServiceConnection)`, the shape the reference shows.

**What tripped us up.** Queue-time validation failed every deployment job:

```
service connection $(Meridian.ServiceConnection) could not be found
```

Authorization runs before macro expansion for values that are not known at queue time, so the
literal macro is looked up as a connection name. The fix was a compile-time name,
`azureSubscription: sc-meridian-${{ parameters.environment }}` (templates v1.0.1 → v1.0.2).

**What was missing, what we used.** The
[variable-syntax page](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/variable-syntax.md)
shows `azureSubscription: $(azureServiceConnection)` (`azp-run` id `var-macro-task-inputs`)
and `azureSubscription: $(serviceConnection.${{ parameters.env }})` with a job-level variable
group inside a deployment job (`var-nested-template-in-macro`). Both carry a "compiles clean"
verdict. A compile does not exercise resource authorization, which the repository's own working
agreement already states. Learn's service-connection pages say "use the name" and nothing about
variable scope. We resolved it by experiment.

**Suggested change.**

- Under both blocks: macro syntax in `azureSubscription` / `connectedServiceNameARM` works
  only when the value resolves at queue time (root `variables:`, a root-level variable group,
  a queue-time variable). Stage- or job-scoped values, including variable templates included
  at stage scope, are not expanded before authorization and fail with "could not be found".
  Templates should take the connection as a parameter or derive it with `${{ }}`.
- Run `var-nested-template-in-macro` for real. A job-level group inside a deployment job is
  the shape we did not test; record the result as observed either way.
- Add the layer that resolves resource-binding inputs to
  [evaluation-layers pitfalls](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/evaluation-layers.md#common-pitfalls).

**Evidence.** Observed (stage-scoped variable template, Meridian org, 2026-09-19).
The job-scoped variable-group form is unverified by us.

---

## 3. Deployment-job `pool.vmImage` from a stage variable is rejected

**Goal.** One place for the hosted image across all stages: a stage-level variable template
with `Meridian.VmImage`, referenced as `pool: vmImage: $(Meridian.VmImage)`.

**What tripped us up.** Plain jobs run. Deployment jobs are abandoned with:

```
Pipeline does not have permissions to use the referenced pool(s)
```

The message reads as a permissions problem; it is the unexpanded macro being treated as a pool
name. Fix: a compile-time image on deployment jobs (template parameter with a default).

**What was missing, what we used.** Learn shows `pool: vmImage: $(imageName)` for matrix
jobs and says nothing about deployment jobs. The templates page's
[`job` vs `deployment`](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/templates.md#deployments)
section and agent-hosting do not mention it. Solved by experiment.

**Suggested change.** In the deployments section and agent-hosting: deployment jobs resolve
`pool` at queue time together with the environment; a macro from stage or job scope is not
expanded there, and the failure surfaces as the misleading pool-permissions message. Items 2,
3 and 4 are one rule: resource-binding inputs (service connection, pool, environment) need
compile-time values or root-level variables.

**Evidence.** Observed (Meridian templates, v1.0.x tag series, 2026-09-20).

---

## 4. Every listed environment and connection is validated at queue time

**Goal.** Consumers declare the environments they deploy to; the template emits one deployment
stage per environment. Only `dev` and `shared` were provisioned.

**What tripped us up.** With compile-time connection names (item 2), a consumer that listed
`test` and `prod` failed at queue time while `sc-meridian-test` and `sc-meridian-prod` did not
exist, even though those stages had conditions that would have skipped them. Consumers now list
only provisioned environments; placeholder rows in Meridian's environments file are the signal.

**What was missing, what we used.** The
[pipeline-resources pitfall](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/pipeline-resources.md#pitfalls)
"Compile-time resolution reaches into the org" covers `resources.*`. The same validation for
service connections named in task inputs, deployment-job pools and deployment-job environments
is not listed anywhere. We learned it from the run.

**Suggested change.** Extend that pitfall, or add a "first run of a governed template"
checklist on the templates page: what is checked before any job starts (repository resources
and refs, pipeline resources and their runs, service connections in task inputs, deployment-job
pools, deployment-job environments), and that `condition:` does not exempt a stage from this
validation. Only `${{ if }}` does, which is the presence-versus-execution split
template-directives already teaches.

**Evidence.** Observed.

---

## 5. A pipeline resource needs one successful run before consumers compile

**Goal.** Service pipelines declare a `resources.pipelines` entry for the shared libraries
pipeline so they trigger on it and download from it.

**What tripped us up.** Until the producer had one successful run, every consumer failed
validation:

```
Unable to resolve latest version for pipeline platformLibraries
```

Nothing to configure. Order the first runs, producer first.

**What was missing, what we used.** The pipeline-resources pitfalls cover the
"source does not exist" case (*Pipeline Resource … Input Must be Valid*). The "exists but has
no completed run" case has a different message and a different remedy and is not listed.

**Suggested change.** Add the message and the rule to the same pitfall. Note the bootstrap
consequence: a script that creates all definitions must queue producers before consumers.

**Evidence.** Observed (Meridian handoff 4).

---

## 6. Branch control evaluates every repository resource, tag-pinned templates included

**Goal.** Branch control on each environment allowing `refs/heads/main` and release
branches. Consumers pin the templates repository to `refs/tags/v1.0.x`, as the templates page
recommends.

**What tripped us up.** The check failed "allowed branches" because the `templates`
repository resource was at `refs/tags/v1.0.2`. The required-template check was reported failed
with it, since both are static checks and the category fails as a unit. Fix: allow
`refs/tags/v*` next to the deployable branches.

**What was missing, what we used.** The
[checks page](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/checks-and-approvals.md#execution-order-five-categories)
lists branch control as static and explains category-level failure. Nothing says the check
evaluates all repository resources of the run, not only `self`, so tag pinning on the templates
page and branch control on the checks page collide silently. Learn's approvals page describes
the check as validating the resources linked to the pipeline; the consequence for a tag-pinned
template repo is not drawn out there either.

**Suggested change.** One bullet under static checks, and a cross-reference beside the
"pin to a tag" comments on the templates page (lines 319 and 896): allowed-branch patterns must
include the template tag pattern; a failing branch control also fails required-template.

**Evidence.** Observed; documented (Learn) for the "all resources" scope.

---

## 7. A template release is a checks change

**Goal.** Ship template fixes as new tags; consumers bump their pinned ref opt-in, per the
operating model.

**What tripped us up.** The required-template check's `extendsChecks` entries carry an exact
`repositoryRef`. Consumers pinned to `refs/tags/v1.0.0` fail the check on every environment
whose check names `refs/heads/main` or the previous tag. Every tag bump therefore touches three
places: the tag, the manifest's allowed refs, and the check on every environment. Meridian
automates two of them (the sync creates a declared tag at the split commit and never moves an
existing one; the bootstrap patches the check with one entry per template per allowed ref) and
the runbook says to add the new ref before consumers bump.

**What was missing, what we used.** The templates page (line 896) says
"pinned tag — Required-template check matches exact ref", which is the fact. The release-process
consequence is not drawn anywhere: old and new refs must both be listed during the migration
window, and the check has to change before consumers can move. We took the settings shape from
Learn's [check-configurations add](https://learn.microsoft.com/rest/api/azure/devops/approvalsandchecks/check-configurations/add)
sample: `extendsChecks: [{ repositoryType: git, repositoryName: <project>/<repo>,
repositoryRef, templatePath }]`.

**Suggested change.** A short "shipping a template change under a required-template check"
subsection on the checks page or in the operating model: order of operations, the multi-ref
window, the settings shape, and that `PATCH pipelines/checks/configurations/{id}` with the
create body plus `id` updates the check in place.

**Evidence.** Observed (PATCH verified on approval and required-template checks);
documented (Learn) for the body.

---

## 8. Requester identity for CI-triggered runs; approver-entry cap

**Goal.** Approval on `shared` and `prod` by a Platform Engineering group with "requester
cannot approve", and two required approvers for prod.

**What tripped us up.**

- In a one-person organization every run has the same requester. Manual runs are queued by
  the owner; CI-triggered runs are requested on behalf of the identity whose PAT pushed the
  mirror. With the owner as the only group member the stage can never be approved, waits out
  the timeout, and is skipped. Remedy: a second approver, or `requesterCannotBeApprover: false`
  on non-production environments.
- `minRequiredApprovers` cannot exceed the number of approver entries, and a group is one
  entry. "Two release managers" cannot be expressed with a single group; the service caps the
  value at the entry count.

**What was missing, what we used.** The
[approvals section](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/checks-and-approvals.md#approvals-the-manual-approval-check)
and the comparison table mention the self-approval setting by its UI label. Nothing says who the
requester is for a CI-triggered run, that a sync identity counts, or how approver entries are
counted. REST key names came from Learn's check-configurations reference.

**Suggested change.** Extend the self-approval bullet with the requester per trigger kind that
we observed (manual: the queuing user; CI: the pushing identity), the solo-org consequence, the
entry-count rule, and the REST keys beside the UI labels (`requesterCannotBeApprover`,
`minRequiredApprovers`, `executionOrder`).

**Evidence.** Observed (Meridian handoff 3; bootstrap `Initialize-AzureDevOps.ps1`).

---

## 9. Checks page has no automation surface; the copied branch-control id is wrong

**Goal.** Create eleven checks across five environments from a governance file, and converge
on re-run.

**What tripped us up.**

- The page is concepts only: no endpoint, api-version, check-type ids, or task-check
  `definitionRef` values. All of it came from Learn and from known GUIDs.
- Branch control: the id in most copied snippets, `86b05a0c-73e6-4f7d-b3cf-e38fd5057eca`, is
  refused with *No task definition found for ID*. The id the Terraform provider's
  `azuredevops_check_branch_control` uses, `86b05a0c-73e6-4f7d-b3cf-e38f3b39a75b`, works with
  version `0.0.1`. Business hours is `445fde2f-6c39-441c-807f-8a59ff2e075f`
  (`evaluateBusinessHours`, inputs `businessDays`, `timeZone`, `startTime`, `endTime`).
  Neither id is returned by `distributedtask/tasks`, so resolving check tasks by name at run
  time does not work; keep the ids in the governance file.
- Convergence: a create-only bootstrap silently ignores edits. `GET
  pipelines/checks/configurations?$expand=settings` returns settings, and `PATCH
  .../configurations/{id}` with the create body plus `id` updates in place. Through
  `az devops invoke`: area `pipelineschecks`, resource `configurations`,
  `--api-version 7.1-preview`.

**What was missing, what we used.** Learn REST reference
([add](https://learn.microsoft.com/rest/api/azure/devops/approvalsandchecks/check-configurations/add),
[update](https://learn.microsoft.com/rest/api/azure/devops/approvalsandchecks/check-configurations/update),
`7.1-preview.1`); the Terraform provider source for the branch-control id; our own runs.

**Suggested change.** An "Automating checks" section on the checks page: endpoint and
api-version, one body per built-in check (approval, branch control, business hours, required
template, exclusive lock), the two task ids with the wrong one called out, `$expand=settings`,
and the PATCH-to-update shape. This is the one core page whose concepts could not be acted on
without leaving the reference. The other control-plane shapes we needed are listed at the end
and are a scope decision.

**Evidence.** Observed (ids and PATCH on the Meridian org); documented (Learn) for bodies.

---

## 10. Scanners page names tools, not how they run in a pipeline

**Goal.** Choose the scanning steps for the governed build stage: image scan, secret scan,
SARIF publish.

**What tripped us up.** The
[scanners page](https://github.com/coolhome/azp-reference/blob/main/docs/domain/automation-security/security-scanners.md#tool-tables-open-source-unless-noted)
lists tools by category and says nothing about how each one runs in Azure Pipelines.
`MicrosoftSecurityDevOps@1`, the Microsoft task that wraps several of them, is a marketplace
extension: it is in the YAML schema the reference ships but not in the built-in tasks catalog,
so we looked for it there first. We install Trivy and Gitleaks binaries directly with pinned
releases. Parallel image-scan jobs that published SARIF under one artifact name collided with
*artifact already exists for build* and took the second job down; one artifact name per job.

**What was missing, what we used.** The task's marketplace page; our own step templates.

**Suggested change.** A "runs in Azure Pipelines as" column or short section: marketplace task
(extension required), vendor task, or direct binary install with a pinned release, plus the
SARIF publishing route and the one-artifact-name-per-job rule.

**Evidence.** Documented (schema versus catalog); observed (artifact collision).

---

## 11. When to expose data instead of `jobList`/`deploymentList`; a multi-kind example

**Goal.** Design the parameter surface of the governed `extends` template.

**What tripped us up.** The templates page recommends `deploymentList` for central templates
and explains `templateContext`; example 09 hands consumers a `stageList`. For a service platform
we wanted consumers to pass data (`kind`, environments, hooks) and the template to emit every
structure, which is example 10's shape. The page never says when to prefer that, so we
reverse-engineered the decision from the examples. Generalizing example 10's
`${{ if }}` / `${{ elseif }}` ladder on `build.kind` into one template that handles a container
image, a NuGet package and a static site behind a `kind:` parameter was the largest piece of
design work with no worked example.

**Suggested change.** A paragraph under
[Data types](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/templates.md#data-types):
data-only parameters for platform-owned templates (the consumer cannot author jobs; every job is
a `deployment:` the template controls), structural parameters when the consumer legitimately owns
steps (with example 01's allow-list check). Link example 10. Example wish: one `extends`
template with several artifact kinds behind `kind:`.

**Evidence.** Design guidance; Meridian's templates are the working instance.

---

## 12. Cross-links: deployment jobs skip checkout; build-only PR pipelines are outside checks

- **Deployment jobs default to `checkout: none`.** Stated once, in
  [multi-repo-checkout](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/multi-repo-checkout.md).
  The Bicep deploy in Meridian's deployment job needed an explicit `- checkout: self` and
  `download: none`. The artifacts page's
  [implicit download](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/artifacts-and-downloads.md#implicit-download-in-deployment-jobs)
  section says the second half; the templates page's deployments section says neither. One
  sentence in each. Evidence: documented.
- **A PR pipeline that only builds is unaffected by environment checks.** Checks bind to
  resources; a build-validation pipeline with no deployment job never touches one, so
  required-template and branch control do not apply to it. The checks page makes this
  derivable; a sentence would save the question. Evidence: observed.

---

## 13. Which `AzureCLI` major for ARM

The integrating page's
[version table](https://github.com/coolhome/azp-reference/blob/main/docs/domain/azure-pipelines/integrating-with-azure-pipelines.md#part-3-azureclin-pipeline-task)
says `@3` adds `connectionType` with `azureRM` or `azureDevOps`, so `@3` accepts ARM. The
catalog row's "Azure DevOps (v3 only)" reads, through a summarizer, as if `@3` were Azure
DevOps-only, and we stayed on `@2` for ARM. Partly our tooling. A one-line rule in the catalog
row would settle it: `@2` for ARM today; `@3` when `connectionType` or the Azure DevOps
connection is needed.

**Evidence.** Documented.

---

## 14. Progressive delivery on a real PaaS; consumers without ingress

Example 02's strategy hooks are echo statements, and its comments already explain that
`preDeploy` runs once while `deploy`, `routeTraffic` and `postRouteTraffic` repeat per
increment. Making that real on Container Apps needed: infrastructure (Bicep) in `preDeploy`,
capturing the previous revision name before the first increment, `az containerapp ingress
traffic set` per increment, and traffic rollback plus revision deactivation in `on.failure`,
with multiple-revision mode only in prod. Workers without ingress cannot smoke over HTTP or
shift traffic, so the template needed a `runOnce` escape hatch and "wait for healthy replicas"
as the smoke check. The examples assume everything has a URL.

**Suggested change.** A worked example or an addendum to 02 mapping each hook to a PaaS
operation, with the no-ingress variant.

**Evidence.** Compiled (Meridian templates); the prod canary path has not completed a live
run yet.

---

## Considered and left out

Recorded so the filter is visible. Each is real, none is a pipelines-reference change.

- **Azure Artifacts feed permission grant.** For two sessions this read "returns 200 with an
  empty collection for every identity shape". It was our body: `ConvertTo-Json -AsArray` on an
  array sent `[[...]]`, which the service accepts as zero permissions. Fixed 2026-09-21; the
  documented contract works. Our defect, and Azure Artifacts control plane either way.
- **Branch policies as code; Azure Repos mirroring** (subtree split, force-push semantics,
  PAT via `http.extraheader`). Repo boundary.
- **PAT-less control-plane automation** (`az devops invoke` quirks, Microsoft-account
  organizations). Tooling.
- **Control-plane wire shapes**: Key Vault-linked variable group create body (`variables`
  cannot be empty, `lastRefreshedOn` must be valid), environment create, `pipelinepermissions`
  PATCH and the `{projectId}.{repoId}` resource id. The access-controls page names the API;
  pulling the shapes in is a scope decision.
- **`az deployment <scope> create --what-if --no-pretty-print`** is rejected on the hosted
  CLI; use the `what-if` subcommand. az CLI, and example 14 already does it right.
- **Scanner configuration and pinning hygiene**: gitleaks scans history (allowlist in
  `.gitleaks.toml`), hadolint pragmas must be bare, PSRule `-Option` replaces `ps-rule.yaml`,
  a pinned Trivy version that was never released.
- **Our tooling**: PowerShell `"$var?..."` reads a variable named `var?`, Git Bash path
  conversion of `/eid1/...` and `/subscriptions/...`, LLM-summarized fetches dropping code
  blocks, sandbox refusals.
- **Example 09 gives consumers too much freedom** for a service platform. An opinion; no change.
- **A machine-readable examples manifest** next to `pipeline-timeline.json`. Site tooling, not
  a docs change.

<!-- doc-dates:start -->
**Knowledge updated:** `2026-09-21T04:40:00Z` · **Corrections updated:** `none`
<!-- doc-dates:end -->
