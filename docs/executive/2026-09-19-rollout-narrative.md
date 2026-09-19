# Rollout narrative, 2026-09-19

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-19 19:10 UTC, after the templates v1.0.6 wave (runs 3808 to 3817) completed |
| Sources | `docs/handoff.md` to `docs/handoff-4.md`; git log `44d25fd..222e216`; Azure Pipelines run timelines and task logs; project variable groups |
| Supersedes | none (first narrative) |

## Where we were

Meridian started this morning as an empty folder. The goal was a small approval application built as a reference platform, to exercise Azure DevOps governance as hard as possible and to grade the azp-reference documentation while doing it. GitHub holds the source of truth as one monorepo. Azure DevOps is the execution plane, with each of the eleven top-level folders mirrored to its own Azure Repo, pipelines, branch policies and environments.

Three working sessions got us from nothing to a fully wired platform. Session one scaffolded the monorepo, wrote seven architecture decision records, bootstrapped the Azure DevOps project from files, and deployed the shared and dev Azure footprint directly. Session two mirrored all eleven repos, created twenty pipeline definitions, applied branch policies as code, and then had to teach the sync identity to bypass the very policies it had just applied. Session three got the sync green, obtained the subscription roles and team membership that only a human could grant, and ran the first real pipelines. The result was six template releases in one afternoon, each fixing what the previous wave surfaced.

## Where we are

The sixth template release was the first wave in which every pipeline ran to a real outcome. It finished at about 19:10 UTC, after the session that queued it had closed. Ten pipelines ran, one succeeded, and the rest failed for reasons traced to the log line.

| Pipeline | Stage reached | Cause | Owner of the fix |
| --- | --- | --- | --- |
| pipeline-templates-ci | Complete | Green | None |
| platform-libraries | Publish | NuGet push used the org-scoped feed URL; the feed is project-scoped | Template, next release |
| app-frontend | Build | Build service lacks Reader on the feed | Platform owner, portal grant |
| containers-base-images | Build | Two parallel image jobs publish an artifact with the same name | Template, next release |
| platform-infrastructure | What-if shared | The shared variable group has no UniqueSuffix, so Bicep got the unexpanded placeholder | Bootstrap config |
| observability | Deploy dev | Four alerts use two evaluation periods without a timestamp column; four target Container Apps that do not exist yet | Alert definitions plus run ordering |
| Four dotnet services | Queue | Depend on a library run that has not yet succeeded | Clears itself |

Two of these were misattributed in the last handoff. The library publish and the infrastructure what-if were both assumed to be the feed permission problem. They are not. One is a URL scoping defect in the template and one is a missing variable in the bootstrap. The feed permission is still real, but it only blocks the frontend and, later, the library push.

The one genuinely good number is that observability reached a Deploy stage and spoke to Azure. No run had got that far before.

## Where we are going, and how it is coming out

The path to the first real deployment is short and known. A seventh template release fixes the feed name, the artifact collision and the alert definitions. A bootstrap change adds the suffix to the shared variable group. The platform owner grants the build service Contributor on the feed, which is the only step the tooling cannot perform. Then the pipelines run in dependency order: infrastructure, base images, libraries, the four services, the frontend, and observability last, since its alerts need the services to exist. The platform owner approves the shared stage when it pauses.

After that, the backlog is the known placeholder list: test and prod environment values, Entra app registrations for the services, a second release manager so prod can require two approvals, and pruning the six dead template tags.

The honest headline is that after three sessions nothing has deployed. The honest reading of that headline is more favourable. Every failure so far has been a first-run defect in content or wiring, not a design flaw. The governance layer worked the first time it was exercised: workload identity login from a pipeline, required-template and branch-control checks, and approvals all behaved as designed. Each wave has reached exactly one stage deeper than the last, from queue-time validation to validate, build, publish and now deploy. That is the shape of a platform converging, not one thrashing.

Three risks are worth naming. A single hosted agent means each wave takes about forty minutes end to end, so iteration is slow and the monthly minutes budget deserves a check before the next wave. The automation sandbox refuses to queue runs or grant permissions, so every wave still needs a human in the loop for two actions. And a one-person organisation trips over approval rules written for teams, which is a design tension we will keep meeting until test and prod have real approvers.

The second deliverable, the reference feedback log, is in good shape. It now covers ten contexts plus five addenda and records where the reference documentation was right, silent, or misleading.
