#!/usr/bin/env bash
# activate-a2a.sh — Ativa o protocolo A2A em um Container App OpenClaw existente
#
# Uso:
#   AZURE_RESOURCE_GROUP=seu-rg \
#   OPENCLAW_CONTAINER_APP=seu-openclaw \
#   A2A_ENDPOINT_BASE=https://seu-openclaw.azurecontainerapps.io \
#   bash activate-a2a.sh
#
# Variáveis obrigatórias:
#   AZURE_RESOURCE_GROUP    — resource group do Container App
#   OPENCLAW_CONTAINER_APP  — nome do Container App
#   A2A_ENDPOINT_BASE       — URL base HTTPS do agente
#
# Variáveis opcionais:
#   A2A_AGENT_ID    — ID do agente no Agent Card (default: openclaw-main-agent)
#   A2A_AGENT_NAME  — Nome do agente (default: OpenClaw Agent)

set -euo pipefail

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP e obrigatorio}"
: "${OPENCLAW_CONTAINER_APP:?OPENCLAW_CONTAINER_APP e obrigatorio}"
: "${A2A_ENDPOINT_BASE:?A2A_ENDPOINT_BASE e obrigatorio}"
: "${A2A_AGENT_ID:=openclaw-main-agent}"
: "${A2A_AGENT_NAME:=OpenClaw Agent}"

A2A_ENDPOINT="${A2A_ENDPOINT_BASE}/a2a"

echo "==> Ativando A2A no Container App: ${OPENCLAW_CONTAINER_APP}"
echo "    A2A endpoint: ${A2A_ENDPOINT}"
echo "    Agent ID:     ${A2A_AGENT_ID}"

az containerapp update \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --set-env-vars \
    "A2A_ENABLED=true" \
    "A2A_ENDPOINT=${A2A_ENDPOINT}" \
    "A2A_AGENT_ID=${A2A_AGENT_ID}" \
    "A2A_AGENT_NAME=${A2A_AGENT_NAME}"

echo ""
echo "==> A2A ativado! Verificando endpoints..."
sleep 3

FQDN=$(az containerapp show \
  --name "${OPENCLAW_CONTAINER_APP}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv 2>/dev/null || true)

if [[ -n "${FQDN}" ]]; then
  echo ""
  echo "Testando Agent Card..."
  if curl -sf "https://${FQDN}/.well-known/agent.json" --max-time 10 | python3 -m json.tool 2>/dev/null; then
    echo ""
    echo "==> Sucesso! Agent Card disponivel em:"
    echo "    https://${FQDN}/.well-known/agent.json"
    echo "    https://${FQDN}/a2a"
  else
    echo "==> Aguarde o container reiniciar e teste manualmente:"
    echo "    curl https://${FQDN}/.well-known/agent.json"
  fi
fi
