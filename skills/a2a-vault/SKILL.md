---
name: a2a-vault
description: "Armazenamento seguro de credenciais para autenticação entre agentes A2A. Gerencia tokens Bearer, chaves de API e configurações de autenticação Entra ID (Azure AD) para comunicação segura entre agentes. Use quando: (1) configurando autenticação para chamadas A2A, (2) rotacionando tokens entre agentes, (3) gerenciando credenciais multi-agente. NÃO para: armazenar segredos de usuários finais (use o gestor de segredos padrão do openclaw)."
metadata: { "openclaw": { "emoji": "🔐" } }
---

# A2A Vault — Credenciais Seguras para Agentes

Gerencia autenticação e credenciais para comunicação A2A entre agentes.

## Modos de autenticação suportados

| Modo | Quando usar |
|---|---|
| `none` | Comunicação interna na mesma VNet (Container Apps) |
| `bearer` | Token estático para ambientes controlados |
| `entra` | Azure AD / Entra ID — recomendado para produção |

## Configurar autenticação Bearer simples

No `openclaw.json`:

```json
{
  "a2a": {
    "enabled": true,
    "agentCard": {
      "auth": { "type": "bearer", "scheme": "static" }
    }
  }
}
```

Usar token via variável de ambiente no Container App:

```bash
az containerapp update \
  --name seu-openclaw \
  --resource-group seu-rg \
  --set-env-vars A2A_AUTH_TOKEN="$(openssl rand -hex 32)"
```

## Configurar autenticação Entra ID (produção)

```bash
# 1. Criar App Registration no Azure AD
az ad app create --display-name "openclaw-a2a-agent"

# 2. Adicionar credencial de cliente
az ad app credential reset \
  --id <app-id> \
  --append

# 3. Configurar no Container App
az containerapp update \
  --name seu-openclaw \
  --resource-group seu-rg \
  --set-env-vars \
    AZURE_CLIENT_ID="<app-id>" \
    AZURE_TENANT_ID="<tenant-id>" \
    AZURE_CLIENT_SECRET="<secret>"
```

Agent Card com Entra:

```json
{
  "a2a": {
    "agentCard": {
      "auth": { "type": "bearer", "scheme": "entra" }
    }
  }
}
```

## Chamar agente com autenticação

```python
import os
from a2a_client import A2AClient

# Bearer estático
client = A2AClient(
    "https://agente-externo.azurecontainerapps.io",
    token=os.environ["A2A_AGENT_TOKEN"]
)

# Verificar Agent Card (autenticado)
card = client.discover()
print(f"Conectado a: {card.name}")
```

## Verificar segurança da comunicação

```bash
# Testar sem token (deve retornar 401)
curl -X POST https://agente.azurecontainerapps.io/a2a \
  -H "Content-Type: application/json" \
  -d '{"input": "test"}'

# Testar com token (deve retornar 202)
curl -X POST https://agente.azurecontainerapps.io/a2a \
  -H "Authorization: Bearer $A2A_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input": "test"}'
```

## Rotação de tokens

```bash
# Gerar novo token e atualizar Container App
NEW_TOKEN=$(openssl rand -hex 32)
az containerapp update \
  --name seu-openclaw \
  --resource-group seu-rg \
  --set-env-vars "A2A_AUTH_TOKEN=${NEW_TOKEN}"

echo "Novo token: ${NEW_TOKEN}"
echo "Distribua este token para os agentes que se comunicam com este gateway."
```
