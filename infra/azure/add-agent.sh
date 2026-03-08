#!/usr/bin/env bash
# add-agent.sh — Add a second OpenClaw agent to the same Container Apps Environment
#               for multi-agent A2A communication (internal VNet traffic only).
#
# Required env vars:
#   AZURE_RESOURCE_GROUP   — resource group name
#   AZURE_ENVIRONMENT      — Container Apps Environment (same as main agent)
#   ACR_NAME               — Azure Container Registry name
#   AGENT_ID               — unique identifier for this agent (e.g. coder-agent)
#
# Optional env vars:
#   OPENCLAW_IMAGE_TAG     — image tag (default: latest)
#   OPENCLAW_MODEL         — model for this agent (default: anthropic/claude-opus-4-5)
#   ANTHROPIC_API_KEY      — Anthropic API key
#   INGRESS_TYPE           — internal | external (default: internal for agent isolation)

set -euo pipefail

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_ENVIRONMENT:?AZURE_ENVIRONMENT is required}"
: "${ACR_NAME:?ACR_NAME is required}"
: "${AGENT_ID:?AGENT_ID is required}"
: "${OPENCLAW_IMAGE_TAG:=latest}"
: "${OPENCLAW_MODEL:=anthropic/claude-opus-4-5}"
: "${INGRESS_TYPE:=internal}"

CONTAINER_APP_NAME="openclaw-${AGENT_ID}"
IMAGE="${ACR_NAME}.azurecr.io/openclaw:${OPENCLAW_IMAGE_TAG}"

echo "==> Adding agent Container App: ${CONTAINER_APP_NAME}"
echo "    Environment: ${AZURE_ENVIRONMENT} (same as main agent)"
echo "    Ingress:     ${INGRESS_TYPE} (VNet only)"
echo "    Model:       ${OPENCLAW_MODEL}"

ENV_VARS=(
  "AGENT_ID=${AGENT_ID}"
  "OPENCLAW_MODEL=${OPENCLAW_MODEL}"
  "A2A_ENABLED=true"
  "A2A_AGENT_ID=${AGENT_ID}"
  "A2A_AGENT_NAME=OpenClaw ${AGENT_ID}"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ENV_VARS+=("ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
fi

az containerapp create \
  --name "${CONTAINER_APP_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --environment "${AZURE_ENVIRONMENT}" \
  --image "${IMAGE}" \
  --registry-server "${ACR_NAME}.azurecr.io" \
  --ingress "${INGRESS_TYPE}" \
  --target-port 18789 \
  --min-replicas 1 \
  --max-replicas 2 \
  --env-vars "${ENV_VARS[@]}"

echo ""
echo "==> Agent '${AGENT_ID}' deployed inside the same Container Apps Environment."
echo "    Agents communicate via A2A over the internal VNet — no public egress."
echo ""
echo "    To add more agents, re-run with a different AGENT_ID."
echo "    Example: AGENT_ID=qa-agent bash add-agent.sh"

if [[ "${INGRESS_TYPE}" == "internal" ]]; then
  INTERNAL_FQDN=$(az containerapp show \
    --name "${CONTAINER_APP_NAME}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv 2>/dev/null || true)
  if [[ -n "${INTERNAL_FQDN}" ]]; then
    echo "    Internal A2A endpoint: http://${INTERNAL_FQDN}/a2a"
  fi
fi
