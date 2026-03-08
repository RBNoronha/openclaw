#!/usr/bin/env bash
# verify-ingress.sh — Verify and enable ingress for an OpenClaw Container App
#
# Required env vars:
#   AZURE_RESOURCE_GROUP   — resource group name
#   OPENCLAW_CONTAINER_APP — Container App name (default: openclaw)
#
# Optional:
#   TARGET_PORT   — port OpenClaw listens on (default: 18789)
#   INGRESS_TYPE  — internal | external (default: external)

set -euo pipefail

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${OPENCLAW_CONTAINER_APP:=openclaw}"
: "${TARGET_PORT:=18789}"
: "${INGRESS_TYPE:=external}"

echo "==> Checking ingress for: ${OPENCLAW_CONTAINER_APP}"

INGRESS=$(az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.configuration.ingress" \
  --output json 2>/dev/null || echo "null")

if [[ "${INGRESS}" == "null" ]]; then
  echo "==> Ingress is NOT configured. Enabling..."
  az containerapp ingress enable \
    --name "${OPENCLAW_CONTAINER_APP}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --target-port "${TARGET_PORT}" \
    --type "${INGRESS_TYPE}"
  echo "==> Ingress enabled."
else
  echo "==> Ingress is already configured:"
  az containerapp show \
    --name "${OPENCLAW_CONTAINER_APP}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --query "properties.configuration.ingress" \
    --output table
fi

FQDN=$(az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv 2>/dev/null || true)

if [[ -n "${FQDN}" ]]; then
  echo ""
  echo "==> FQDN: https://${FQDN}"
  echo "    A2A Agent Card: https://${FQDN}/.well-known/agent.json"
  echo "    A2A Endpoint:   https://${FQDN}/a2a"
fi
