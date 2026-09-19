# syntax=docker/dockerfile:1.7
# Governed .NET runtime base for console jobs (no ASP.NET Core).
ARG UPSTREAM=mcr.microsoft.com/dotnet/runtime:10.0-noble-chiseled
FROM ${UPSTREAM}

ARG APP_VERSION=0.0.0-local
ARG VCS_REF=unknown
ARG BASE_DIGEST=unresolved

LABEL org.opencontainers.image.title="meridian/base/dotnet-runtime" \
      org.opencontainers.image.description="Meridian governed .NET 10 runtime base (chiseled, non-root)" \
      org.opencontainers.image.vendor="Meridian Platform Engineering" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.base.name="${UPSTREAM}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      meridian.image.tier="base"

ENV DOTNET_EnableDiagnostics=0 \
    DOTNET_gcServer=0 \
    TZ=UTC

USER $APP_UID
