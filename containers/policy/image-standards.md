# Image standards

Every image that runs in a Meridian environment must:

1. **Start from a governed base** in the shared registry (`base/dotnet-aspnet:10.0`,
   `base/dotnet-runtime:10.0`). Service Dockerfiles take it as the `BASE_IMAGE` build arg,
   with a public fallback only for local builds. The pipeline always injects the governed one.
2. **Run as non-root** (`USER $APP_UID` on chiseled images, explicit `useradd` elsewhere).
3. **Contain no compiler, package manager or shell** at runtime. Build happens on the agent
   (already tested output is copied in), never inside the runtime image.
4. **Carry OCI labels**: title, version, revision, base name, base digest.
5. **Pass Trivy** with zero CRITICAL fixed vulnerabilities before the channel tag moves.
6. **Be pulled by digest or immutable tag** in Container Apps: services deploy
   `services/<name>:<build number>`, never `latest`.
7. **Be rebuilt when upstream changes** (ACR Task base-image trigger) and at least weekly
   (scheduled pipeline run), and services rebuild through the `resources.containers` trigger.

Upstream channel pinning versus digest pinning: base Dockerfiles pin the channel tag and
record the resolved digest as a label at build time. Renovate-style digest bumps are a
follow-up once the platform has a bot identity.
