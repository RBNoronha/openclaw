#!/bin/bash
# Build da imagem A2A usando Azure Container Registry Tasks
# Não requer Docker local

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ACR_NAME="${ACR_NAME:-acrtemplateopenclaw}"
IMAGE_NAME="${IMAGE_NAME:-openclaw-a2a}"
TAG="${TAG:-latest}"

echo -e "${BLUE}🏗️  ACR Build - OpenClaw A2A${NC}"
echo "=============================="

# Verificar Azure login
echo -e "\n${BLUE}🔐 Verificando Azure...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}❌ Não logado no Azure${NC}"
    exit 1
fi
SUBSCRIPTION=$(az account show --query "name" -o tsv)
echo -e "${GREEN}✅ Logado: $SUBSCRIPTION${NC}"

# Criar diretório temporário com os arquivos necessários
echo -e "\n${BLUE}📁 Preparando arquivos...${NC}"
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

# Copiar arquivos essenciais
cp Dockerfile.a2a "$BUILD_DIR/"
cp package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc "$BUILD_DIR/" 2>/dev/null || true
cp -r scripts "$BUILD_DIR/" 2>/dev/null || true
cp -r patches "$BUILD_DIR/" 2>/dev/null || true
cp -r src "$BUILD_DIR/" 2>/dev/null || true
cp -r ui "$BUILD_DIR/" 2>/dev/null || true
cp openclaw.mjs "$BUILD_DIR/" 2>/dev/null || true

echo -e "${GREEN}✅ Arquivos preparados em $BUILD_DIR${NC}"

# Iniciar build no ACR
echo -e "\n${BLUE}🚀 Iniciando build no ACR...${NC}"
echo "Isso pode levar alguns minutos..."

az acr build \
    --registry "$ACR_NAME" \
    --image "$IMAGE_NAME:$TAG" \
    --file Dockerfile.a2a \
    --platform linux/amd64 \
    "$BUILD_DIR"

echo -e "${GREEN}✅ Build completo!${NC}"

# Verificar imagem
echo -e "\n${BLUE}🔍 Verificando imagem...${NC}"
az acr repository show-tags \
    --name "$ACR_NAME" \
    --repository "$IMAGE_NAME" \
    --output table

# Deploy no Container App
echo -e "\n${YELLOW}🚀 Deseja fazer deploy no Container App openclaw-zero-person? (s/n)${NC}"
read -r response
if [[ "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
    echo -e "\n${BLUE}🚀 Deploy...${NC}"
    
    az containerapp update \
        --name openclaw-zero-person \
        --resource-group RG-OPENCLAW \
        --image "$ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG" \
        --output table
    
    echo -e "${GREEN}✅ Deploy iniciado!${NC}"
    
    # Aguardar
    echo -e "\n${BLUE}⏳ Aguardando inicialização (60s)...${NC}"
    sleep 60
    
    # Testar A2A
    echo -e "\n${BLUE}🧪 Testando A2A endpoint...${NC}"
    URL=$(az containerapp show \
        --name openclaw-zero-person \
        --resource-group RG-OPENCLAW \
        --query "properties.configuration.ingress.fqdn" -o tsv)
    
    echo "URL: https://$URL/.well-known/agent.json"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://$URL/.well-known/agent.json" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ A2A está funcionando!${NC}"
        echo ""
        curl -s "https://$URL/.well-known/agent.json" 2>/dev/null | head -30
        
        # Testar criação de task
        echo -e "\n${BLUE}🧪 Testando criação de task...${NC}"
        TASK_RESULT=$(curl -s -X POST "https://$URL/a2a" \
            -H "Content-Type: application/json" \
            -d '{"input":"Hello from A2A test","agentId":"test-agent"}' 2>/dev/null)
        echo "Resposta: $TASK_RESULT"
    else
        echo -e "${YELLOW}⚠️  A2A retornou HTTP $HTTP_CODE${NC}"
        echo "Verificando logs..."
        az containerapp logs show -n openclaw-zero-person -g RG-OPENCLAW --tail 20
    fi
fi

echo -e "\n${GREEN}✅ Processo completo!${NC}"
