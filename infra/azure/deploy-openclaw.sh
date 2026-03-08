#!/usr/bin/env bash
# deploy-openclaw.sh — Deploy OpenClaw with A2A protocol on Azure Container Apps
#
# Required env vars:
#   AZURE_RESOURCE_GROUP   — resource group name
#   AZURE_LOCATION         — e.g. brazilsouth
#   AZURE_ENVIRONMENT      — Container Apps Environment name
#   ACR_NAME               — Azure Container Registry name (without .azurecr.io)
#   OPENCLAW_IMAGE_TAG     — image tag to deploy (e.g. latest)
#   OPENCLAW_CONTAINER_APP — Container App name (default: openclaw)
#   A2A_ENDPOINT_BASE      — HTTPS base URL of this agent (e.g. https://openclaw.azurecontainerapps.io)
#
# Optional env vars:
#   OPENCLAW_GATEWAY_TOKEN — gateway auth token
#   ANTHROPIC_API_KEY      — Anthropic API key
#   A2A_AGENT_ID           — agent id for Agent Card (default: openclaw-main-agent)
#   A2A_AGENT_NAME         — agent name for Agent Card
#   INGRESS_TYPE           — internal | external (default: external)

set -euo pipefail

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
: "${AZURE_LOCATION:?AZURE_LOCATION is required}"
: "${AZURE_ENVIRONMENT:?AZURE_ENVIRONMENT is required}"
: "${ACR_NAME:?ACR_NAME is required}"
: "${OPENCLAW_IMAGE_TAG:=latest}"
: "${OPENCLAW_CONTAINER_APP:=openclaw}"
: "${A2A_ENDPOINT_BASE:=}"
: "${A2A_AGENT_ID:=openclaw-main-agent}"
: "${A2A_AGENT_NAME:=OpenClaw Agent}"
: "${INGRESS_TYPE:=external}"

IMAGE="${ACR_NAME}.azurecr.io/openclaw:${OPENCLAW_IMAGE_TAG}"
A2A_ENDPOINT="${A2A_ENDPOINT_BASE}/a2a"

echo "==> Deploying OpenClaw Container App: ${OPENCLAW_CONTAINER_APP}"
echo "    Image:       ${IMAGE}"
echo "    Environment: ${AZURE_ENVIRONMENT}"
echo "    Ingress:     ${INGRESS_TYPE}"
echo "    A2A endpoint:${A2A_ENDPOINT}"

# Build env-var list
ENV_VARS=(
  "A2A_ENABLED=true"
  "A2A_ENDPOINT=${A2A_ENDPOINT}"
  "A2A_AGENT_ID=${A2A_AGENT_ID}"
  "A2A_AGENT_NAME=${A2A_AGENT_NAME}"
)

if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  ENV_VARS+=("OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}")
fi
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ENV_VARS+=("ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
fi

# Check if the Container App already exists
if az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --output none 2>/dev/null; then

  echo "==> Updating existing Container App..."
  az containerapp update \
    --name "${OPENCLAW_CONTAINER_APP}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --image "${IMAGE}" \
    --set-env-vars "${ENV_VARS[@]}"
else
  echo "==> Creating new Container App..."
  az containerapp create \
    --name "${OPENCLAW_CONTAINER_APP}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --environment "${AZURE_ENVIRONMENT}" \
    --image "${IMAGE}" \
    --registry-server "${ACR_NAME}.azurecr.io" \
    --ingress "${INGRESS_TYPE}" \
    --target-port 18789 \
    --min-replicas 1 \
    --max-replicas 3 \
    --env-vars "${ENV_VARS[@]}"
fi

echo "==> Checking ingress..."
az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.configuration.ingress" \
  --output table

FQDN=$(az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv 2>/dev/null || true)

if [[ -n "${FQDN}" ]]; then
  echo ""
  echo "==> Deployment complete!"
  echo "    Agent Card: https://${FQDN}/.well-known/agent.json"
  echo "    A2A endpoint: https://${FQDN}/a2a"
  echo "    Health: https://${FQDN}/healthz"
fi
