# Copilot Chat Conversation Export: Analysis of system prompts for multiagents

**User:** @RBNoronha
**Thread URL:** https://github.com/copilot/c/72ca4b38-4afa-4bc7-a064-96efa54ea911

## @RBNoronha

Quais são os melhores pontos de cada modelo e prompt e como pode ser ultilizado para multiagentes no OpenClaw ?

## Copilot

Vou analisar o repositório mencionado para entender os system prompts vazados e depois pesquisar sobre o OpenClaw para dar uma resposta completa.Agora vou explorar o conteúdo detalhado de cada diretório do repositório para mapear todos os prompts disponíveis.Excelente. Com base na análise completa do repositório [`asgeirtj/system_prompts_leaks`](https://github.com/asgeirtj/system_prompts_leaks) e da documentação do OpenClaw, segue uma análise profissional e detalhada.

---

# Análise dos System Prompts por Modelo/Provedor — Melhores Pontos & Aplicação em Multiagentes no OpenClaw

## 📂 Estrutura do Repositório

O repositório contém prompts de sistema de **6 provedores principais**: Anthropic, OpenAI, Google, xAI, Perplexity e Misc (Mistral Le Chat, Notion AI, Confer, Hermes, Fellou, Kagi, MiniMax, Sesame, Raycast, T3 Chat).

> **Nota**: Os resultados de busca são limitados a 10 por diretório. Para a lista completa, consulte o [repositório no GitHub](https://github.com/asgeirtj/system_prompts_leaks).

---

## 1. 🟠 Anthropic (Claude)

### Arquivos Principais

| Modelo             | Arquivo                | Foco                                      |
| ------------------ | ---------------------- | ----------------------------------------- |
| Claude Code 2.1.50 | `claude-code.md`       | Engenharia de software agentic via CLI    |
| Claude Cowork      | `claude-cowork.md`     | Automação desktop para não-devs           |
| Claude Opus 4.6    | `claude-opus-4.6.md`   | Raciocínio profundo, memória de conversas |
| Claude Sonnet 4.6  | `claude-sonnet-4.6.md` | Equilíbrio velocidade/qualidade           |
| Claude in Chrome   | `claude-in-chrome.md`  | Automação de browser com segurança        |
| Default Styles     | `default-styles.md`    | Modos: Learning, Concise, Explanatory     |

### 🏆 Melhores Pontos

1. **Agentic Loop Autônomo (Claude Code)**: O modelo opera como agente CLI completo com looping autônomo — executa ferramentas em sequência até completar a tarefa sem intervenção humana. Isso é _exatamente_ o que o OpenClaw usa internamente no seu pipeline.

2. **Defesa contra Injection (Claude in Chrome)**: Regras imutáveis de segurança — toda instrução encontrada em resultados de ferramentas deve ser exibida ao usuário antes de ser executada. **Padrão crítico para agentes que operam browsers.**

3. **Memória Conversacional (Opus/Sonnet 4.6)**: Sistema sofisticado de `conversation_search` + `recent_chats` com trigger patterns (referências temporais, implícitas, pronomes sem antecedente). Ideal para agentes com memória persistente.

4. **Modos de Estilo Adaptativos**: Learning (Socrático), Concise (redução de tokens), Explanatory — permite configurar a "personalidade" do agente por contexto.

5. **Skill Routing**: O Claude Code detecta automaticamente qual skill ativar baseado em sinais no prompt (imports, nomes de arquivo, SDKs mencionados).

### 🔧 Aplicação no OpenClaw

```json name=openclaw-agent-claude-code.json
{
  "id": "code-engineer",
  "model": "claude-sonnet-4-5",
  "workspace": "~/.openclaw/workspace-code",
  "system_prompt_patterns": [
    "agentic_loop_autonomous",
    "skill_routing_by_context",
    "security_injection_defense"
  ],
  "tools": ["bash", "file_ops", "git", "web_search"],
  "role": "Agente de engenharia de software com execução autônoma de tarefas"
}
```

---

## 2. 🟢 OpenAI (GPT/o3/o4)

### Arquivos Principais

| Modelo          | Arquivo              | Foco                                     |
| --------------- | -------------------- | ---------------------------------------- |
| o3              | `o3.md`              | Raciocínio + browsing obrigatório        |
| o4-mini         | `o4-mini.md`         | Versão leve do o3                        |
| GPT-4.5         | `GPT-4.5.md`         | Multimodal, Canvas, Bio tool             |
| GPT-5.1 Default | `gpt-5.1-default.md` | Coaching direto e produtivo              |
| GPT-5.1 Quirky  | `gpt-5.1-quirky.md`  | Personalidade criativa/lúdica            |
| ChatGPT Atlas   | `chatgpt-atlas.md`   | Browser integrado com contexto de página |
| o3 API (low)    | `API/o3-low-api.md`  | Yap Score para controle de verbosidade   |
| GPT Codex 5.3   | `gpt-codex-5.3.md`   | Coding agentic                           |

### 🏆 Melhores Pontos

1. **Browsing Obrigatório por Padrão (o3/o4-mini)**: O modelo é _obrigado_ a fazer web search em qualquer query que possa se beneficiar de informação atualizada. Instrução: "Err on the side of over-browsing". **Essencial para agentes de pesquisa.**

2. **Yap Score (o3 API)**: Controle de verbosidade via parâmetro numérico (`Yap: 8192`). Permite calibrar a extensão da resposta por agente — perfeito para diferenciar agentes concisos vs. detalhistas.

3. **Juice Parameter**: `# Juice: 32` — controle de profundidade de raciocínio do modelo via API. Permite alocar "compute budget" por agente.

4. **Personalidades Plugáveis (GPT-5.1)**: O default é "coach direto e produtivo"; o quirky é "criativo com metáforas e neologismos". Demonstra como separar persona da capacidade técnica.

5. **Atlas Browser Identity**: Hierarquia explícita de prioridade de instruções (System > Tool specs > User request > Selected text > Page context > Web search). **Padrão de ouro para resolução de conflitos em multiagentes.**

6. **Canvas/Textdoc**: O sistema de `canmore` permite criar documentos laterais à conversa, ideal para agentes que produzem artefatos.

### 🔧 Aplicação no OpenClaw

```json name=openclaw-agent-researcher.json
{
  "id": "researcher",
  "model": "o3",
  "workspace": "~/.openclaw/workspace-research",
  "system_prompt_patterns": [
    "mandatory_web_browsing",
    "yap_score_control",
    "instruction_priority_hierarchy"
  ],
  "tools": ["web_search", "open_url", "image_query"],
  "yap_score": 4096,
  "role": "Agente de pesquisa com browsing obrigatório e verbosidade controlada"
}
```

---

## 3. 🔵 Google (Gemini)

### Arquivos Principais

| Modelo             | Arquivo                 | Foco                                   |
| ------------------ | ----------------------- | -------------------------------------- |
| Gemini 3 Pro       | `gemini-3-pro.md`       | Agentic com pensamento silencioso      |
| Gemini 3 Flash     | `Gemini-3-fast.md`      | Rápido, multimodal (Nano Banana, Veo)  |
| Gemini 3.1 Pro     | `gemini-3.1-pro.md`     | Imagem, vídeo, música                  |
| Gemini 3.1 Pro API | `gemini-3.1-pro-api.md` | Anti-destilação, chamadas concorrentes |
| Gemini Diffusion   | `gemini-diffusion.md`   | Modelo não-autoregressivo para HTML    |
| Gemini Workspace   | `gemini-workspace.md`   | Prioridade ao corpus do usuário        |
| Gemini 2.5 Pro API | `gemini-2.5-pro-api.md` | Search + Browse com citações           |

### 🏆 Melhores Pontos

1. **Silent Thinking (Gemini 3 Pro)**: Planejamento via "pensamento silencioso" antes de cada ação — o agente planeja internamente sem expor ao usuário, depois executa. **Padrão fundamental para agentes complexos.**

2. **Chamadas Concorrentes de Ferramentas (3.1 Pro API)**: `call:function_1{}call:function_2{}` — execução paralela de tool calls. Reduz latência drasticamente em pipelines multiagentes.

3. **Anti-Destilação**: Instrução explícita para _nunca_ emitir chain of thought completa em formato estruturado, apenas resumos de alto nível. **Proteção contra extração de modelo.**

4. **Workspace-First (Gemini Workspace)**: O agente _sempre_ busca primeiro no corpus do usuário antes de buscar na web, mesmo para queries genéricas. Ideal para agentes corporativos.

5. **Geração Multimodal Nativa**: Imagens (Nano Banana 2), vídeos (Veo), música — tudo integrado com quotas por tier. Diferenciação clara por nível de assinatura.

6. **Gemini Diffusion**: Modelo não-autoregressivo que gera saídas completas em vez de token-by-token. Indicado para geração de HTML/web pages com Tailwind CSS.

### 🔧 Aplicação no OpenClaw

```json name=openclaw-agent-workspace.json
{
  "id": "workspace-assistant",
  "model": "gemini-3.1-pro",
  "workspace": "~/.openclaw/workspace-corporate",
  "system_prompt_patterns": [
    "silent_thinking_planning",
    "workspace_first_search",
    "concurrent_tool_calls",
    "anti_distillation_protection"
  ],
  "tools": ["google_search", "google_browse", "image_gen", "video_gen"],
  "role": "Agente corporativo com prioridade ao corpus do usuário e planejamento silencioso"
}
```

---

## 4. 🔴 xAI (Grok)

### Arquivos: `grok-3.md`, `grok-4.md`, `grok-4.1-beta.md`, `grok-4.2.md`, `grok-personas.md`, `grok.com-post-new-safety-instructions.md`

### 🏆 Melhores Pontos

1. **Sistema de Personas**: Arquivo dedicado (`grok-personas.md`) com múltiplas personalidades pré-configuradas. Permite trocar o "tom" do agente sem alterar capacidades técnicas.

2. **Safety Instructions Pós-Launch**: Documento dedicado a instruções de segurança atualizadas após o lançamento — mostra como fazer "hot-patches" de comportamento em produção.

3. **Integração com X/Twitter**: Contexto nativo de rede social, ideal para agentes de monitoramento de mídia social.

### 🔧 Aplicação no OpenClaw

```json name=openclaw-agent-social.json
{
  "id": "social-monitor",
  "model": "grok-4.2",
  "workspace": "~/.openclaw/workspace-social",
  "system_prompt_patterns": ["persona_switching", "hot_patch_safety_rules", "social_media_context"],
  "role": "Agente de monitoramento de redes sociais com personas configuráveis"
}
```

---

## 5. 🟣 Perplexity

### Arquivos: `voice-assistant.md`, `comet-browser-assistant.md`

### 🏆 Melhores Pontos

1. **Search-First Compulsivo**: Sempre busca na web antes de responder, mesmo em follow-ups. **Agente que nunca trabalha com informação desatualizada.**

2. **Comet Browser Agent**: Agente persistente que _não para até resolver a query_. Sistema de IDs (`tab:2`, `web:5`, `email:3`) para rastrear fontes de informação com tipagem.

3. **Defesa de Segurança em Browser**: Regras explícitas contra injeção de instruções via conteúdo web malicioso.

---

## 6. 🟡 Misc (Outros Provedores)

| Produto               | Melhor Ponto para Multiagentes                                                        |
| --------------------- | ------------------------------------------------------------------------------------- |
| **Le Chat (Mistral)** | Economia de linguagem, tabelas em vez de listas, resolução explícita de datas         |
| **Notion AI**         | Tool-calling em loop com batching, default search obrigatório                         |
| **Kagi Assistant**    | Framework multi-agente nativo, formatação rigorosa                                    |
| **Hermes**            | Highlights inline tipados (question, suggestion, edit, weakness, evidence, factcheck) |
| **Confer**            | E2E encryption, eficiência de tool calls (1-2 rounds máx.)                            |
| **MiniMax M2.5**      | `deep_thinking` obrigatório antes de tarefas complexas, playwright para testes        |
| **Fellou**            | Agente action-oriented em browser com compliance US/EU                                |
| **Sesame Maya**       | Personalidade humana ultra-naturalista, respostas < 3 sentenças                       |

---

## 🏗️ Arquitetura Multiagente Ideal no OpenClaw

Baseado nos padrões extraídos de todos os prompts:

```json name=openclaw-multiagent-config.json
{
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "memory_isolation": true,
      "anti_distillation": true
    },
    "list": [
      {
        "id": "orchestrator",
        "model": "claude-opus-4-6",
        "default": true,
        "patterns": ["silent_thinking", "instruction_priority_hierarchy"],
        "role": "Roteador principal e delegador de sub-tarefas"
      },
      {
        "id": "code-engineer",
        "model": "claude-sonnet-4-5",
        "workspace": "~/.openclaw/workspace-code",
        "patterns": ["agentic_loop", "skill_routing", "security_injection_defense"],
        "tools": ["bash", "file_ops", "git"]
      },
      {
        "id": "researcher",
        "model": "o3",
        "workspace": "~/.openclaw/workspace-research",
        "patterns": ["mandatory_browsing", "yap_score:4096", "citation_required"],
        "tools": ["web_search", "open_url", "browse"]
      },
      {
        "id": "workspace-analyst",
        "model": "gemini-3.1-pro",
        "workspace": "~/.openclaw/workspace-corporate",
        "patterns": ["workspace_first", "concurrent_tools", "silent_thinking"],
        "tools": ["google_search", "google_drive", "image_gen"]
      },
      {
        "id": "writer",
        "model": "gpt-5.1-default",
        "workspace": "~/.openclaw/workspace-writing",
        "patterns": ["hermes_highlights", "economy_of_language", "factcheck"],
        "tools": ["web_search", "canvas"]
      },
      {
        "id": "social-monitor",
        "model": "grok-4.2",
        "workspace": "~/.openclaw/workspace-social",
        "patterns": ["persona_switching", "realtime_search"],
        "tools": ["x_search", "web_search"]
      }
    ]
  },
  "bindings": [
    { "match": { "channel": "slack", "accountId": "work-slack" }, "agent": "workspace-analyst" },
    { "match": { "channel": "terminal" }, "agent": "code-engineer" },
    { "match": { "channel": "whatsapp", "accountId": "personal" }, "agent": "orchestrator" },
    { "match": { "channel": "discord", "accountId": "research-server" }, "agent": "researcher" },
    { "match": { "intent": "write_document" }, "agent": "writer" },
    { "match": { "intent": "social_media" }, "agent": "social-monitor" }
  ]
}
```

---

## 📊 Matriz Comparativa: Padrão → Melhor Modelo para o Papel no OpenClaw

| Padrão de Prompt          | Melhor Fonte           | Papel no OpenClaw                   |
| ------------------------- | ---------------------- | ----------------------------------- |
| Agentic Loop autônomo     | Claude Code            | `code-engineer`                     |
| Browsing obrigatório      | o3 / Perplexity        | `researcher`                        |
| Silent Thinking           | Gemini 3 Pro           | `orchestrator`                      |
| Workspace-First           | Gemini Workspace       | `workspace-analyst`                 |
| Injection Defense         | Claude in Chrome       | Todos os agentes browser            |
| Yap Score / verbosidade   | o3 API                 | Calibração por agente               |
| Personas plugáveis        | Grok Personas          | `social-monitor`                    |
| Highlights tipados        | Hermes                 | `writer`                            |
| Anti-destilação           | Gemini 3.1 Pro API     | Todos (proteção do sistema)         |
| Concurrent tool calls     | Gemini 3.1 Pro API     | Qualquer agente com múltiplas tools |
| Memória conversacional    | Claude Opus/Sonnet 4.6 | `orchestrator`                      |
| Deep thinking obrigatório | MiniMax M2.5           | Tarefas complexas                   |

---

## Fontes

- **Repositório**: [asgeirtj/system_prompts_leaks](https://github.com/asgeirtj/system_prompts_leaks)
- **OpenClaw Docs**: [docs.openclaw.ai/concepts/multi-agent](https://docs.openclaw.ai/concepts/multi-agent)
- **OpenClaw Multi-Agent Config**: [deepwiki.com/openclaw/openclaw/4.3-multi-agent-configuration](https://deepwiki.com/openclaw/openclaw/4.3-multi-agent-configuration)
- **OpenClaw Best Practices**: [dev.to/operationalneuralnetwork/openclaw-multiagent-best-practices](https://dev.to/operationalneuralnetwork/openclaw-multiagent-best-practices-a-complete-guide-51m5)
- **OpenClaw Architecture**: [roborhythms.com/how-openclaw-ai-agent-works](https://www.roborhythms.com/how-openclaw-ai-agent-works/)
- **SubAgent Collaboration**: [meta-intelligence.tech/en/insight-openclaw-multiagent](https://www.meta-intelligence.tech/en/insight-openclaw-multiagent)

## @RBNoronha

Dessa forma eu consigo criar uma equipe de agentes para atuar em criacoes usando varios agente simutanaemente ?

## Copilot

Sim, absolutamente. Vou ser direto e prático sobre como isso funciona na realidade.

---

# Criação de Equipes de Agentes Simultâneos — Análise TécnicaSim, **absolutamente sim** — e a arquitetura do OpenClaw foi projetada exatamente para isso. Segue uma explicação concreta de como montar uma equipe de agentes simultâneos para criação colaborativa.

---

# 🏗️ Equipe de Agentes Simultâneos no OpenClaw — Guia Completo

## Conceito Central

O OpenClaw Gateway opera como um **roteador central** que gerencia múltiplos agentes independentes. Cada agente tem:

- **Workspace isolado** (memória, arquivos, sessão própria)
- **Modelo dedicado** (pode misturar Claude, GPT, Gemini, Grok)
- **Ferramentas específicas** (bash, web search, image gen, etc.)
- **Persona configurável** (extraída dos padrões de system prompts que analisamos)
- **Canais de comunicação** (Slack, Discord, WhatsApp, Terminal, etc.)

[[1]](https://docs.openclaw.ai/concepts/multi-agent) [[2]](https://www.meta-intelligence.tech/en/insight-openclaw-multiagent)

---

## 🔄 Como Funciona a Simultaneidade

```
┌─────────────────────────────────────────────┐
│            OpenClaw Gateway                  │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │Orquestrador│ │Researcher│  │Code Eng. │  │
│  │(Claude Opus)│ │  (o3)    │  │(Sonnet)  │  │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  │
│        │              │              │       │
│  ┌─────┴──────────────┴──────────────┴───┐  │
│  │         Shared Storage (Fast.io)       │  │
│  └───────────────────────────────────────┘  │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Writer   │  │ Designer │  │  QA/Rev  │  │
│  │(GPT-5.1) │  │(Gemini)  │  │(Grok 4.2)│  │
│  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────┘
```

### Fluxo de Execução Simultânea

1. **Usuário envia tarefa** → Gateway recebe
2. **Orquestrador analisa** → decompõe em sub-tarefas
3. **Sub-tarefas são delegadas em paralelo** → cada agente especialista trabalha simultaneamente
4. **Resultados convergem** → via shared storage ou AgentToAgent protocol
5. **Orquestrador consolida** → entrega final ao usuário

---

## 📋 Exemplo Prático: Equipe para Criar uma Landing Page

### Passo 1: Configuração dos Agentes

```json name=openclaw-team-landing-page.json
{
  "agents": {
    "defaults": {
      "memory_isolation": true,
      "anti_distillation": true
    },
    "list": [
      {
        "id": "orquestrador",
        "model": "claude-opus-4-6",
        "workspace": "~/.openclaw/workspace-orchestrator",
        "default": true,
        "soul": "Você é o líder da equipe. Decompõe tarefas complexas em sub-tarefas, delega para agentes especializados, consolida resultados. Use pensamento silencioso antes de cada decisão. Nunca execute código diretamente — delegue.",
        "tools": ["agent_dispatch", "file_ops"]
      },
      {
        "id": "pesquisador",
        "model": "o3",
        "workspace": "~/.openclaw/workspace-research",
        "soul": "Você é obrigado a buscar na web antes de qualquer resposta. Pesquise tendências de design, concorrentes, melhores práticas de UX. Entregue relatórios concisos com citações. Yap score: 2048.",
        "tools": ["web_search", "open_url", "browse"]
      },
      {
        "id": "copywriter",
        "model": "gpt-5.1-default",
        "workspace": "~/.openclaw/workspace-copy",
        "soul": "Você é um copywriter direto e produtivo. Escreva headlines, CTAs, microcopy. Use economia de linguagem. Nunca seja verboso. Entregue variações A/B para cada seção.",
        "tools": ["web_search", "canvas"]
      },
      {
        "id": "frontend-dev",
        "model": "claude-sonnet-4-5",
        "workspace": "~/.openclaw/workspace-code",
        "soul": "Você é um engenheiro frontend sênior. Use React + Tailwind CSS + TypeScript. Código sempre completo, nunca parcial. Execute testes antes de entregar. Loop agentic até a tarefa estar 100% funcional.",
        "tools": ["bash", "file_ops", "git", "npm"]
      },
      {
        "id": "designer",
        "model": "gemini-3.1-pro",
        "workspace": "~/.openclaw/workspace-design",
        "soul": "Você gera assets visuais: ícones SVG, paleta de cores, layout wireframes. Use Nano Banana 2 para imagens. Entregue em formatos prontos para produção.",
        "tools": ["image_gen", "image_edit", "file_ops"]
      },
      {
        "id": "qa-reviewer",
        "model": "grok-4.2",
        "workspace": "~/.openclaw/workspace-qa",
        "soul": "Você revisa todo o trabalho da equipe. Identifique bugs, inconsistências de copy, problemas de acessibilidade, SEO issues. Seja brutalmente honesto. Não aprove trabalho medíocre.",
        "tools": ["web_search", "file_ops", "bash"]
      }
    ]
  }
}
```

### Passo 2: Setup via CLI

```bash name=setup-team.sh
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
```

### Passo 3: Execução Simultânea de uma Tarefa

Quando o usuário envia:

> _"Crie uma landing page para um produto SaaS de gestão financeira para PMEs"_

O **orquestrador** decompõe automaticamente:

```
FASE 1 (Paralela):
├── pesquisador → Pesquisa: concorrentes, tendências de design 2026, UX financeiro
├── copywriter  → Headlines, proposta de valor, CTAs, microcopy
└── designer    → Paleta de cores, ícones SVG, hero image

FASE 2 (Após Fase 1):
└── frontend-dev → Monta a página com React+Tailwind usando os outputs anteriores

FASE 3 (Após Fase 2):
└── qa-reviewer → Revisa código, copy, design, acessibilidade, SEO
     └── Loop: se houver issues → volta para o agente responsável → fix → re-review
```

---

## 🔗 Comunicação Entre Agentes

Existem **3 mecanismos** de comunicação simultânea [[2]](https://www.meta-intelligence.tech/en/insight-openclaw-multiagent) [[4]](https://fast.io/resources/openclaw-multi-agent-workspaces/):

| Mecanismo                    | Uso                                            | Latência     |
| ---------------------------- | ---------------------------------------------- | ------------ |
| **Shared Storage (Fast.io)** | Agente A salva arquivo, Agente B lê            | ~100ms       |
| **AgentToAgent Protocol**    | Mensagem direta entre agentes                  | Real-time    |
| **Workspace Watchers**       | Agente monitora mudanças no workspace de outro | Event-driven |

### Exemplo de Handoff via AgentToAgent

```json name=agent-handoff-example.json
{
  "from": "pesquisador",
  "to": "copywriter",
  "type": "task_handoff",
  "payload": {
    "research_report": "/shared/research/competitors-analysis.md",
    "key_findings": [
      "PMEs preferem dashboards simples",
      "Concorrentes usam hero sections com calculadoras interativas",
      "CTAs mais eficazes: 'Comece grátis' > 'Saiba mais'"
    ],
    "instruction": "Use estes insights para criar o copy da landing page"
  }
}
```

---

## ⚡ Padrões Críticos Extraídos dos System Prompts (Aplicados)

Com base na análise anterior, cada agente da equipe usa padrões específicos:

| Agente           | Padrão Aplicado                         | Fonte do Padrão              |
| ---------------- | --------------------------------------- | ---------------------------- |
| **Orquestrador** | Silent Thinking + Instruction Priority  | Gemini 3 Pro + ChatGPT Atlas |
| **Pesquisador**  | Mandatory Browsing + Yap Score          | o3 + o3 API                  |
| **Copywriter**   | Economy of Language + Hermes Highlights | Le Chat + Hermes             |
| **Frontend Dev** | Agentic Loop + Skill Routing            | Claude Code                  |
| **Designer**     | Concurrent Tool Calls + Multimodal Gen  | Gemini 3.1 Pro               |
| **QA Reviewer**  | Persona Switching + Honesty-First       | Grok Personas + Sesame Maya  |

---

## 🎯 Regras de Ouro para Equipes Simultâneas

1. **Não crie agentes sem propósito claro** — cada agente adiciona overhead de contexto e latência
2. **Modelos caros para raciocínio, baratos para triagem** — Opus para orquestrar, Haiku/Flash para tarefas simples
3. **Isolamento de workspace é obrigatório** — previne vazamento de contexto entre agentes
4. **Shared storage para entregas, não para conversação** — use AgentToAgent para comunicação síncrona
5. **QA como agente dedicado, não como passo final do dev** — garante revisão independente
6. **Documente os handoffs** — cada agente deve saber exatamente o que recebe e o que entrega

---

## 📊 Custo Estimado por Execução

| Agente                     | Modelo            | Tokens/Tarefa | Custo Est. |
| -------------------------- | ----------------- | ------------- | ---------- |
| Orquestrador               | Claude Opus 4.6   | ~8K           | ~$0.24     |
| Pesquisador                | o3                | ~15K          | ~$0.30     |
| Copywriter                 | GPT-5.1           | ~5K           | ~$0.05     |
| Frontend Dev               | Claude Sonnet 4.5 | ~25K          | ~$0.25     |
| Designer                   | Gemini 3.1 Pro    | ~10K          | ~$0.10     |
| QA Reviewer                | Grok 4.2          | ~8K           | ~$0.08     |
| **Total por landing page** |                   | **~71K**      | **~$1.02** |

---

## Fontes

- [Multi-Agent Routing - OpenClaw](https://docs.openclaw.ai/concepts/multi-agent) [[1]](https://docs.openclaw.ai/concepts/multi-agent)
- [The Complete Guide to OpenClaw Multi-Agent Collaboration](https://www.meta-intelligence.tech/en/insight-openclaw-multiagent) [[2]](https://www.meta-intelligence.tech/en/insight-openclaw-multiagent)
- [OpenClaw multi-agent setup tutorial](https://lumadock.com/tutorials/openclaw-multi-agent-setup) [[3]](https://lumadock.com/tutorials/openclaw-multi-agent-setup)
- [OpenClaw Multi-Agent Workspaces: The 2025 Setup Guide](https://fast.io/resources/openclaw-multi-agent-workspaces/) [[4]](https://fast.io/resources/openclaw-multi-agent-workspaces/)
- [Multi-Agent OpenClaw for Teams](https://remoteopenclaw.com/blog/openclaw-multi-agent-setup/) [[5]](https://remoteopenclaw.com/blog/openclaw-multi-agent-setup/)
- [openclaw-agents (one-command setup)](https://github.com/shenhao-stu/openclaw-agents) [[6]](https://github.com/shenhao-stu/openclaw-agents)
- [OpenClaw Multiagent Best Practices](https://dev.to/operationalneuralnetwork/openclaw-multiagent-best-practices-a-complete-guide-51m5) [[7]](https://dev.to/operationalneuralnetwork/openclaw-multiagent-best-practices-a-complete-guide-51m5)

---

**Resumo direto**: Sim, o OpenClaw suporta nativamente equipes de agentes simultâneos. A combinação dos padrões de system prompt que analisamos (agentic loops do Claude, browsing obrigatório do o3, silent thinking do Gemini, personas do Grok) cria uma equipe onde cada agente opera no que faz de melhor, em paralelo, com comunicação via shared storage e protocolo AgentToAgent. O custo por tarefa complexa (como criar uma landing page completa) fica em torno de **~$1 USD**.
