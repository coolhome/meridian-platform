# Rollout narrative, 2026-09-19 (second note)

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-20 02:14 UTC, after a verification pass over the completed v1.0.6 wave (runs 3808 to 3817) |
| Sources | `docs/handoff-4.md`; git log `222e216..2afebd2`; run timelines and task logs for 3812 to 3817; project variable groups; feed permissions; `pipeline-templates/pipelines/extends/service.yml`; hosted resource usage |
| Supersedes | `2026-09-19-rollout-narrative.md` |

## Where we were

The previous note, written at 19:10 UTC, reported the platform fully wired after three sessions and the templates v1.0.6 wave as the first in which every pipeline ran to a real outcome. Ten pipelines ran, one succeeded, and five distinct first-deploy causes were named. Nothing had deployed. The note flagged that two of those causes had been misattributed in handoff 4, and that the feed permission grant was the one step the tooling could not perform.

## Where we are

No pipeline has run since 19:10 UTC, so the platform state itself is unchanged. What changed is the quality of what we know about it. This pass traced every failure to its log line and confirmed each cause in the repository or in the service, which is the standard the previous note set for itself but could only partly meet while runs were still finishing.

Four of the five causes are confirmed exactly as stated. One new defect was found that the previous note did not name. Both actions that only the platform owner can take are confirmed still open.

| Pipeline or workstream | Stage reached | Cause | Owner of the fix |
| --- | --- | --- | --- |
| pipeline-templates-ci (3808) | Complete | Green, and green in three consecutive waves | None |
| platform-infrastructure (3814) | What-if shared | `shared.bicepparam` passes the literal `$(UniqueSuffix)` into a parameter capped at 8 characters (BCP332). The `meridian-shared` group defines four `Meridian.*` variables and no `UniqueSuffix` | Bootstrap config |
| platform-libraries (3815) | Publish | NuGet push targets the organisation-scoped feed URL, which returns 404 TF1600011. The feed is project-scoped | Template, next release |
| containers-base-images (3816) | Build | Both parallel image jobs publish an artifact named `CodeAnalysisLogs-image` | Template, next release |
| app-frontend (3812) | Build, and separately Deploy dev | `npm ci` returns 403 because the build service lacks Reader on the feed. Deploy dev then ran despite the failed build and failed on a missing artifact | Platform owner for the grant, template for the stage dependency |
| observability (3817) | Deploy dev | Eight ARM errors: four log alerts use two evaluation periods without projecting a timestamp column, and four metric alerts target Container Apps that do not exist yet | Alert definitions, plus run ordering |
| identity-service, approval-service, app-backend, worker-jobs (3809 to 3811, 3813) | Queue-time validation, zero minutes consumed | The `platformLibraries` pipeline resource cannot resolve a successful run | Clears itself |

The new finding is in app-frontend, which the previous note recorded as a single feed-permission failure. It is two defects. The second one matters more than the first. In `pipeline-templates/pipelines/extends/service.yml` the deploy stages carry no `dependsOn` and rely on file order, with a comment stating that this gives dev, then test, then prod. For the .NET services that is safe, because the stage before Deploy is `Package`, which depends on Build and Scan. For the single-page-app path there is no Package stage, so Deploy dev inherits the stage before it, which is `Scan`, and `Scan` declares `dependsOn: []` so that it runs in parallel with Build. The stage condition `succeeded()` therefore evaluated only Scan. A failed build did not stop a deployment. Run 3812 shows Build failed, Security scan succeeded, and Deploy dev running and then failing on the artifact it had no way to obtain.

Today this fails safely, because there is no artifact to deploy. It is still a gate that is not enforced, in a platform whose purpose is to demonstrate enforced gates.

Two confirmations are worth recording because they close off guesswork. The BCP332 error matches the suffix diagnosis to the character: the literal string `$(UniqueSuffix)` is exactly 15 characters, and the error reports a value of length 15 or more against a maximum of 8. And an independent read of the feed permissions returns three entries, two administrators and one identity at role `none`, with no Contributor or Reader for the build service. The grant has not been made.

The good numbers are real but narrow. Observability reached a Deploy stage and received a genuine ARM deployment response listing all eight alert resources, which means the path from pipeline to subscription is fully working and only the content is wrong. platform-libraries builds, tests, produces an SBOM, packs and passes its security scan, and fails only on the push. The templates pipeline has been green three waves running.

## Where we are going, and how it is coming out

The path to the first deployment is unchanged in shape and now fully specified. A seventh template release fixes four things: the feed URL scope, a distinct SARIF artifact name per image job, an explicit `dependsOn` of Build and Scan on every deploy stage, and the alert evaluation periods. A bootstrap change adds `UniqueSuffix` to the `meridian-shared` group and reconciles it with the `Meridian.` prefix the rest of that group uses. The platform owner grants the build service Contributor on the feed, which `tooling/Grant-FeedRole.ps1` will now attempt through four identity forms and report on. The pipelines then run in dependency order, infrastructure first and observability last, with the platform owner approving the shared stage when it pauses, which `tooling/Approve-PendingApprovals.ps1 -Wait` can now do unattended.

After that milestone the backlog is the known placeholder list: test and prod environment values, Entra app registrations for the services, a second release manager so prod can require two approvals, and pruning the six dead template tags.

The honest headline is that nothing has deployed and the platform has not moved in seven hours. The honest reading is that the pause is not a stall in the work. Every remaining move needs either a template release or an action from the platform owner, and the session that would have queued them had already closed. The trend is still convergence rather than thrash. Each wave has reached exactly one stage deeper than the last, from queue-time validation through validate, build and publish to deploy, and the v1.0.6 wave got a real deployment response out of Azure. Every cause on the table is a content or wiring defect. None is a design flaw. The one new finding is a genuine gap in enforcement, and finding it by reading the template rather than by watching a bad artifact reach an environment is the review process working as intended.

Three risks are worth naming. Hosted minutes are at 498 of 1800 for the month, all spent today, with one parallel job and roughly forty minutes per wave; three or four more waves of this size put the budget in question before the platform is green, which would force either slower iteration or the self-hosted agent move already costed in the companion assessment. Two actions in the critical path can only be performed by the platform owner, and the feed grant in particular has now failed through the API in every scripted form attempted, so it remains unproven that tooling can ever do it. And observability cannot go green until the services it watches exist, which is a structural ordering constraint rather than a defect, so it should be excluded from the definition of a successful next wave.

The second deliverable, the reference feedback log, now runs to seventeen sections: eleven numbered contexts and six addenda, recording where the reference documentation was right, silent or misleading. It remains the most complete artefact the project has produced.
