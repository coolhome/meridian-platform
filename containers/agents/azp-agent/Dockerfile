# syntax=docker/dockerfile:1.7
# Self-hosted Azure Pipelines agent for pool "meridian-agents" (platform-infrastructure's
# caj-mrd-shared-agent / caj-mrd-shared-agent-placeholder Container Apps jobs, shared tier).
#
# Built on the platform's own build-tools image so the toolchain every pipeline-templates/ job
# already assumes (.NET 10 SDK, Node 24, PowerShell, GitVersion, CycloneDX, non-root "builder"
# user) is present without every job re-downloading it. This Dockerfile adds what the templates
# need beyond that: Azure CLI, a pinned bicep binary, the hadolint and Azure Pipelines agent
# binaries (all pinned and sha256-checked except Azure CLI itself, per pipeline-templates/steps/
# and jobs/ below), and the small utilities several steps shell out to. Trivy, UseDotNet@2,
# NodeTool@0/UseNode@1 and NuGetAuthenticate@1 install themselves into the agent's own work folder
# at run time (that is how they behave on Microsoft-hosted agents too); this image only needs to
# make that folder writable by the user the agent runs as.
#
# Tool inventory derived from pipeline-templates/ (steps/, jobs/, pipelines/extends/,
# azure-pipelines.yml):
#   - Azure CLI + bicep: steps/bicep-deploy.yml, steps/bicep-validate.yml,
#     steps/container-build-push.yml, steps/container-scan.yml (az acr login --expose-token),
#     jobs/deploy-container-app.yml, pipelines/extends/container-images.yml Promote stage. The
#     azure-devops extension is not used anywhere (no `az pipelines`/`az devops` calls;
#     pipeline-templates-ci's own preview-compile step talks to the REST API directly with
#     System.AccessToken), so it is deliberately not installed.
#   - jobs/deploy-static-site.yml uses `az staticwebapp secrets list` (covered by Azure CLI above)
#     but its actual upload step is AzureStaticWebApp@0, which runs `docker run` internally —
#     Container Apps jobs cannot do that. This pool cannot run that job until pipelines-dev lands
#     templates v1.1.0, which switches it to `npx @azure/static-web-apps-cli deploy`; on `main`
#     today it still calls AzureStaticWebApp@0, so a service's static-site deploy stage should stay
#     off this pool until that tag ships.
#   - jq: steps/bicep-deploy.yml (parses deployment outputs into ##vso[task.setvariable]).
#   - curl: gitversion.yml, sbom-dotnet.yml (dotnet tool install), container-scan.yml and
#     security-scan.yml (trivy/gitleaks downloads), smoke-test.yml, tag-release.yml, this
#     Dockerfile's own hadolint/bicep/agent downloads.
#   - git: steps/checkout.yml, steps/tag-release.yml.
#   - unzip / zip: Microsoft's own note for ArchiveFiles/ExtractFiles-shaped steps; no template
#     here calls those tasks directly today, kept for whatever a consumer's preBuildSteps allow
#     list (jobs/governance-prebuild-steps.yml: CopyFiles@2, ExtractFiles@1) exercises.
#   - ca-certificates, libicu74: TLS for every curl/az/dotnet/npm call above and the .NET agent
#     runtime itself; libicu74 is Ubuntu 24.04's package name (the agent image is noble, same as
#     the build-tools base).
#   - .NET 8 runtime (installed as a pinned, sha512-checked tarball into the SDK's own
#     /usr/share/dotnet, not via apt): NuGetAuthenticate@1's Azure Artifacts credential provider
#     is a .NET 8 tool it installs on first use; see the comment by that install step below for
#     why this is not the dotnet-runtime-8.0 apt package.
#   - pipx: pipeline-templates-ci's own Lint job (`pipx install yamllint==1.35.1`) — this pool's
#     first consumer per the capacity assessment, so it needs to work from day one even though no
#     step under pipeline-templates/steps/ or jobs/ calls it.
#   - hadolint binary: pinned, sha256-checked, replaces `docker run hadolint/hadolint:v2.12.0` in
#     pipelines/extends/container-images.yml once pipelines-dev's templates v1.1.0 makes that swap
#     (Container Apps jobs cannot run Docker-in-container) — on `main` today that step still runs
#     `docker run`, so this only helps once that tag lands. Same v2.12.0 pin as the docker run
#     today, and the same `--failure-threshold warning` gate that step already applies.
#   - bicep binary: pinned, sha256-checked; see the comment by its install step below for why it is
#     a plain binary on PATH rather than `az bicep install`.
#   - Azure Pipelines agent binary: pinned Linux x64 build, sha256-checked, unpacked at build time
#     so start.sh never downloads it at container start.
ARG UPSTREAM=acrmrdshared.azurecr.io/base/build-tools:10.0
# The tag is pinned in the ARG default above; DL3006 cannot see through the ARG (same as
# base-images/build-tools/Dockerfile).
# hadolint ignore=DL3006
FROM ${UPSTREAM}

ARG APP_VERSION=0.0.0-local
ARG VCS_REF=unknown
ARG HADOLINT_VERSION=2.12.0
ARG HADOLINT_SHA256=56de6d5e5ec427e17b74fa48d51271c7fc0d61244bf5c90e828aab8362d55010
ARG AZP_AGENT_VERSION=4.275.0
ARG AZP_AGENT_SHA256=416eb9340385d599e3159b86d08c03754af24d1cb2b6624425142a47ca65f346
ARG BICEP_VERSION=0.47.16
ARG BICEP_SHA256=64c345a58e0c3e48b1bc98a4e62d6b3adb1d238281297de3400aeafb2697aa5a
# Microsoft's own release manifest (dotnet/core release-notes/8.0/releases.json) publishes this
# artifact's checksum as sha512, not sha256, so this one pin is verified with sha512sum -c instead
# of matching the sha256 style of the other pins in this file; see the comment by the install step.
ARG DOTNET_RUNTIME8_VERSION=8.0.31
ARG DOTNET_RUNTIME8_SHA512=f336bdec58d54bf50d74a1b38efa82f7290d976bd2ed98b845ebcbac42cf0d8cef504684fc088d4b05f98737b996bf3302e52bd9c23005deae7c60780b2652fb

LABEL org.opencontainers.image.title="meridian/agents/azp-agent" \
      org.opencontainers.image.description="Self-hosted Azure Pipelines agent, pool meridian-agents" \
      org.opencontainers.image.vendor="Meridian Platform Engineering" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.base.name="${UPSTREAM}" \
      meridian.image.tier="agent"

# pipx (installed below) puts its shims here by default only when this is set before install;
# under `bash --noprofile --norc` (how the agent runs job scripts) nothing sources a profile to
# add ~/.local/bin to PATH, so a pipx-installed command like yamllint would otherwise not be found.
ENV PIPX_BIN_DIR=/usr/local/bin

# The base image ends USER builder; every install below needs root.
USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq libicu74 pipx unzip zip \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# .NET 8 runtime for NuGetAuthenticate@1's Azure Artifacts credential provider, which is itself a
# .NET 8 tool it installs on first use — without a matching runtime already on the image, every
# job that restores from the feed would eat the provider's own download-and-first-run cost.
#
# This is deliberately NOT `apt-get install dotnet-runtime-8.0` (what runs 4020-4024 on this pool
# shipped with, and the cause of "No .NET SDKs were found" from every dotnet invocation, including
# steps/gitversion.yml's `dotnet tool install --global GitVersion.Tool`). The base image
# (mcr.microsoft.com/dotnet/sdk:10.0-noble, via base-images/build-tools/Dockerfile) installs the
# 10.0 SDK by extracting Microsoft's own tarball into /usr/share/dotnet and symlinking
# /usr/bin/dotnet to /usr/share/dotnet/dotnet — no /etc/dotnet/install_location file, because (per
# Microsoft's own distribution-packaging doc) that file "is not necessary... when the root is
# /usr/share/dotnet". The dotnet-runtime-8.0 *apt* package pulls in dotnet-hostfxr-8.0, which pulls
# in dotnet-host as a dependency; per the same doc, the dotnet-host package owns /usr/bin/dotnet,
# the man page, AND /etc/dotnet/install_location. Debian/Ubuntu's Microsoft-feed packages lay their
# files under /usr/lib/dotnet, so apt's postinst overwrites /usr/bin/dotnet to point there and
# writes /etc/dotnet/install_location=/usr/lib/dotnet. Every subsequent `dotnet` invocation resolves
# through that install_location, which has a .NET 8 runtime but no SDK at all (the 10.0 SDK is
# still sitting, untouched, under /usr/share/dotnet/sdk) — hence zero SDKs found, on the very first
# dotnet command in the job, in ~2-3s (the apt package's postinst runs at image build time, so every
# container from this image is affected identically; this is not a race or a per-run flake). This
# is the same class of problem Microsoft documents at
# https://learn.microsoft.com/dotnet/core/install/linux-package-mixup — two .NET installs with
# different disk layouts on one machine — except both sides here are Microsoft's own distribution,
# just via different mechanisms (Docker-image tarball vs. apt).
#
# The fix: extract ONLY the .NET 8 shared framework directory from the pinned, sha512-checked
# tarball into the SDK's own /usr/share/dotnet — not the whole archive. A dotnet-runtime tarball
# also carries its own ./dotnet (the muxer), ./LICENSE.txt, ./ThirdPartyNotices.txt and
# ./host/fxr/<fxr version>; extracting the full tarball was tried first and rejected in review
# (tested with podman against mcr.microsoft.com/dotnet/sdk:10.0-noble): it silently overwrites
# /usr/share/dotnet/dotnet with the 8.0 build's muxer binary, and only kept working because the
# resulting host still finds and loads host/fxr/10.0.12 (the higher of the two fxr versions now on
# disk) — an implicit, untested dependency on host-selection behaviour, not something this fix
# should rely on. hostfxr resolves a "Microsoft.NETCore.App" 8.x framework reference by scanning
# shared/Microsoft.NETCore.App/<version> directories under the one dotnet_root regardless of which
# hostfxr build is loaded, so the 8.0 tarball's own muxer and host/fxr copies buy nothing here.
# Extracting only shared/Microsoft.NETCore.App/${DOTNET_RUNTIME8_VERSION} leaves /usr/bin/dotnet,
# /usr/share/dotnet/dotnet, host/fxr/* and /etc/dotnet/install_location exactly as the base image
# built them: `dotnet --list-sdks` keeps seeing the 10.0 SDK through the base image's own,
# untouched muxer, and `dotnet --list-runtimes` gains the 8.0 framework the credential provider
# needs. `-o` on tar matches the official SDK image's own extract step (skip restoring the
# archived owner/group; everything here ends up root:root, same as the rest of /usr/share/dotnet
# from the base image).
RUN curl -fsSL -o /tmp/dotnet-runtime-8.0.tar.gz "https://builds.dotnet.microsoft.com/dotnet/Runtime/${DOTNET_RUNTIME8_VERSION}/dotnet-runtime-${DOTNET_RUNTIME8_VERSION}-linux-x64.tar.gz" \
 && echo "${DOTNET_RUNTIME8_SHA512}  /tmp/dotnet-runtime-8.0.tar.gz" | sha512sum -c - \
 && tar -oxzf /tmp/dotnet-runtime-8.0.tar.gz -C /usr/share/dotnet "./shared/Microsoft.NETCore.App/${DOTNET_RUNTIME8_VERSION}" \
 && rm /tmp/dotnet-runtime-8.0.tar.gz

# Azure CLI: Microsoft's own apt-based installer (system-wide, needs root); cleans up its own apt
# lists in this layer too, since it runs `apt-get install` internally and would otherwise leave a
# second copy of the package cache behind.
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
 && rm -rf /var/lib/apt/lists/*

# hadolint: pinned binary, sha256-checked against the file this step actually downloaded.
RUN curl -fsSL -o /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
 && echo "${HADOLINT_SHA256}  /usr/local/bin/hadolint" | sha256sum -c - \
 && chmod +x /usr/local/bin/hadolint

# az bicep install caches the bicep CLI under $HOME/.azure/bin, keyed to whichever user and
# AZURE_CONFIG_DIR ran it; AzureCLI@2 gives each step a fresh AZURE_CONFIG_DIR, so that cache is
# never seen again and every job would re-download bicep. Installing the pinned binary on PATH
# instead is what az's own bicep wrapper looks for first when TF_BUILD is set (true in every
# pipeline job) — no install step, no per-job network call.
RUN curl -fsSL -o /usr/local/bin/bicep "https://github.com/Azure/bicep/releases/download/v${BICEP_VERSION}/bicep-linux-x64" \
 && echo "${BICEP_SHA256}  /usr/local/bin/bicep" | sha256sum -c - \
 && chmod +x /usr/local/bin/bicep

# Azure Pipelines agent: pinned Linux x64 build, sha256-checked, unpacked into /azp. start.sh
# (COPYed below) configures and runs it; it never fetches its own agent bits at container start.
RUN mkdir -p /azp \
 && curl -fsSL -o /tmp/vsts-agent.tar.gz "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz" \
 && echo "${AZP_AGENT_SHA256}  /tmp/vsts-agent.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/vsts-agent.tar.gz -C /azp \
 && rm /tmp/vsts-agent.tar.gz

# /azp/_work is where UseDotNet@2, NodeTool@0/UseNode@1, NuGetAuthenticate@1 and the trivy/gitleaks
# downloads in steps/container-scan.yml and steps/security-scan.yml land their own tool caches and
# temp files; the agent user (build-tools' "builder", uid 1001) needs to own all of /azp, not just
# _work, since config.sh/run.sh also write their own state (.agent, .credentials, _diag) there.
RUN mkdir -p /azp/_work \
 && chown -R builder:builder /azp

WORKDIR /azp
COPY --chown=builder:builder start.sh ./start.sh
RUN chmod +x ./start.sh

USER builder

ENTRYPOINT ["./start.sh"]
