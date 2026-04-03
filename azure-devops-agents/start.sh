#!/bin/bash
set -e

if [ -z "${AZP_URL}" ]; then
  echo "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -z "${AZP_TOKEN}" ]; then
  echo "error: missing AZP_TOKEN environment variable"
  exit 1
fi

if [ -z "${AZP_POOL}" ]; then
  AZP_POOL="Default"
fi

if [ -z "${AZP_AGENT_NAME}" ]; then
  AZP_AGENT_NAME="$(hostname)"
fi

# Make the agent work directory
mkdir -p "${AZP_WORK:-/workspace}"

cleanup() {
  echo "Removing agent registration..."
  ./config.sh remove --unattended --auth pat --token "${AZP_TOKEN}" || true
}
trap cleanup EXIT

echo "Configuring Azure Pipelines agent..."
./config.sh \
  --unattended \
  --url "${AZP_URL}" \
  --auth pat \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL}" \
  --agent "${AZP_AGENT_NAME}" \
  --work "${AZP_WORK:-/workspace}" \
  --replace \
  --acceptTeeEula

echo "Running Azure Pipelines agent..."
./run.sh
