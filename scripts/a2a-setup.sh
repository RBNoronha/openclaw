#!/bin/bash
# A2A Agents Setup Script
# Cria e configura agentes para comunicação A2A

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🤖 A2A Agents Setup${NC}"
echo "===================="

# Verificar se openclaw está instalado
if ! command -v openclaw &> /dev/null; then
    echo -e "${RED}❌ openclaw CLI não encontrado${NC}"
    echo "Instale com: npm install -g openclaw"
    exit 1
fi

echo -e "${GREEN}✅ openclaw CLI encontrado${NC}"

# Listar agentes existentes
echo -e "\n${BLUE}📋 Agentes existentes:${NC}"
openclaw agents list 2>/dev/null || echo "Nenhum agente encontrado"

# Função para criar agente
create_agent() {
    local agent_id="$1"
    local name="$2"
    local description="$3"
    
    echo -e "\n${BLUE}📝 Criando agente: $name${NC}"
    
    # Verificar se agente já existe
    if openclaw agents list 2>/dev/null | grep -q "\b${agent_id}\b"; then
        echo -e "${YELLOW}⚠️  Agente $agent_id já existe${NC}"
        return 0
    fi
    
    # Criar diretório do agente
    local agent_dir="$HOME/.openclaw/agents/${agent_id}"
    mkdir -p "$agent_dir"
    
    # Criar identity.md
    cat > "$agent_dir/identity.md" << EOF
# $name

$name

## Description

$description

## Capabilities

- A2A protocol communication
- Multi-agent collaboration
- Task delegation and execution
EOF
    
    echo -e "${GREEN}✅ Agente $name criado${NC}"
}

# Criar agentes A2A de exemplo
echo -e "\n${BLUE}🔧 Criando agentes A2A padrão...${NC}"

create_agent "coordinator" "Coordinator Agent" "Agente coordenador que orquestra tarefas entre múltiplos agentes"
create_agent "executor" "Executor Agent" "Agente executor que realiza tarefas específicas"
create_agent "validator" "Validator Agent" "Agente validador que verifica resultados e qualidade"

# Configurar A2A nos agentes
echo -e "\n${BLUE}⚙️  Configurando A2A...${NC}"

# Criar arquivo de configuração para A2A
A2A_CONFIG_DIR="$HOME/.openclaw/config"
mkdir -p "$A2A_CONFIG_DIR"

cat > "$A2A_CONFIG_DIR/a2a.yaml" << 'EOF'
# A2A Protocol Configuration
a2a:
  enabled: true
  agentCard:
    id: openclaw-a2a-gateway
    name: OpenClaw A2A Gateway
    description: Multi-channel AI gateway with A2A protocol support
    skills:
      - id: channel-management
        name: Channel Management
        description: Manage communication channels
      - id: agent-orchestration
        name: Agent Orchestration
        description: Orchestrate multiple agents for complex tasks
      - id: message-routing
        name: Message Routing
        description: Route messages between agents and channels
    auth:
      type: bearer

tools:
  agentToAgent:
    enabled: true
    allow:
      - coordinator
      - executor
      - validator
EOF

echo -e "${GREEN}✅ Configuração A2A criada${NC}"
echo "   Local: $A2A_CONFIG_DIR/a2a.yaml"

# Configurar bindings para agentes
echo -e "\n${BLUE}🔗 Configurando bindings...${NC}"

# Adicionar agentes à configuração principal
cat >> "$A2A_CONFIG_DIR/agents.yaml" 2>/dev/null << 'EOF' || true
agents:
  list:
    - id: coordinator
      name: Coordinator
      model: anthropic:claude-3-opus-20240229
    - id: executor
      name: Executor
      model: anthropic:claude-3-sonnet-20240229
    - id: validator
      name: Validator
      model: anthropic:claude-3-haiku-20240307
EOF

echo -e "${GREEN}✅ Agentes configurados${NC}"

# Resumo
echo -e "\n${BLUE}====================${NC}"
echo -e "${BLUE}📊 RESUMO${NC}"
echo -e "${BLUE}====================${NC}"

echo -e "${GREEN}✅ Agentes A2A criados:${NC}"
echo "   - coordinator: Orquestra tarefas"
echo "   - executor: Executa tarefas"
echo "   - validator: Valida resultados"

echo -e "\n${BLUE}📝 Próximos passos:${NC}"
echo "   1. Inicie o gateway: openclaw gateway start"
echo "   2. Verifique A2A: curl http://localhost:3000/.well-known/agent.json"
echo "   3. Teste comunicação entre agentes"
echo ""
echo -e "${BLUE}🔗 Links úteis:${NC}"
echo "   - A2A Spec: https://google.github.io/A2A/"
echo "   - OpenClaw Docs: https://docs.openclaw.ai"
