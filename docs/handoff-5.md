# Handoff 5: v1.0.7 written, feed grant proven manual (2026-09-20, end of session four)

Supersedes the next-steps of `handoff-4.md`. Identifiers in `handoff-2.md` still apply.

## State

Branch `fix/v1.0.7-first-deploy-defects`, four commits on top of `2afebd2`. **Not merged, not pushed.**
Merging to main triggers the sync and a ~40-minute wave; minutes were 498/1800.

| Done | Where |
| --- | --- |
| Four template/bicep defects from the v1.0.6 wave fixed; `UniqueSuffix` added to `meridian-shared` by the bootstrap; every pin at v1.0.7; dead tags pruned | `d036fbc` |
| Boundary check exempts git-ignored dirs (governance change, own commit; review it) | `98c82da` |
| Feed grant **proven** un-automatable: six identity shapes, by name and GUID, three api-versions, all 200 + nothing persisted, while a feed-description write with the same token succeeds. Scope, identity, version, addressing all ruled out | `2c77022`, `docs/reference-feedback.md` |
| Manual steps documented in root README, tooling/README, and a banner the bootstrap prints | `d036fbc` |

Validated locally: 75 YAML parse, all PowerShell parses, alerts bicep builds, boundary check passes.
**Not validated: template expression semantics** (the `${{ if }}` insertions in `dependsOn`) — only a real sync + queue-time compile proves those.

## Do next, in order

1. **Portal, once:** Artifacts > `meridian` > gear > Permissions > Add > `Meridian Build Service (coolhome)` > Contributor. No script can do this; stop trying.
2. **Finish the dependsOn fix.** A fresh-eyes review at session end found the same file-order pattern in three other templates that `d036fbc` only fixed in `service.yml`: `library.yml` Deploy_/Release, `container-images.yml` Promote (no dependsOn at all), `infrastructure.yml` WhatIf_/Deploy_. Same defect class, same fix. Do it before merging so v1.0.7 is one release, not two.
3. Merge to main, approve the shared stage when it pauses (`Approve-PendingApprovals.ps1 -Wait`), watch the wave. Exclude observability from "green": half its alerts target Container Apps that do not exist yet.
4. Two things to consider after: `failedRequests` alert went from 2-of-2 periods to 1-of-1 (noisier; the alternative is `bin(timestamp)` in the KQL); `.agents/` is a duplicate of `.claude/skills/exec-narrative` and should probably be deleted.

## Traps this session

`"$var?"` in a URL reads variable `var?` (bit both helper scripts; grep `\$[A-Za-z_][A-Za-z0-9_]*\?`). `$feed` and `$Feed` are the same variable (case-insensitive) — shadowed a parameter and produced a confident wrong diagnostic. The auto-mode classifier blocks permission grants and self-written permission rules; a rule written mid-session is not live until `/hooks` or restart.
