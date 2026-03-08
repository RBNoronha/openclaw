---
name: a2a-agent-lookup
description: "Verificação e lookup de agentes A2A — descobre, valida e cataloga agentes disponíveis na rede. Use quando: (1) verificando se um agente externo está online e acessível, (2) listando capacidades de agentes disponíveis, (3) encontrando o agente certo para uma tarefa específica, (4) diagnosticando problemas de conectividade A2A. NÃO use para comunicação ou delegação de tarefas (use a2a-protocol)."
metadata: { "openclaw": { "emoji": "🔍" } }
---

# A2A Agent Lookup — Descoberta e Verificação de Agentes

Ferramentas para descobrir, verificar e catalogar agentes A2A na rede.

## Verificar se um agente está online

```bash
# Verificar Agent Card
curl -sf https://agente.azurecontainerapps.io/.well-known/agent.json \
  && echo "✅ Agente online" \
  || echo "❌ Agente offline"

# Verificar health
curl -sf https://agente.azurecontainerapps.io/healthz | jq .
```

## Listar capacidades do agente

```bash
curl https://agente.azurecontainerapps.io/.well-known/agent.json | jq '{
  id: .id,
  name: .name,
  endpoint: .endpoint,
  skills: [.skills[].id],
  auth_type: .auth.type
}'
```

## Lookup em múltiplos agentes

```bash
# agents.txt — lista de endpoints (um por linha)
# https://openclaw-main.azurecontainerapps.io
# https://openclaw-coder.azurecontainerapps.io
# https://openclaw-qa.azurecontainerapps.io

while IFS= read -r url; do
  echo -n "Verificando ${url}... "
  result=$(curl -sf --max-time 5 "${url}/.well-known/agent.json" 2>/dev/null)
  if [[ -n "$result" ]]; then
    name=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','?'))")
    skills=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(s['id'] for s in d.get('skills',[])))")
    echo "✅ ${name} [skills: ${skills}]"
  else
    echo "❌ Offline ou inacessível"
  fi
done < agents.txt
```

## Encontrar agente por skill

```python
from a2a_client import A2AClient

AGENTS = [
    "https://openclaw-main.azurecontainerapps.io",
    "https://openclaw-coder.azurecontainerapps.io",
    "https://openclaw-qa.azurecontainerapps.io",
]

def find_agent_with_skill(skill_id: str) -> list[dict]:
    matches = []
    for url in AGENTS:
        try:
            client = A2AClient(url, timeout=5)
            card = client.discover()
            skill_ids = [s["id"] for s in card.skills]
            if skill_id in skill_ids:
                matches.append({"url": url, "name": card.name, "card": card})
        except Exception:
            pass
    return matches

# Encontrar agente com skill de Azure infra
agents = find_agent_with_skill("azure-infra")
for a in agents:
    print(f"✅ {a['name']} — {a['url']}")
```

## Diagnosticar conectividade

```bash
# Testar rota completa: discovery → task → status
AGENT_URL="https://openclaw-main.azurecontainerapps.io"

echo "1. Verificando Agent Card..."
curl -sf "${AGENT_URL}/.well-known/agent.json" | jq .name

echo "2. Enviando tarefa de teste..."
TASK=$(curl -sf -X POST "${AGENT_URL}/a2a" \
  -H "Content-Type: application/json" \
  -d '{"input": "ping"}')
TASK_ID=$(echo "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin)['taskId'])")
echo "   Task ID: ${TASK_ID}"

echo "3. Verificando status..."
curl -sf "${AGENT_URL}/a2a/tasks/${TASK_ID}" | jq .task.status
```

## Mapa de agentes no Container Apps Environment

```bash
# Listar todos os Container Apps no mesmo environment
az containerapp list \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query "[].{name:name, fqdn:properties.configuration.ingress.fqdn, type:properties.configuration.ingress.external}" \
  --output table
```
