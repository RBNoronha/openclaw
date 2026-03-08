# Guia de Deploy A2A - Azure Container Apps

## ⚠️ Problema de Autenticação Identificado

O deploy automático falhou porque o Service Principal `sp-openclaw-a2a` não tem **Federated Identity Credential** configurado para o repositório `RBNoronha/openclaw`.

### Opção 1: Configurar Federated Identity (Recomendado)

Execute no Azure CLI:

```bash
# Configurar credencial federada para o seu fork
az identity federated-credential create \
  --name github-federated-rbnoronha \
  --identity-name github-actions-openclaw \
  --resource-group rg-openclaw-prod \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:RBNoronha/openclaw:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"
```

### Opção 2: Deploy Manual com Credenciais

Use o workflow `Deploy to Azure Container Apps (Manual Auth)`:

1. Crie um Service Principal:
```bash
az ad sp create-for-rbac \
  --name "openclaw-manual-deploy" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-openclaw-prod \
  --json-auth > azure-credentials.json
```

2. Acesse: https://github.com/RBNoronha/openclaw/actions/workflows/deploy-azure-manual.yml

3. Clique "Run workflow" e cole o conteúdo de `azure-credentials.json`

## 🚀 Validação do A2A

### 1. Configurar Agentes Localmente

```bash
# Execute o script de setup
./scripts/a2a-setup.sh
```

Isso cria 3 agentes:
- `coordinator`: Orquestra tarefas
- `executor`: Executa tarefas
- `validator`: Valida resultados

### 2. Validar Protocolo A2A

```bash
# Defina a URL do Container App
export OPENCLAW_URL=https://seu-container-app.azurecontainerapps.io

# Execute validação
./scripts/a2a-validate.sh
```

### 3. Teste Manual via cURL

```bash
# Verificar Agent Card
curl https://seu-container-app.azurecontainerapps.io/.well-known/agent.json | jq

# Criar task A2A
curl -X POST https://seu-container-app.azurecontainerapps.io/a2a \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Hello from A2A test",
    "agentId": "coordinator",
    "sessionKey": "test-123"
  }'

# Verificar status da task
curl https://seu-container-app.azurecontainerapps.io/a2a/tasks/{task-id}
```

## 🔧 Configuração do Container App

### Variáveis de Ambiente Necessárias

```bash
az containerapp update \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --set-env-vars \
    "OPENCLAW_A2A_ENABLED=true" \
    "OPENCLAW_A2A_AGENT_CARD_ID=openclaw-a2a-gateway" \
    "OPENCLAW_A2A_AGENT_CARD_NAME=OpenClaw A2A Gateway" \
    "NODE_ENV=production"
```

### Verificar Logs

```bash
# Logs do Container App
az containerapp logs show \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --follow
```

## 🧪 Teste de Comunicação A2A entre Agentes

### Teste 1: Agent Card Discovery
```bash
curl -s https://<URL>/.well-known/agent.json | jq '.'
```

Esperado: JSON com informações do agente

### Teste 2: Task Creation
```bash
curl -X POST https://<URL>/a2a \
  -H "Content-Type: application/json" \
  -d '{"input":"Test task"}'
```

Esperado: `{"ok":true,"taskId":"...","status":"running"}`

### Teste 3: Task Status
```bash
curl -s https://<URL>/a2a/tasks/<task-id> | jq '.'
```

Esperado: Status atual da task

## 📊 Troubleshooting

### Erro: "no configured federated identity credentials"
**Solução**: Configure a federated credential ou use o workflow manual

### Erro: "A2A Agent Card não disponível"
**Solução**: Verifique se `OPENCLAW_A2A_ENABLED=true` está configurado

### Erro: "Container App não encontrado"
**Solução**: Verifique se os secrets `AZURE_RESOURCE_GROUP` e `AZURE_CONTAINER_APP_NAME` estão configurados

### Erro: "Task não criada"
**Solução**: Verifique os logs do Container App para erros na API

## 📝 Comandos Úteis

```bash
# Listar Container Apps
az containerapp list --resource-group rg-openclaw-prod --output table

# Ver detalhes
az containerapp show --name openclaw-prod --resource-group rg-openclaw-prod

# Reiniciar
az containerapp revision restart \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --revision openclaw-prod--{revision}

# Atualizar imagem manualmente
az containerapp update \
  --name openclaw-prod \
  --resource-group rg-openclaw-prod \
  --image ghcr.io/openclaw/openclaw:v2026.3.7
```
