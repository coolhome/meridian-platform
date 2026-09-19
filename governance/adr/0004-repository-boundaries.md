# ADR 0004: Repository boundaries

**Status:** Accepted, 2026-09-19

## Decision

1. **A folder never references another folder by path.** No `../other-folder` in `csproj`,
   `Dockerfile`, YAML, TypeScript or Bicep. `tooling/Test-RepoBoundaries.ps1` fails CI on it.
2. **Shared code is a package.** `Meridian.ServiceDefaults` and `Meridian.Messaging.Contracts`
   are NuGet packages built from `platform-libraries` and published to the `meridian` Azure
   Artifacts feed. Services consume them through `nuget.config` with package source mapping
   (`Meridian.*` only from the feed, everything else only from nuget.org) to block dependency
   confusion.
3. **Shared pipeline logic is a template repository** (ADR 0002).
4. **Shared infrastructure is a contract of names.** Platform infrastructure creates shared
   resources with deterministic names; service `infra/main.bicep` files reference them with
   `existing` and never redeclare them.
5. **Message shapes are owned by the producer's contract package**, with JSON Schema published
   alongside and a contract test that fails when the C# type and the schema drift.
6. **Every mirrored folder carries the same governance overlay** (PR template, editorconfig,
   gitattributes, SECURITY.md) stamped from `governance/templates/overlay`. Drift fails CI.
7. **Required files per tier** (README, `azure-pipelines.yml`, and for .NET `global.json`,
   `Directory.Build.props`, `nuget.config`, lock files) are checked by the same script.
