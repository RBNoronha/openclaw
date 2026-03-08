---
name: a2a-protocol
description: "Protocolo Agent-to-Agent (A2A) para descoberta e comunicação entre agentes IA. Use quando: (1) enviando tarefas para outros agentes A2A, (2) descobrindo agentes via Agent Card (.well-known/agent.json), (3) monitorando status de tarefas delegadas, (4) integrando com agentes externos que falam A2A. NÃO use para comunicação interna entre agentes no mesmo gateway (use sessions_spawn)."
metadata: { "openclaw": { "emoji": "🤝" } }
---

# Protocolo A2A — Agent-to-Agent

Comunicação entre agentes IA via protocolo A2A (Google Agent-to-Agent Protocol).

## Endpoints deste agente

| Endpoint | Método | Descrição |
|---|---|---|
| `/.well-known/agent.json` | GET | Agent Card — identidade e capacidades |
| `/a2a` | POST | Recebe tarefas delegadas por outros agentes |
| `/a2a/tasks/:id` | GET | Status de tarefa em andamento |

## Descobrir um agente externo

```bash
curl https://agente-externo.azurecontainerapps.io/.well-known/agent.json
```

## Delegar tarefa para outro agente

```bash
curl -X POST https://agente-externo.azurecontainerapps.io/a2a \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Crie um relatório de uso de recursos Azure do último mês",
    "agentId": "openclaw-main-agent"
  }'
# Retorna: { "taskId": "uuid", "status": "running" }
```

## Verificar status da tarefa

```bash
curl https://agente-externo.azurecontainerapps.io/a2a/tasks/<taskId>
```

## Usando o cliente Python

```python
from a2a_client import A2AClient

client = A2AClient("https://agente-externo.azurecontainerapps.io")

# Descobrir agente
card = client.discover()
print(card["name"], card["skills"])

# Enviar tarefa
task = client.send_task("Analise os logs de erro do último dia")
print(task.task_id)

# Aguardar resultado
result = client.wait_for_task(task.task_id)
print(result.output)
```

## Ativar A2A neste gateway

No `openclaw.json`:

```json
{
  "a2a": {
    "enabled": true,
    "agentCard": {
      "id": "openclaw-main-agent",
      "name": "OpenClaw Agent",
      "endpoint": "https://seu-openclaw.azurecontainerapps.io/a2a",
      "skills": [
        { "id": "azure-infra", "name": "Gestão Azure" },
        { "id": "powershell", "name": "Automação PowerShell" }
      ],
      "auth": { "type": "bearer", "scheme": "entra" }
    }
  },
  "tools": {
    "agentToAgent": { "enabled": true, "allow": ["*"] }
  }
}
```
