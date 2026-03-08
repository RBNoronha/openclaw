# Azure Container Apps Deployment

Este documento descreve como configurar o deploy automático do OpenClaw no Azure Container Apps.

## Pré-requisitos

1. Azure subscription ativa
2. Azure Container Registry (ACR) criado
3. Azure Container App criado
4. Managed Identity configurada com permissões no ACR e Container App

## Configuração de Secrets no GitHub

Adicione os seguintes secrets no repositório (Settings > Secrets and variables > Actions):

| Secret | Descrição | Exemplo |
|--------|-----------|---------|
| `AZURE_CLIENT_ID` | Client ID da Managed Identity ou App Registration | `12345678-1234-1234-1234-123456789012` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_RESOURCE_GROUP` | Nome do Resource Group | `rg-openclaw-prod` |
| `AZURE_CONTAINER_APP_NAME` | Nome do Container App | `openclaw-prod` |
| `AZURE_ACR_NAME` | Nome do Azure Container Registry | `openclawacr` |

## Setup do Azure (passo a passo)

### 1. Criar Resource Group

```bash
az group create \
  --name rg-openclaw-prod \
  --location eastus
```

### 2. Criar Azure Container Registry

```bash
az acr create \
  --resource-group rg-openclaw-prod \
  --name openclawacr \
  --sku Standard \
  --admin-enabled false
```

### 3. Criar Container App Environment

```bash
az containerapp env create \
  --name openclaw-env \
  --resource-group rg-openclaw-prod \
  --location eastus
```

### 4. Criar Container App

```bash
az containerapp create \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --environment openclaw-env \
  --image openclawacr.azurecr.io/rbnoronha/openclaw:main \
  --target-port 3000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 3 \
  --cpu 1 \
  --memory 2Gi \
  --registry-server openclawacr.azurecr.io
```

### 5. Configurar Managed Identity para GitHub Actions

```bash
# Criar Managed Identity
az identity create \
  --name github-actions-openclaw \
  --resource-group rg-openclaw-prod \
  --location eastus

# Obter IDs (substitua pelos valores reais)
export SUBSCRIPTION_ID="your-subscription-id"
export RESOURCE_GROUP="rg-openclaw-prod"
export ACR_NAME="openclawacr"
export CONTAINER_APP_NAME="openclaw-prod"
export IDENTITY_NAME="github-actions-openclaw"

# Obter Resource IDs
IDENTITY_CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query clientId -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
CONTAINER_APP_ID=$(az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

# Atribuir permissões no ACR (AcrPush e AcrPull)
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role AcrPush \
  --scope $ACR_ID

az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role AcrPull \
  --scope $ACR_ID

# Atribuir permissões no Container App
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "Container Apps Contributor" \
  --scope $CONTAINER_APP_ID

# Configurar federated credential para GitHub Actions
az identity federated-credential create \
  --name github-federated \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:RBNoronha/openclaw:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"
```

## CD Automático via ACR Webhook (Opcional)

Para deploy automático sempre que uma nova imagem for pushada para o ACR:

### 1. Criar Webhook no ACR

```bash
az acr webhook create \
  --registry openclawacr \
  --name deploy-openclaw \
  --actions push \
  --uri "https://management.azure.com/subscriptions/{subscription-id}/resourceGroups/rg-openclaw-prod/providers/Microsoft.App/containerApps/openclaw-prod?api-version=2023-05-01" \
  --scope "rbnoronha/openclaw:*"
```

### 2. Ou usar Azure Event Grid (recomendado)

```bash
# Criar Event Grid System Topic
az eventgrid system-topic create \
  --name openclaw-acr-events \
  --resource-group rg-openclaw-prod \
  --source $ACR_ID \
  --topic-type Microsoft.ContainerRegistry.Registries

# Criar subscription para Container App update (requer Azure Function ou Logic App)
```

## Variáveis de Ambiente do Container App

Configure as variáveis de ambiente necessárias no Azure Portal ou via CLI:

```bash
az containerapp update \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --set-env-vars \
    "NODE_ENV=production" \
    "OPENCLAW_API_KEY=xxx" \
    # Adicione outras variáveis necessárias
```

## Troubleshooting

### Erro: "Unauthorized" no login do ACR

Verifique se a Managed Identity tem a role `AcrPush` atribuída.

### Erro: "Forbidden" no deploy do Container App

Verifique se a Managed Identity tem a role `Container Apps Contributor` atribuída.

### Pipeline preso em "queued"

Se o workflow ficar preso em queued, verifique:
1. O runner está configurado corretamente (`ubuntu-latest`)
2. Não há runs anteriores bloqueando
3. GitHub Actions está habilitado no repositório

Para cancelar runs presos:

```bash
# Via GitHub CLI
gh run list --repo RBNoronha/openclaw --status queued
gh run cancel <run-id> --repo RBNoronha/openclaw
```
