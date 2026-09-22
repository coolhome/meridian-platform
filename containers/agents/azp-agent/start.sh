#!/bin/bash
# Adapted from Microsoft's "Run a self-hosted agent in Docker" script
# (https://learn.microsoft.com/azure/devops/pipelines/agents/docker), simplified for this image:
# PAT-only auth (no service-principal branch — ADR 0006's workload-identity rule has a recorded
# exception for this PAT, not a reason to add more secret types), and no runtime agent download,
# because the Dockerfile already unpacked a pinned, sha256-checked agent build into /azp.
set -euo pipefail

print_header() {
  echo -e "\n\033[1;36m${1}\033[0m\n"
}

if [ -z "${AZP_URL:-}" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -z "${AZP_TOKEN:-}" ]; then
  echo 1>&2 "error: missing AZP_TOKEN environment variable"
  exit 1
fi

if [ -z "${AZP_POOL:-}" ]; then
  echo 1>&2 "error: missing AZP_POOL environment variable"
  exit 1
fi

AZP_TOKEN_FILE="/azp/.token"
(umask 177 && echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}")
unset AZP_TOKEN

# Belt and suspenders: if the token somehow survives into a job's environment, the agent itself
# strips these variable names before handing the environment to job processes.
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "Configuring Azure Pipelines agent..."

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "${AZP_URL}" \
  --auth PAT \
  --token "$(cat "${AZP_TOKEN_FILE}")" \
  --pool "${AZP_POOL}" \
  --work _work \
  --replace \
  --acceptTeeEula

if [ "${AZP_PLACEHOLDER:-}" = "1" ]; then
  print_header "AZP_PLACEHOLDER=1: agent configured and left registered offline in pool ${AZP_POOL}. Not running a job."
  exit 0
fi

# Only reached (and only trapped) once configuration succeeded, so a bad token, URL or pool never
# attempts a "config.sh remove" against an agent that was never registered.
cleanup() {
  trap '' EXIT INT TERM
  print_header "Removing Azure Pipelines agent..."
  ./config.sh remove --unattended --auth PAT --token "$(cat "${AZP_TOKEN_FILE}")" || \
    echo 1>&2 "warning: failed to remove agent configuration"
}
# rc carries run.sh's real exit code through cleanup so the EXIT trap reports it, not a hardcoded
# 0 — otherwise a crashed job execution would show as a Succeeded Container Apps job execution.
rc=0
trap 'cleanup; exit "$rc"' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

print_header "Running Azure Pipelines agent..."
./run.sh --once || rc=$?
