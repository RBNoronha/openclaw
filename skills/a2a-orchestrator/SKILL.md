---
name: a2a-orchestrator
description: "Orquestrador multi-agente via protocolo A2A. Roteia tarefas entre openclaw-zero-person (agente principal, externo) e openclaw-coder-agent (agente especialista, interno via VNet). Use quando: (1) tarefa exige raciocínio + execução de código, (2) delegando subtarefas especializadas para o coder agent, (3) monitorando progresso de tarefas delegadas. Endpoints configurados via env vars A2A_ENDPOINT e A2A_CODER_ENDPOINT."
metadata: { "openclaw": { "emoji": "🎯" } }
---

# A2A Orchestrator — Comunicação Multi-Agente

Orquestra comunicação A2A entre os dois agentes no mesmo Container Apps Environment.

## Topologia

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────┐
│         Azure Container Apps Environment          │
│              (openclaw-aca-env, East US)           │
│                                                    │
│  ┌─────────────────────┐   A2A (VNet interno)      │
│  │  openclaw-zero-     │◄────────────────────────► │
│  │  person             │                           │
│  │  (externo: HTTPS)   │  ┌──────────────────────┐ │
│  │                     │  │ openclaw-coder-agent  │ │
│  │  Gemini 2.5 Pro     │  │ (interno: VNet only)  │ │
│  └─────────────────────┘  │                       │ │
│                            │  Gemini 2.5 Pro       │ │
│                            └──────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Endpoints

| Agente | Tipo | URL |
|---|---|---|
| `openclaw-zero-person` | Externo (público) | `https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io` |
| `openclaw-coder-agent` | Interno (VNet) | `http://openclaw-coder-agent.internal.purplestone-bd490ece.eastus.azurecontainerapps.io` |

## Delegar tarefa para o coder agent

```python
import os
from a2a_client import A2AClient

CODER_URL = os.environ.get(
    "A2A_CODER_ENDPOINT",
    "http://openclaw-coder-agent.internal.purplestone-bd490ece.eastus.azurecontainerapps.io"
).rstrip("/a2a")

client = A2AClient(CODER_URL)

# Descobrir capacidades
card = client.discover()
print(f"Agente: {card.name} | Skills: {[s['id'] for s in card.skills]}")

# Delegar tarefa de codificação
task = client.send_task(
    "Implemente uma função TypeScript que valida um Agent Card A2A",
    agent_id="openclaw-coder-agent"
)
print(f"Task ID: {task.task_id}")

# Aguardar resultado (máx 5 minutos)
result = client.wait_for_task(task.task_id, timeout=300)
print(f"Status: {result.status}")
print(f"Output: {result.output}")
```

## Padrão orquestrador: raciocinar + delegar

```python
from a2a_client import A2AClient
import os

def orchestrate(user_request: str) -> str:
    """
    Padrão A2A de melhores práticas:
    1. Agente principal analisa e divide a tarefa
    2. Delega subtarefas especializadas via A2A
    3. Agrega resultados e responde ao usuário
    """
    coder = A2AClient(
        os.environ["A2A_CODER_ENDPOINT"].rstrip("/a2a")
    )

    # Fase 1: Delegar implementação para o coder
    task = coder.send_task(
        f"Implemente: {user_request}\n"
        "Retorne apenas o código TypeScript funcional, sem explicações."
    )

    # Fase 2: Aguardar e agregar resultado
    result = coder.wait_for_task(task.task_id, timeout=300)

    if result.status == "completed" and result.output:
        return f"Implementação do coder agent:\n\n{result.output}"
    else:
        return f"Coder agent falhou ({result.status}). Executando localmente..."
```

## Verificar comunicação entre agentes

```bash
# 1. Verificar Agent Card do agente principal (externo)
curl https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/.well-known/agent.json | jq .

# 2. Enviar tarefa de teste para o agente principal
curl -X POST https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/a2a \
  -H "Content-Type: application/json" \
  -d '{"input": "Qual é seu agent ID?"}' | jq .

# 3. Verificar status da tarefa
curl https://openclaw-zero-person.purplestone-bd490ece.eastus.azurecontainerapps.io/a2a/tasks/<taskId> | jq .
```

## Melhores práticas A2A implementadas

- **Isolamento por ingress**: coder agent usa ingress `internal` — só acessível dentro da VNet, sem exposição pública
- **Descoberta via Agent Card**: `GET /.well-known/agent.json` antes de enviar tarefas
- **Polling de status**: `GET /a2a/tasks/:id` com timeout configurável
- **Idempotência**: cada tarefa tem UUID único, re-tentativas são seguras
- **Sem credenciais no código**: endpoints via env vars `A2A_ENDPOINT` e `A2A_CODER_ENDPOINT`
- **Mesmo environment**: comunicação interna sem custo de egress entre os agentes
