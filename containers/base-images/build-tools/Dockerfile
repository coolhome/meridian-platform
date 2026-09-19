# syntax=docker/dockerfile:1.7
# Build toolchain for container jobs: .NET 10 SDK, Node 24, PowerShell, GitVersion, CycloneDX.
# Referenced by pipelines as a job container (resources.containers) when a hermetic build is needed.
ARG UPSTREAM=mcr.microsoft.com/dotnet/sdk:10.0-noble
# hadolint ignore=DL3006  (the tag is pinned in the ARG default above; DL3006 cannot see through the ARG)
FROM ${UPSTREAM}

ARG APP_VERSION=0.0.0-local
ARG VCS_REF=unknown
ARG NODE_MAJOR=24
ARG GITVERSION_VERSION=6.3.0
ARG CYCLONEDX_VERSION=5.3.1

LABEL org.opencontainers.image.title="meridian/base/build-tools" \
      org.opencontainers.image.description="Meridian build toolchain: .NET 10 SDK, Node ${NODE_MAJOR}, PowerShell, GitVersion, CycloneDX" \
      org.opencontainers.image.vendor="Meridian Platform Engineering" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.base.name="${UPSTREAM}" \
      meridian.image.tier="build"

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    PATH="${PATH}:/opt/dotnet-tools"

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq unzip \
 && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/msprod.deb \
 && dpkg -i /tmp/msprod.deb && rm /tmp/msprod.deb \
 && apt-get update && apt-get install -y --no-install-recommends powershell \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN dotnet tool install --tool-path /opt/dotnet-tools GitVersion.Tool --version "${GITVERSION_VERSION}" \
 && dotnet tool install --tool-path /opt/dotnet-tools CycloneDX --version "${CYCLONEDX_VERSION}"

# Agents run container jobs as the agent user; keep a non-root default for anything else.
RUN useradd --create-home --uid 1001 builder
USER builder
WORKDIR /home/builder
