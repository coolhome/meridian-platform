# Rollout narrative, 2026-09-21 (third note)

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-22 03:55 UTC, after the templates v1.0.9 wave (runs 3962 to 3971) completed and the four services were probed in Azure |
| Sources | `docs/handoff-6.md`; git log `2afebd2..2e8bb39`; run timelines and `triggerInfo` for 3962 to 3984; task log of 3963; Container Apps, revision health and registry listings in the subscription; health endpoint probes; hosted resource usage; the azp-reference pages on trigger semantics and pipeline resources |
| Supersedes | `2026-09-19-rollout-narrative-2.md` |

## Where we were

The second note, written after the v1.0.6 wave, reported ten pipelines run, one green, nothing deployed, and six first-deploy causes confirmed to the log line. Two actions sat with the platform owner: a feed permission grant that the tooling had failed to make in every scripted form, and a missing variable in a bootstrap group. It named a gap in enforcement (deploy stages not gated on the build in the single-page-app path) and put hosted minutes at 498 of 1800.

Since then one working session produced five merges. Templates v1.0.7 fixed the six causes and made every stage dependency explicit. The feed grant turned out to have been automatable all along: the request body had been double-wrapped by a serialisation flag, and the service had been accepting it as "nothing to do" with a success code. v1.0.8 fixed a package cache key that matched nothing and a unique suffix that reached only one of three parameter files. A services change let them float on the newest library prerelease, because the release version they pinned does not exist yet. v1.0.9 removed a pipe into an early-exit command that was killing the image packaging job. Alongside, the repository gained a working agreement and a roster of ten agents, plus scripts that tear an environment down and build it again in dependency order.

## Where we are

The platform has deployed. The v1.0.9 wave took nine of ten pipelines to green, including all four .NET services end to end for the first time, and the four services are running as Container Apps in the dev environment with healthy endpoints. The one red pipeline is stopped by a subscription role that only the platform owner can grant.

| Pipeline or workstream | Stage reached | Cause | Owner of the fix |
| --- | --- | --- | --- |
| pipeline-templates-ci (3962) | Complete | Green, in every wave since the second note | None |
| platform-infrastructure (3963) | What-if shared | The shared pipeline identity cannot write policy assignments: Contributor excludes `Microsoft.Authorization/*/write`, and this is the first wave in which the identity rather than a person reached the policy module | Platform owner: grant Resource Policy Contributor to both pipeline identities (commands in handoff 6); the identity script already grants it for new environments |
| platform-libraries (3964) | Complete | Green; published prerelease 1.0.0-11 | None |
| containers-base-images (3970) | Complete | Green; the shared-stage approval was recorded unattended by the approvals script | None |
| app-frontend (3968) | Complete | Green, second wave in a row | None |
| identity-service, approval-service, app-backend, worker-jobs (3965 to 3969) | Complete | Green through build, scan, image and deploy; four Container Apps running, three ingress endpoints answer Healthy, the worker revision reports Healthy | None |
| observability (3971) | Complete | Green for the first time, without a re-run: its deploy stage ran after the Container Apps it monitors existed | None |
| Duplicate service runs (3976 to 3979, 3981 to 3984) | Queued | Every service is queued three times per wave: its own CI, the libraries publish trigger, and the base-image tag trigger | Fix on branch `fix/producer-triggers`, being merged |

Handoff 6 expected observability to stay red until a manual re-run; it went green on its own because the single hosted agent happened to reach its deploy stage last. The second note's judgement that the feed grant was "unproven that tooling can ever do it" was wrong, and the record now says why. The enforcement gap the second note found is closed: every deploy stage names its dependencies.

The finding of this wave was made by reading the trigger information on each run rather than its reason code. In every wave since v1.0.7, each service ran three times: once for its own change, once because the libraries pipeline had minted a new prerelease of unchanged code, and once because the base-image pipeline had re-promoted an unchanged channel tag. The Build API reports all of those runs as manual, so the wave tables read by run number never showed the pattern, and the redeploy script's detection of them had never matched. Two of the three sets are wasted. The fix stops the two producers from running on a template pin bump and keeps the triggers that make services rebuild when a library or base image really changes; it needs no template release and no change to the governance checks.

The good numbers: nine green pipelines out of ten, four services live, and hosted minutes at 859 of 1800 after five syncs in one day.

## Where we are going, and how it is coming out

The path to a fully green platform is one action. The platform owner runs the two role-assignment commands in handoff 6, granting Resource Policy Contributor to the shared and dev pipeline identities at subscription scope; the classifier that governs the agents' actions refuses Azure role assignments, so this cannot be scripted from the session. The next infrastructure run then passes the what-if, pauses for the shared approval, and deploys. Before that, the orchestrator merges the trigger fix, which cuts a wave from roughly twelve service runs to four and applies from the next pin bump.

After that milestone the backlog is unchanged: test and prod environment values, Entra app registrations for the services, a second release manager so prod can require two approvals, pruning the dead template tags, and the self-hosted agent move costed in the companion assessment.

The honest headline is that the platform works: a change flows from GitHub through the mirrors, the governed templates, the checks and an unattended approval into running services in Azure, with security scans, SBOMs and image promotion on the way. The honest reading is that convergence held: each of the four waves since the second note fixed one class of defect and reached one stage further, every cause was content or wiring rather than design, and the last one standing is a permission. The cost of getting there was higher than it needed to be. Roughly a third of the hosted minutes spent today went to duplicate service runs that nobody had noticed for four waves, because the evidence that distinguished them was one field deeper than the tables anyone was reading.

Three risks are worth naming. Hosted minutes stand at 859 of 1800 with about 80 minutes of already-queued duplicates still to run and nine days left in the month; without the trigger fix, two more waves would have consumed the rest. The base images rebuild every Sunday by schedule and their promotion waits for a Platform Engineering approval; unattended, that approval expires and the run fails, and attended, the promotion re-runs all four services by design, so the schedule costs about an hour a week and someone has to be there for it. And the hands-off mode has a floor: the classifier refuses role assignments and the cancelling of queued runs, so the two most cost-relevant actions of the day, granting a role and stopping duplicates, still needed a person.

The second deliverable, the reference feedback log, now runs to twenty sections: eleven numbered contexts and nine dated addenda, plus a separate field report of the items worth sending upstream. The newest addendum records that the reference's trigger rules named the double-run failure mode and settled whether the fix would fire on its own push, and that its identity cheat sheet describes the value inside a run while the API reports something else.

## Postscript, 2026-09-22 04:45 UTC

The one action closed within the hour. The platform owner granted the role at about 04:05 UTC; infrastructure run 3985, queued by the redeploy script, passed every stage including the shared deployment, with the approval recorded unattended at 04:37 UTC. Every one of the eleven pipelines has now had a green run and the dev environment is fully deployed. The trigger fix merged as PR #9 and its own mirror push queued no pipeline, as predicted. The eight duplicate runs finished green and cost the expected minutes; the meter stands at 941 of 1800. The redeploy script's first live use found one defect of its own, a strict-mode read of a property the run API does not return, after the run had already succeeded; the fix is small and in review.
