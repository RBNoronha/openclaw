---
name: a2a-bridge
description: "Ponte A2A para conectar agentes OpenClaw com agentes externos em outras redes ou plataformas (LangChain, AutoGen, CrewAI, Google ADK). Use quando: (1) integrando com ecossistemas de agentes externos, (2) traduzindo entre protocolos de agente, (3) federando múltiplos gateways OpenClaw. NÃO use para comunicação direta entre agentes no mesmo gateway (use sessions_spawn)."
metadata: { "openclaw": { "emoji": "🌉" } }
---

# A2A Bridge — Ponte entre Redes de Agentes

Conecta este agente OpenClaw a agentes externos em outras plataformas e ecossistemas.

## Plataformas suportadas

| Plataforma | Como conectar |
|---|---|
| **Google ADK** | Via `/.well-known/agent.json` nativo |
| **LangChain** | Wrapper HTTP sobre `/a2a` |
| **AutoGen** | Wrapper HTTP sobre `/a2a` |
| **CrewAI** | Wrapper HTTP sobre `/a2a` |
| **Outro gateway OpenClaw** | Direto via A2A protocol |

## Conectar a um agente Google ADK

```bash
# 1. Descobrir o agente ADK
curl https://adk-agent.example.com/.well-known/agent.json

# 2. Enviar tarefa
curl -X POST https://adk-agent.example.com/a2a \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input": "Analise este dataset e gere um relatório"}'
```

## Registrar agente externo como bridge

No `openclaw.json`:

```json
{
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["*"]
    }
  }
}
```

## Federar dois gateways OpenClaw

```
Gateway A (Azure Brazil South)          Gateway B (Azure East US)
┌─────────────────────┐                 ┌─────────────────────┐
│  OpenClaw Main      │◄───── A2A ─────►│  OpenClaw Coder     │
│  /.well-known/      │                 │  /.well-known/      │
│  agent.json         │                 │  agent.json         │
└─────────────────────┘                 └─────────────────────┘
```

```python
from a2a_client import A2AClient

# Gateway A envia tarefa para Gateway B
client_b = A2AClient("https://openclaw-coder.azurecontainerapps.io")
card = client_b.discover()
print(f"Agente encontrado: {card.name}, skills: {[s['id'] for s in card.skills]}")

task = client_b.send_task("Refatore a função processPayment para usar async/await")
result = client_b.wait_for_task(task.task_id, timeout=300)
print(result.output)
```

## Verificar conectividade da bridge

```bash
# Listar agentes alcançáveis
curl https://meu-openclaw.azurecontainerapps.io/.well-known/agent.json | jq .

# Verificar saúde
curl https://meu-openclaw.azurecontainerapps.io/healthz
```
