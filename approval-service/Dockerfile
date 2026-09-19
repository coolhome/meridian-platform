# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
FROM ${BASE_IMAGE}

ARG APP_VERSION=0.0.0-local
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="meridian/services/approval-service" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://dev.azure.com/CHANGE-ME/Meridian/_git/meridian-approval-service" \
      meridian.service="approval-service"

WORKDIR /app
COPY .publish/ ./
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "Meridian.Approval.Api.dll"]
