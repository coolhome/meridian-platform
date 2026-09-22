# Repository boundaries

ADR 0004 is the decision. This page lists what the boundary check actually tests.

`tooling/Test-RepoBoundaries.ps1` runs in GitHub PR validation and fails on:

1. A relative path in any text file that resolves outside the folder it lives in.
2. A mirrored folder missing a required file for its tier.
3. A file under `governance/templates/overlay` whose stamped copy in a mirrored folder differs.
4. A top-level folder that is not listed in `repos.manifest.json` (allow-list: `.github`,
   `.claude`, `docs`). A directory git ignores (for example `.agents/`) is skipped: it is never
   committed or mirrored, so it cannot cross a repo boundary.
5. A pipeline path in the manifest that does not exist.
6. An `azure-pipelines.yml` that does not `extends:` a template from the templates repository,
   or pins a different `ref:` than the manifest's `templatesRef`.
7. A `resources.repositories` entry pointing at the templates repo without `ref:`.

Run it locally with:

```bash
pwsh ./tooling/Test-RepoBoundaries.ps1
```
