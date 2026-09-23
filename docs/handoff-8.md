# Handoff 8: the pool's first real wave breaks on a hidden .NET runtime, gets fixed, and needs manual re-queues (2026-09-23, session seven)

Supersedes the next-steps of `handoff-7.md`. Identifiers in `handoff-2.md` still apply.

## The finding that matters

**The agent image's own `apt-get install dotnet-runtime-8.0` hid the .NET 10 SDK it was built
on.** The runtime package pulls in `dotnet-host`, which repoints `/usr/bin/dotnet` to
`/usr/lib/dotnet` — a runtime-only install — so the base image's 10.0 SDK muxer stopped
resolving. This is exactly the failure mode the agent pool build had not yet exercised: the
first production wave on the pool (PR #16, templates v1.1.0, all consumers `agentPool:
platform`) failed GitVersion in 5 of 6 consumer pipelines within 2-3 seconds, "No .NET SDKs
were found", exit 145. Ops and platform-dev diagnosed that root cause from the GitVersion log
line plus the agent Dockerfile, not from a deeper probe. The first fix attempt (a full
runtime-tarball extraction in place of the apt install) carried a latent defect of its own: the
reviewer's `podman` test on that build showed the 10.0 SDK still listed and GitVersion still
installing fine, but the full tarball had downgraded the muxer (`/usr/share/dotnet/dotnet`) to
the 8.0.31 one (plus its LICENSE/ThirdPartyNotices); it kept working only because the muxer loads
the highest available `hostfxr` (10.0.12) — nothing visibly failed. Caught before shipping, not
because anything broke. `ea2d109` corrected it to extract only `./shared/Microsoft.NETCore.App/8.0.31` from the
sha512-checked tarball, leaving the base image's muxer untouched; that landed as PR #19
(`0c5eadb`). Ops built and verified `azp-agent:1.0.1` with `az acr run` before merge (SDK
10.0.401, runtimes 8.0.31 + 10.0.12).

Second, corrected after this handoff's first draft: the `batch: true` CI trigger **did** fire for
the PR #19 mirror commit. Run 4032 (`platform-infrastructure-cicd`, `batchedCI`, sourceVersion
`2165329`) queued 02:47:36 and went green 03:07:06, rolling both agent jobs to `azp-agent:1.0.1`.
The ops watcher's run listing (a sorted top-N) missed it mid-session, so the orchestrator queued a
second, redundant run (4035, same commit) by hand; both went green and the owner approved both
Deploy shared stages. The lesson is not about trigger reliability — it is to identify a specific
commit's run by sourceVersion (`az pipelines runs list --status all`, filtered to the commit or
branch in question), not by scanning a fixed-size top-N listing that can hide the run you are
looking for behind others queued around the same time.

Third, smaller but recurring: the classifier refused `Approve-PendingApprovals.ps1 -Wait`
("Production Deploy") this session despite the settings allowlist, the same pattern
`handoff-7.md` documented for `Remove-AzureEnvironment.ps1`. The orchestrator did not retry it;
the owner approved both shared deployments directly in the portal instead.

## State

`main` at `4be9f74`. Since `handoff-7.md` (`67cdb57`, session six close, no owner action open
against `main` itself):

| Commit | PR | What | Merged |
| --- | --- | --- | --- |
| `40f871b` | #18 | docs: `handoff-7.md` and a postscript to the fourth narrative | before session seven started |
| `d6ecc1f` | #15 | `pipeline-templates-ci` moved onto the `meridian-agents` pool (proof run) | ~01:00 UTC |
| `215be4c` | #16 | Templates v1.1.0: every consumer opts into `agentPool: platform`; hadolint, SWA CLI and NuGet steps without Docker or duplicates | ~00:32 UTC (queued the wave; see below) |
| `0c5eadb` | #19 | Agent image 1.0.1: drop the apt `dotnet-runtime-8.0` install that hid the .NET 10 SDK | ~02:50 UTC |
| `4be9f74` | #17 | `app-backend` and `worker-jobs` derive sibling URLs from the environment domain | ~04:25 UTC |

No held, unmerged branches remain from this session.

Worktrees safe to remove now (their PRs are merged): `azp-test-proof` (#15), `azp-test-templates`
(#16), `azp-test-agentimg` (#19), `azp-test-services` (#17).

Hosted minutes: 994 of 1800 at the start of the session, **1007 of 1800 now** (live read). Only
`governance-ci` ran hosted this session, by design (~8s per job); that accounts for only part of
the 13-minute increase, leaving roughly 6 minutes unattributed — see Backlog.

The fifth executive narrative, `docs/executive/2026-09-23-rollout-narrative.md`, and a
narrative-2 in progress, both cover this session but were uncommitted as of this write-up
(another scribe pass); treat this handoff as the source for exact run numbers and the current
wave state.

## What happened, in order

| Done | Where |
| --- | --- |
| Infra run 3997 green: created `caj-mrd-shared-agent` and `caj-mrd-shared-agent-placeholder` | ops, live `rg-mrd-shared-platform` |
| `Initialize-AgentPool.ps1 -RegisterPlaceholder` succeeded; `placeholder-agent` registered in pool `meridian-agents` (14), offline/enabled | ops, pool state |
| PR #15 merged (`d6ecc1f`): `pipeline-templates-ci` run 4016 green on the pool — ephemeral KEDA agents, ~90s cold start per job, 0 hosted minutes | run 4016 |
| PR #16 merged (`215be4c`): templates v1.1.0, all consumers pinned with `agentPool: platform` | wave 4017-4025 |
| Wave result: `governance-ci` (hosted by design), `pipeline-templates-ci`, `observability` (4025) green; `identity-service`, `approval-service`, `app-backend`, `worker-jobs`, `app-frontend` (4020-4024) failed at GitVersion in 2-3s, "No .NET SDKs were found", exit 145; `platform-libraries` and `containers` correctly did not fire (path filters) | live run logs |
| Root cause diagnosed: apt `dotnet-runtime-8.0`'s `dotnet-host` dependency repointed `/usr/bin/dotnet` to the runtime-only `/usr/lib/dotnet`, hiding the base image's 10.0 SDK muxer | ops / platform-dev, from the GitVersion log line and the agent Dockerfile |
| First fix (full runtime-tarball extraction) carried a latent defect: reviewer's `podman` test showed the SDK still listed and installs still working, but the tarball had downgraded the muxer to 8.0.31 — it worked only because hostfxr resolves the highest version present; caught before shipping, not from a failure. Corrected in `ea2d109` to extract only `./shared/Microsoft.NETCore.App/8.0.31` | reviewer, `podman` extraction; `containers/agents/azp-agent` |
| PR #19 merged (`0c5eadb`): agent image 1.0.1 — no apt `dotnet-*`, only `./shared/Microsoft.NETCore.App/8.0.31` from a sha512-checked tarball; `agentImageTag` bumped to 1.0.1 | `containers/agents/azp-agent`, image `sha256:65e14a4a...afdf` |
| ops verified `azp-agent:1.0.1` before merge: `az acr run --cmd "--entrypoint bash <image> -lc ..."` showed SDK 10.0.401, runtimes 8.0.31 + 10.0.12 | ACR `acrmrdshared` |
| Owner approved run 4019 (Deploy shared, pre-fix commit), green ~02:47 UTC | portal approval |
| Run 4032 (`platform-infrastructure-cicd`, `batchedCI`, sourceVersion `2165329` = PR #19 mirror commit) queued 02:47:36, green 03:07:06 — the `batch: true` trigger firing correctly; rolled both agent jobs to `azp-agent:1.0.1` | run 4032 |
| Run 4035, same commit, queued 03:05 before 4032's completion was noticed — a redundant duplicate, not a missed-trigger recovery; also green (03:22); owner approved both Deploy shared stages | run 4035 |
| Manual re-runs queued on `main`, 4036-4040 (identity-service, approval-service, app-backend, worker-jobs, app-frontend) — **all five green end to end on the pool**, last (4040) finished 04:17:41 UTC, ~53 min serial for the batch. 4040 succeeded through Deploy dev: the first real SWA CLI deploy on the pool (v1.1.0 replaced `AzureStaticWebApp@0`, which needs Docker, with `npx @azure/static-web-apps-cli@2.0.10 deploy`). Hosted meter moved 1005 → 1007 across the five | runs 4036-4040 |

## Owner actions

1. **Decide how shared approvals run.** The portal works and was used twice this session; the
   `Approve-PendingApprovals.ps1 -Wait` script is refused by the classifier despite the settings
   allowlist. Either accept portal-only approvals or adjust the allow rule.
2. **Unblock the teardown/redeploy exercise** (carried from `handoff-7.md`, still open): allow
   `pwsh ./tooling/Remove-AzureEnvironment.ps1*` and `pwsh ./tooling/Start-EnvironmentDeploy.ps1*`
   in `.claude/settings.local.json`, or run the teardown directly.

## Do next, in order

1. Read the runs PR #17 fired (`app-backend-cicd`, `worker-jobs-cicd`) on the pool — merged
   ~04:25 UTC as `4be9f74`, an ops agent is watching, results were not in as of this write-up.
2. ~~Merge PR #17.~~ **Done**: `4be9f74`, ~04:25 UTC.
3. ~~Confirm run 4040 (app-frontend) finished green.~~ **Done**: 4036-4040 all green end to end,
   last finished 04:17:41 UTC; 4040 is the first real SWA CLI deploy on the pool.
4. Commit the fifth and sixth executive narratives and this handoff in one docs PR.
5. Remove the four merged worktrees (`azp-test-proof`, `azp-test-templates`, `azp-test-agentimg`,
   `azp-test-services`) and their local branches.
6. Work the backlog below, roughly in the order listed.
7. Resume `handoff-7.md`'s owner action 2 (teardown/redeploy) once the pool has carried a few
   more ordinary waves — unchanged reasoning from last session.

## Backlog

* Bring `containers/agents/azp-agent/` under the governed containers pipeline instead of a manual
  `az acr build` — would have caught the dotnet-runtime defect with the existing SARIF scan and
  Promote gate, carried forward from `handoff-7.md` — platform-dev.
* `steps/gitversion.yml` runs `dotnet tool install GitVersion.Tool`, which is redundant: the base
  image already has it in `/opt/dotnet-tools` — pipelines-dev.
* Decide on a warm-agent vs. cold-start tradeoff for the KEDA-scaled job (~90s cold start per job
  observed on run 4016) — platform-dev / owner.
* Account for the ~6 unattributed hosted minutes this session (only `governance-ci` should have
  run hosted) — ops.
* Carried unchanged from `handoff-7.md`: the dev teardown test, `app-backend`/`worker-jobs`
  sibling Bicep redeploy-ordering dependency, `test`/`prod` environment values, Entra app
  registrations for the four services, a second release manager, and any now-dead template tags
  left over once every consumer is confirmed on v1.1.0.

## Traps this session

* **An `apt install` of a runtime package can silently replace an SDK's `dotnet` muxer.**
  `dotnet-runtime-8.0`'s `dotnet-host` dependency repointed `/usr/bin/dotnet` to a runtime-only
  install, hiding the base image's .NET 10 SDK. GitVersion failed in seconds with "No .NET SDKs
  were found"; ops and platform-dev traced that straight to the apt install from the log line and
  the agent Dockerfile, no deeper probe needed. Any future custom agent image that installs a
  `dotnet-runtime-*` package alongside an SDK-bearing base image needs this check.
* **Verify what a fix writes to disk, not only that it works.** The first fix swapped the apt
  install for extracting the *whole* runtime tarball, which downgraded the muxer
  (`/usr/share/dotnet/dotnet`) to 8.0.31 — but the build still worked, because the muxer loads the
  highest `hostfxr` present (10.0.12), so nothing visibly failed. The defect was latent, not a
  failure; only the reviewer's `podman` test, which inspected the built image instead of trusting
  that it worked, caught the downgrade before it shipped. `ea2d109` fixed it for real by
  extracting only the one runtime folder needed. A fix that "removes the bad step" and still
  passes needs its output inspected, not just its pipeline result.
* **`az.cmd` strips backslash-escaped quotes inside `--cmd`.** Verifying `azp-agent:1.0.1` with
  `az acr run --cmd "--entrypoint bash <image> -lc ..."` needed the payload base64-encoded and
  decoded inside the container; a literal escaped-quote payload was silently mangled before it
  reached the image.
* **Identify a commit's run by sourceVersion, not by scanning a sorted top-N listing.** Run 4032
  was the real `batch: true` trigger firing for the PR #19 mirror commit (queued 02:47:36, green
  03:07:06, rolled both agent jobs to `azp-agent:1.0.1`), but a fixed-size run listing missed it
  mid-session, so the orchestrator queued a redundant duplicate (4035) by hand. Use
  `az pipelines runs list --status all` filtered to the sourceVersion (or repository/branch) in
  question when checking whether a specific commit's run exists, not a sorted top-N.
* **A classifier refusal on an allowlisted command is still final, not a bug to route around.**
  `Approve-PendingApprovals.ps1 -Wait` was refused twice this session despite the settings allow
  rule (same "Production Deploy" refusal class as `handoff-7.md`'s `Remove-AzureEnvironment.ps1`
  finding). The orchestrator did not retry; the owner approved in the portal both times. Treat
  every refusal as final regardless of what the settings file says it should do.
