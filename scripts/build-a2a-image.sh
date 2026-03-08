#!/bin/bash
# Build e push da imagem OpenClaw com A2A para o ACR

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ACR_NAME="${ACR_NAME:-acrtemplateopenclaw}"
IMAGE_NAME="${IMAGE_NAME:-openclaw-a2a}"
TAG="${TAG:-latest}"

echo -e "${BLUE}🐳 Build OpenClaw A2A Image${NC}"
echo "=============================="

# Verificar se está logado no Azure
echo -e "\n${BLUE}🔐 Verificando login Azure...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}❌ Não está logado no Azure${NC}"
    echo "Execute: az login"
    exit 1
fi

echo -e "${GREEN}✅ Logado no Azure${NC}"

# Login no ACR
echo -e "\n${BLUE}🔐 Login no ACR...${NC}"
az acr login --name "$ACR_NAME"
echo -e "${GREEN}✅ Logado no ACR${NC}"

# Build da imagem
echo -e "\n${BLUE}🏗️  Build da imagem...${NC}"
docker build \
    -f Dockerfile.a2a \
    -t "$ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG" \
    -t "$ACR_NAME.azurecr.io/$IMAGE_NAME:$(git rev-parse --short HEAD 2>/dev/null || echo 'local')" \
    .

echo -e "${GREEN}✅ Build completo${NC}"

# Push para o ACR
echo -e "\n${BLUE}📤 Push para ACR...${NC}"
docker push "$ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG"
echo -e "${GREEN}✅ Push completo${NC}"

# Verificar imagem no ACR
echo -e "\n${BLUE}🔍 Verificando imagem no ACR...${NC}"
az acr repository show-tags \
    --name "$ACR_NAME" \
    --repository "$IMAGE_NAME" \
    --output table

# Perguntar se deseja deploy
echo -e "\n${YELLOW}🚀 Deseja fazer deploy no Container App? (s/n)${NC}"
read -r response
if [[ "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
    echo -e "\n${BLUE}🚀 Deploy no Container App...${NC}"
    
    az containerapp update \
        --name openclaw-zero-person \
        --resource-group RG-OPENCLAW \
        --image "$ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG" \
        --output table
    
    echo -e "${GREEN}✅ Deploy iniciado!${NC}"
    
    echo -e "\n${BLUE}⏳ Aguardando Container App iniciar...${NC}"
    sleep 30
    
    # Testar A2A
    echo -e "\n${BLUE}🧪 Testando A2A...${NC}"
    URL=$(az containerapp show \
        --name openclaw-zero-person \
        --resource-group RG-OPENCLAW \
        --query "properties.configuration.ingress.fqdn" -o tsv)
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://$URL/.well-known/agent.json" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ A2A está funcionando!${NC}"
        echo -e "\n${BLUE}📋 Agent Card:${NC}"
        curl -s "https://$URL/.well-known/agent.json" 2>/dev/null | head -30
    else
        echo -e "${YELLOW}⚠️  A2A retornou HTTP $HTTP_CODE${NC}"
        echo "Verifique os logs: az containerapp logs show -n openclaw-zero-person -g RG-OPENCLAW"
    fi
fi

echo -e "\n${GREEN}✅ Processo completo!${NC}"
echo -e "${BLUE}📍 Imagem: $ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG${NC}"
