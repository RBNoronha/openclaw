#!/bin/bash
# A2A Protocol Validation Script
# Valida se o protocolo A2A está funcionando e agentes estão se comunicando

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 A2A Protocol Validator${NC}"
echo "=============================="

# Verificar variáveis de ambiente
CONTAINER_APP_URL="${OPENCLAW_URL:-${AZURE_CONTAINERAPP_URL:-}}"
if [ -z "$CONTAINER_APP_URL" ]; then
    echo -e "${YELLOW}⚠️  OPENCLAW_URL não definido. Usando localhost:3000${NC}"
    CONTAINER_APP_URL="http://localhost:3000"
fi

echo -e "\n${BLUE}📍 Target URL: $CONTAINER_APP_URL${NC}"

# Função para fazer requisições HTTP
http_get() {
    local url="$1"
    curl -s -w "\n%{http_code}" "$url" 2>/dev/null || echo -e "\n000"
}

http_post() {
    local url="$1"
    local data="$2"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        -w "\n%{http_code}" \
        "$url" 2>/dev/null || echo -e "\n000"
}

# 1. Verificar Agent Card (/.well-known/agent.json)
echo -e "\n${BLUE}1️⃣  Verificando Agent Card...${NC}"
AGENT_CARD_RESPONSE=$(http_get "${CONTAINER_APP_URL}/.well-known/agent.json")
AGENT_CARD_HTTP_CODE=$(echo "$AGENT_CARD_RESPONSE" | tail -1)
AGENT_CARD_BODY=$(echo "$AGENT_CARD_RESPONSE" | sed '$d')

if [ "$AGENT_CARD_HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Agent Card encontrado${NC}"
    echo "   Resposta:"
    echo "$AGENT_CARD_BODY" | jq -C '.' 2>/dev/null || echo "$AGENT_CARD_BODY"
    
    # Extrair informações
    AGENT_ID=$(echo "$AGENT_CARD_BODY" | jq -r '.id // "unknown"')
    AGENT_NAME=$(echo "$AGENT_CARD_BODY" | jq -r '.name // "unknown"')
    ENDPOINT=$(echo "$AGENT_CARD_BODY" | jq -r '.endpoint // "unknown"')
    
    echo -e "\n   ${BLUE}📋 Resumo:${NC}"
    echo "   - ID: $AGENT_ID"
    echo "   - Nome: $AGENT_NAME"
    echo "   - Endpoint: $ENDPOINT"
    
    # Verificar skills
    SKILLS_COUNT=$(echo "$AGENT_CARD_BODY" | jq '.skills | length')
    echo "   - Skills: $SKILLS_COUNT"
else
    echo -e "${RED}❌ Agent Card não disponível (HTTP $AGENT_CARD_HTTP_CODE)${NC}"
    echo "   Verifique se A2A está habilitado na configuração"
fi

# 2. Criar uma task A2A de teste
echo -e "\n${BLUE}2️⃣  Criando task A2A de teste...${NC}"
TASK_PAYLOAD='{
    "input": "Hello from A2A validation test",
    "agentId": "validator-agent",
    "sessionKey": "test-session-123"
}'

TASK_RESPONSE=$(http_post "${CONTAINER_APP_URL}/a2a" "$TASK_PAYLOAD")
TASK_HTTP_CODE=$(echo "$TASK_RESPONSE" | tail -1)
TASK_BODY=$(echo "$TASK_RESPONSE" | sed '$d')

if [ "$TASK_HTTP_CODE" = "202" ]; then
    echo -e "${GREEN}✅ Task criada com sucesso${NC}"
    echo "   Resposta:"
    echo "$TASK_BODY" | jq -C '.' 2>/dev/null || echo "$TASK_BODY"
    
    TASK_ID=$(echo "$TASK_BODY" | jq -r '.taskId // empty')
    if [ -n "$TASK_ID" ]; then
        echo -e "\n   ${BLUE}📝 Task ID: $TASK_ID${NC}"
        
        # 3. Verificar status da task
        echo -e "\n${BLUE}3️⃣  Verificando status da task...${NC}"
        sleep 1
        
        STATUS_RESPONSE=$(http_get "${CONTAINER_APP_URL}/a2a/tasks/${TASK_ID}")
        STATUS_HTTP_CODE=$(echo "$STATUS_RESPONSE" | tail -1)
        STATUS_BODY=$(echo "$STATUS_RESPONSE" | sed '$d')
        
        if [ "$STATUS_HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✅ Task status recuperado${NC}"
            echo "   Resposta:"
            echo "$STATUS_BODY" | jq -C '.' 2>/dev/null || echo "$STATUS_BODY"
            
            TASK_STATUS=$(echo "$STATUS_BODY" | jq -r '.task.status // "unknown"')
            echo -e "\n   ${BLUE}📊 Status: $TASK_STATUS${NC}"
        else
            echo -e "${RED}❌ Falha ao recuperar status (HTTP $STATUS_HTTP_CODE)${NC}"
        fi
    fi
elif [ "$TASK_HTTP_CODE" = "404" ]; then
    echo -e "${YELLOW}⚠️  Endpoint A2A não encontrado - A2A pode estar desabilitado${NC}"
else
    echo -e "${RED}❌ Falha ao criar task (HTTP $TASK_HTTP_CODE)${NC}"
    echo "   Resposta: $TASK_BODY"
fi

# 4. Verificar agentes configurados
echo -e "\n${BLUE}4️⃣  Verificando agentes configurados...${NC}"

# Verificar se openclaw CLI está disponível
if command -v openclaw &> /dev/null; then
    echo -e "${GREEN}✅ CLI openclaw encontrado${NC}"
    
    # Listar agentes
    AGENTS_OUTPUT=$(openclaw agents list 2>/dev/null || echo "Erro ao listar agentes")
    echo "   Agentes:"
    echo "$AGENTS_OUTPUT" | head -20
    
    # Contar agentes
    AGENT_COUNT=$(echo "$AGENTS_OUTPUT" | grep -c "^  " || echo "0")
    echo -e "\n   ${BLUE}📊 Total de agentes: $AGENT_COUNT${NC}"
else
    echo -e "${YELLOW}⚠️  CLI openclaw não encontrado${NC}"
    echo "   Para verificar agentes, instale o openclaw CLI"
fi

# 5. Resumo
echo -e "\n${BLUE}==============================${NC}"
echo -e "${BLUE}📊 RESUMO DA VALIDAÇÃO A2A${NC}"
echo -e "${BLUE}==============================${NC}"

if [ "$AGENT_CARD_HTTP_CODE" = "200" ] && [ "$TASK_HTTP_CODE" = "202" ]; then
    echo -e "${GREEN}✅ A2A Protocol está funcionando corretamente!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  A2A Protocol pode não estar totalmente configurado${NC}"
    echo ""
    echo -e "${BLUE}💡 Dicas:${NC}"
    echo "   1. Verifique se OPENCLAW_A2A_ENABLED=true está configurado"
    echo "   2. Certifique-se de que o Container App está rodando"
    echo "   3. Verifique os logs: az containerapp logs show --name <app> --resource-group <rg>"
    exit 1
fi
