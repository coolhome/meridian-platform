# syntax=docker/dockerfile:1.7
# Governed ASP.NET Core runtime base. Chiseled: no shell, no package manager, non-root by default.
# Upstream is pinned to the 10.0 channel; the resolved digest is recorded as a label at build time
# by the pipeline (BASE_DIGEST) so every service image can be traced to the exact upstream layer set.
ARG UPSTREAM=mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
# The tag is pinned in the ARG default above; DL3006 cannot see through the ARG.
# hadolint ignore=DL3006
FROM ${UPSTREAM}

ARG APP_VERSION=0.0.0-local
ARG VCS_REF=unknown
ARG BASE_DIGEST=unresolved

LABEL org.opencontainers.image.title="meridian/base/dotnet-aspnet" \
      org.opencontainers.image.description="Meridian governed ASP.NET Core 10 runtime base (chiseled, non-root)" \
      org.opencontainers.image.vendor="Meridian Platform Engineering" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.base.name="${UPSTREAM}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      meridian.image.tier="base" \
      meridian.image.policy="containers/policy/image-standards.md"

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_gcServer=0 \
    DOTNET_TieredPGO=1 \
    TZ=UTC

EXPOSE 8080
USER $APP_UID
