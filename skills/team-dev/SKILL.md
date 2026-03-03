---
name: team-dev
description: "Orquestra um time de agentes especializados para desenvolvimento de software. Use quando: (1) criando features completas, (2) precisar de pesquisa + implementação + review, (3) projetos maiores que exigem múltiplos passos, (4) quiser paralelizar pesquisa e codificação. O Orquestrador delega para: coder (implementação), researcher (pesquisa/docs), reviewer (code review), tester (testes). NÃO use para edições triviais de 1–2 linhas."
metadata: { "openclaw": { "emoji": "🏗️" } }
---

# Time de Desenvolvimento Multiagente

Use `sessions_spawn` para delegar a agentes especializados dentro do time.

## Agentes Disponíveis

| Agente     | ID           | Especialidade                           | Modelo            |
| ---------- | ------------ | --------------------------------------- | ----------------- |
| Coder      | `coder`      | Escrever, editar e refatorar código     | kimi-coding/k2p5  |
| Researcher | `researcher` | Pesquisar docs, APIs, explorar codebase | gemini-2.5-pro    |
| Reviewer   | `reviewer`   | Code review, qualidade, segurança       | claude-sonnet-4-6 |
| Tester     | `tester`     | Escrever e executar testes Vitest       | claude-haiku-4-5  |

## Quando Spawnar vs. Fazer Direto

**Faça direto (sem spawn):**

- Leitura de arquivos / grep / busca semântica
- Edições triviais de 1–2 linhas
- Responder perguntas sobre o código

**Spawn o agente certo:**

- Feature com múltiplos arquivos → `coder`
- Precisa entender uma lib/API externa → `researcher`
- Código novo que precisa ser validado → `reviewer`
- Nova lógica que precisa de testes → `tester`

## Fluxo Típico de Feature

```
1. Entender o pedido
2. Researcher → mapear como funciona hoje no codebase
3. Coder → implementar (com contexto do researcher)
4. Reviewer → revisar o diff
5. Tester → cobrir com testes
6. Reportar ao usuário
```

## Como Fazer Spawn

```
sessions_spawn agentId:"coder" message:"[TAREFA DETALHADA]

Contexto:
- Repo: /workspaces/openclaw
- Arquivo alvo: src/foo/bar.ts
- O que fazer: [descrição precisa]
- Restrições: [padrões a seguir, o que NOT fazer]"
```

## Paralelização

Researcher e Coder podem rodar em paralelo se a pesquisa for sobre uma parte diferente da implementação. Reviewer e Tester sempre rodam DEPOIS do Coder terminar.

```
PARALLEL:
  researcher → "como funciona X no codebase atual?"
  coder      → "implemente Y (parte independente de X)"
THEN:
  reviewer   → revisa output do coder
  tester     → testa output do coder
```

## Comunicação com o Usuário

- Anuncie quando vai spawnar: "Delegando para o coder…"
- Confirme quando receber: "Coder terminou, revisando…"
- Reporte resultado final com contexto: arquivos editados, testes passando, PR criado

## Limites

- `maxSpawnDepth`: 2 (sub-agentes podem spawnar sub-sub-agentes)
- `maxChildrenPerAgent`: 8 (máximo 8 filhos simultâneos)
- `maxConcurrent`: 8 (lane global de subagentes)
- Agentes filhos NÃO podem spawnar o Orquestrador de volta (evite loops)
