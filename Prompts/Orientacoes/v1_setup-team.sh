# Instalar OpenClaw (se ainda não instalado)
curl -fsSL https://openclaw.ai/install.sh | bash

# Criar os agentes
openclaw agents add orquestrador
openclaw agents add pesquisador
openclaw agents add copywriter
openclaw agents add frontend-dev
openclaw agents add designer
openclaw agents add qa-reviewer

# Vincular canais
openclaw channels bind slack --agent orquestrador --account work
openclaw channels bind terminal --agent frontend-dev

# Iniciar o Gateway com todos os agentes
openclaw gateway start --multi-agent