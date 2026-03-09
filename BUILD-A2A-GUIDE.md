# Guia de Build A2A - OpenClaw

## Status Atual

O Container App `openclaw-zero-person` está rodando em:
- **URL**: https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/
- **Imagem**: `acrtemplateopenclaw.azurecr.io/openclaw-a2a:latest`
- **Status**: ✅ Gateway HTTP funcionando (porta 3000)
- **A2A**: ❌ Não habilitado (código não compilado na imagem)

## Problema

O código A2A (`src/gateway/a2a-http.ts`) existe no repositório, mas precisa ser compilado 
para JavaScript e incluído na imagem Docker. Os builds no ACR falharam devido a:

1. Dependências de build complexas (A2UI bundle, TypeScript compilation)
2. Memória insuficiente no ambiente de build
3. Tempo limite de execução

## Solução

### Opção 1: Build Local (Recomendado)

Execute em uma máquina com:
- **16GB+ RAM**
- **Docker instalado**
- **Node.js 22+** e **pnpm**

```bash
# Clone o repositório
git clone https://github.com/RBNoronha/openclaw.git
cd openclaw

# Instalar dependências
NODE_OPTIONS=--max-old-space-size=8192 pnpm install

# Criar A2UI placeholder
mkdir -p src/canvas-host/a2ui
echo "// A2UI" > src/canvas-host/a2ui/a2ui.bundle.js
echo "placeholder" > src/canvas-host/a2ui/.bundle.hash

# Compilar TypeScript
NODE_OPTIONS=--max-old-space-size=8192 pnpm exec tsc \
  --project tsconfig.json \
  --outDir dist/ \
  --skipLibCheck

# Copiar arquivos não-TypeScript
find src -type f ! -name "*.ts" ! -name "*.tsx" \
  -exec cp --parents {} dist/ \;

# Build Docker local
docker build -f Dockerfile.a2a-simple -t openclaw-a2a:local .

# Tag e push para ACR
az acr login --name acrtemplateopenclaw
docker tag openclaw-a2a:local acrtemplateopenclaw.azurecr.io/openclaw-a2a:v5
docker push acrtemplateopenclaw.azurecr.io/openclaw-a2a:v5

# Deploy
az containerapp update \
  --name openclaw-zero-person \
  --resource-group RG-OPENCLAW \
  --image acrtemplateopenclaw.azurecr.io/openclaw-a2a:v5
```

### Opção 2: GitHub Actions

Use o workflow `.github/workflows/build-a2a-image-manual.yml`:

1. Acesse: https://github.com/RBNoronha/openclaw/actions/workflows/build-a2a-image-manual.yml
2. Clique "Run workflow"
3. Forneça as credenciais do Azure:

```bash
# Gere as credenciais:
az ad sp create-for-rbac \
  --name "github-actions-a2a" \
  --role contributor \
  --scopes /subscriptions/8d0494dd-f967-4e00-b193-b7eaf572b227/resourceGroups/RG-OPENCLAW \
  --json-auth
```

4. Cole o JSON no campo `azure_credentials`
5. Clique "Run workflow"

### Opção 3: Azure Cloud Shell

Execute no Azure Cloud Shell (mais memória disponível):

```bash
# Clone
git clone https://github.com/RBNoronha/openclaw.git
cd openclaw

# Execute o script de setup completo
chmod +x scripts/setup-a2a-complete.sh
./scripts/setup-a2a-complete.sh
```

## Verificação Após Build

Teste se o A2A está funcionando:

```bash
# Testar Agent Card
curl https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/.well-known/agent.json

# Criar task
curl -X POST https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/a2a \
  -H "Content-Type: application/json" \
  -d '{"input":"Test A2A","agentId":"test"}'
```

## Agentes a Criar

Após o A2A funcionar, crie estes agentes especializados:

1. **frontend-dev**: React, TypeScript, UI/UX
2. **backend-dev**: APIs, Database, Security
3. **devops-eng**: CI/CD, Containers, Azure
4. **qa-eng**: Unit Tests, E2E Tests, Code Review

## Recursos

- **ACR**: `acrtemplateopenclaw.azurecr.io`
- **Container App**: `openclaw-zero-person` (RG: `RG-OPENCLAW`)
- **Storage**: `stoclaw` (File Share: `openclaw-config`)
- **MCP Server**: `/home/userland/mcp-azure/server.js`
