# Relatório de Mudanças e Atualizações — OpenClaw

> Este documento é atualizado a cada mudança, melhoria ou configuração aplicada ao ambiente OpenClaw.
> Ordem: mais recente primeiro.

---

## [2026-03-03] Correção do agente `hitch` — HTTP 404 ao usar `azure-openai/gpt-4o`

### Contexto

O agente `hitch` estava falhando com `HTTP 404: Resource not found` ao tentar usar o modelo primário `azure-openai/gpt-4o`. Todos os testes anteriores resultavam no fallback para `kimi-coding/k2p5`.

### Diagnóstico

**Causa raiz:** O campo `api` do provider `azure-openai` estava configurado como `"openai-responses"`. O tipo `openai-responses` faz a biblioteca `@mariozechner/pi-ai` chamar `{baseUrl}/responses` — endpoint da nova OpenAI Responses API que **não existe no Azure OpenAI v1**, resultando em HTTP 404.

O Azure OpenAI v1 somente suporta o endpoint `/chat/completions`, confirmado via `curl` direto que retornou resposta correta.

Problema adicional: o tipo `openai-completions` usa a variável de ambiente `OPENAI_API_KEY`, mas o config tinha apenas `AZURE_AI_API_KEY`, sem mapear uma para a outra.

### Investigação de código

| Arquivo                                                                 | Descoberta                                                                                                                                              |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `node_modules/@mariozechner/pi-ai/dist/providers/register-builtins.js`  | `openai-responses` → `streamOpenAIResponses`; `azure-openai-responses` → `streamAzureOpenAIResponses`; `openai-completions` → `streamOpenAICompletions` |
| `node_modules/@mariozechner/pi-ai/dist/providers/openai-responses.js`   | Com provider ≠ `openai`, chama `{baseUrl}/responses` via cliente OpenAI SDK                                                                             |
| `node_modules/@mariozechner/pi-ai/dist/providers/openai-completions.js` | Chama `{baseUrl}/chat/completions`; autentica via `OPENAI_API_KEY`                                                                                      |
| `node_modules/@mariozechner/pi-ai/dist/env-api-keys.js`                 | Mapeamento de providers para env vars: `openai-completions` usa `OPENAI_API_KEY`                                                                        |
| `src/agents/pi-embedded-runner/model.ts`                                | `api: providerCfg?.api ?? "openai-responses"` — default que causava o problema                                                                          |

### Correções aplicadas

**Ambos os arquivos de configuração foram atualizados** (`/home/codespace/.openclaw/openclaw.json` e `/workspaces/.openclaw/openclaw.json`):

| Campo                               | Antes                | Depois                  |
| ----------------------------------- | -------------------- | ----------------------- |
| `models.providers.azure-openai.api` | `"openai-responses"` | `"openai-completions"`  |
| `env.OPENAI_API_KEY`                | _(ausente)_          | `"${AZURE_AI_API_KEY}"` |

### Validação

```
pnpm openclaw agent --agent hitch --message "ping"
→ pong 🏓
```

O agente respondeu usando `azure-openai/gpt-4o` sem falhar para fallbacks.

### Estado após a correção

| Item                                                   | Status                          |
| ------------------------------------------------------ | ------------------------------- |
| Agente `hitch` — modelo primário `azure-openai/gpt-4o` | ✅ funcional                    |
| Endpoint Azure `…/openai/v1/chat/completions`          | ✅ respondendo                  |
| `AZURE_AI_API_KEY` configurada no env                  | ✅                              |
| `OPENAI_API_KEY` mapeada para `${AZURE_AI_API_KEY}`    | ✅                              |
| Binding schema (campos `content.pattern` inválidos)    | ✅ corrigido em sessão anterior |
| Docker push para GHCR `ghcr.io/rbnoronha/openclaw`     | ✅ `2026.3.2` + `latest`        |

---

## [2026-03-03] Correção de falhas na suíte de testes + validação dos 8 agentes via gateway

### Contexto

Sessão de manutenção focada em: (1) corrigir 28 falhas de teste causadas por ACL world-writable em `/tmp` no Codespace, (2) verificar 8 agentes do time, (3) corrigir IDs de modelos desatualizados no `openclaw.json`.

### Falhas de Teste Corrigidas

**Problema raiz:** O `/tmp` no Codespace tem ACL POSIX `1757` (sticky + world-writable), que aplica bit `o+w` a todos os novos diretórios criados — conflitando com o security check de `discovery.ts` que bloqueia paths com bit `0o002`.

**Solução (`test/setup.ts`):** Monkey-patch nas funções de criação de arquivos/diretórios (`fs.mkdirSync`, `fs.writeFileSync`, `fs.promises.mkdir`, `fs.promises.writeFile`). Após cada criação, remove apenas o bit `o+w` (`mode & ~0o002`) sem alterar outros bits — preservando permissões como `0o600` usadas pelos testes de sessão.

**Testes corrigidos:**

| Arquivo                                       | Falhas corrigidas                                |
| --------------------------------------------- | ------------------------------------------------ |
| `src/plugin-sdk/loader/discovery.test.ts`     | 11                                               |
| `src/plugin-sdk/loader/loader.test.ts`        | 25                                               |
| `src/config/config.plugin-validation.test.ts` | 2 (incl. stale ref. a `google-antigravity-auth`) |

**Teste stale (`config.plugin-validation.test.ts`):** O plugin `google-antigravity-auth` foi re-adicionado como extensão real no commit `e65057ef9`, mas o teste ainda referenciava seu ID como entrada de `LEGACY_REMOVED_PLUGIN_IDS`. Solução: export do Set `LEGACY_REMOVED_PLUGIN_IDS` de `validation.ts` + injeção de ID stub temporário no teste.

### Resultado Final dos Testes

| Métrica       | Valor                                        |
| ------------- | -------------------------------------------- |
| Tests passed  | 5892                                         |
| Tests failed  | 0                                            |
| Tests skipped | 2 (1 intencional: `gateway.sigterm.test.ts`) |
| Test files    | 736/737 passed                               |

### Commits

| Hash        | Mensagem                                                                         |
| ----------- | -------------------------------------------------------------------------------- |
| `f7fe5a511` | `fix(tests): resolve world-writable /tmp ACL failures and stale validation test` |
| `cbfe3165d` | `fix(tests): use precise world-write removal instead of fixed chmod`             |

### Validação dos 8 Agentes via Gateway

Gateway rodando: PID 142684, `ws://127.0.0.1:18789`, `gateway.mode: local`.

| Agente           | Status           | Provider/Modelo usado                       |
| ---------------- | ---------------- | ------------------------------------------- |
| `orquestrador`   | ✅ OK            | kimi-coding/k2p5 (primário, ~120s)          |
| `coder`          | ✅ OK            | kimi-coding/k2p5 (fallback)                 |
| `researcher`     | ✅ OK            | kimi-coding/k2p5 (fallback)                 |
| `reviewer`       | ✅ OK            | github-copilot/claude-sonnet-4.6 (fallback) |
| `tester`         | ✅ OK            | fallback disponível                         |
| `copywriter`     | ✅ OK            | azure-foundry/DeepSeek-V3.2-Speciale        |
| `designer`       | ✅ OK (após fix) | google/gemini-2.5-pro                       |
| `social-monitor` | ✅ OK            | azure-foundry/grok-4-fast-reasoning         |

### Correções de Config (`/home/codespace/.openclaw/openclaw.json`)

- **IDs de modelo corrigidos:** `google/gemini-2.5-pro-preview` → `google/gemini-2.5-pro` e `google/gemini-2.5-flash-preview` → `google/gemini-2.5-flash` (afetou agentes `gemini`, `researcher`, `designer`).
- **Designer:** adicionado `github-copilot/claude-sonnet-4.6` como fallback final.
- **azure-openai provider:** removido campo `apiVersion` não reconhecido pelo schema do OpenClaw 2026.3.2 (validação Zod agora strict após commit `3002f13ca`).

### Plugins

12/39 plugins carregados — estado intencional. Os 27 "disabled" são plugins de canal (Discord, Slack, etc.) não configurados pelo operador. Nenhum plugin com erro.

---

## [2026-03-03] SOUL.md — melhorias com padrões avançados da análise de prompts

### Contexto

Revisão dos SOUL.md dos 8 agentes do time de desenvolvimento para incorporar padrões identificados na análise de system prompts em `/workspaces/openclaw/Prompts/Orientacoes/analysis_of_system_prompts_for_multiagents.md`. Os arquivos anteriores já cobriavam os padrões principais, mas faltavam padrões de anti-destilação, Yap Score, Hermes Highlights, Canvas artifacts e Personas plugáveis.

### Agentes Atualizados

| Agente           | Padrões Adicionados                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| `orquestrador`   | Memória conversacional (Claude Opus pattern) + Anti-destilação                                              |
| `researcher`     | Yap Score 4096 (o3 API pattern)                                                                             |
| `reviewer`       | Hermes Highlights tipados (`weakness`, `evidence`, `suggestion`, `factcheck`, `question`) + Anti-destilação |
| `tester`         | Anti-destilação (chain-of-thought interno permanece interno)                                                |
| `copywriter`     | Canvas/Textdoc artifacts (GPT-4.5 pattern) + Hermes Highlights para feedback de copy                        |
| `designer`       | Anti-destilação                                                                                             |
| `social-monitor` | Personas plugáveis (Grok Personas pattern) + Yap Score 3072 + Anti-destilação                               |

### Padrões de Referência

| Padrão                 | Fonte Original                                                        |
| ---------------------- | --------------------------------------------------------------------- |
| Anti-destilação        | Gemini 3.1 Pro API — nunca expor chain-of-thought completo            |
| Yap Score              | o3 API — calibrar verbosidade por agente (`Yap: N`)                   |
| Hermes Highlights      | Hermes — annotations inline tipadas para feedback estruturado         |
| Canvas/Textdoc         | GPT-4.5 — artefatos de texto paralelos à conversa principal           |
| Personas plugáveis     | Grok Personas — troca de tom sem alterar capacidades técnicas         |
| Memória conversacional | Claude Opus 4.6 — detectar referências implícitas a contexto anterior |

---

## [2026-03-03] Plugins google-antigravity-auth e google-gemini-cli-auth habilitados

### Contexto

Após a implementação do código OAuth no repositório, os plugins precisavam ser ativados explicitamente no `openclaw.json`. Ambos são plugins de autenticação OAuth sem esquema de configuração adicional — apenas `enabled: true`.

### Mudanças

- **`/workspaces/.openclaw/openclaw.json`**: adicionado `plugins.entries.google-antigravity-auth: {enabled: true}` e `plugins.entries.google-gemini-cli-auth: {enabled: true}`
- Gateway reiniciado — ambos confirmados como `loaded`:
  - `google-antigravity-auth` — provedor `google-antigravity` ativo
  - `google-gemini-cli-auth` — provedor `google-gemini-cli` ativo

### Observação Importante

O primeiro uso de cada provedor requer completar um fluxo OAuth interativo (`openclaw providers auth google-antigravity` / `openclaw providers auth google-gemini-cli`). No Codespace, o callback precisa de `--no-open` + URL manual ou forwarding de porta para o browser local.

---

## [2026-03-03] memory-lancedb — GitHub Models como embedding primário + Azure fallback

### Contexto

Substituição do embedding primário do memory-lancedb de Azure OpenAI para GitHub Models (PAT-based, gratuito no Codespace via `GITHUB_TOKEN`), mantendo Azure como fallback silencioso.

### Arquivos Modificados

| Arquivo                               | Mudança                                                                                                                                                                                                                                       |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `extensions/memory-lancedb/config.ts` | Adicionado tipo `EmbeddingConfig`; campo `embeddingFallback?: EmbeddingConfig` em `MemoryConfig`; nomes `openai/text-embedding-3-small` e `openai/text-embedding-3-large` em `EMBEDDING_DIMENSIONS`; parse e validação de `embeddingFallback` |
| `extensions/memory-lancedb/index.ts`  | Classe `Embeddings` aceita 4º param `fallback`; cria `fallbackClient` + `fallbackModel`; `embed()` envolve chamada primária em try/catch e faz retry com fallback                                                                             |
| `/workspaces/.openclaw/openclaw.json` | Embedding primário: `${GITHUB_TOKEN}` → `https://models.github.ai/inference` → `openai/text-embedding-3-small` (dim 1536); fallback: Azure key → `https://azrblnai.openai.azure.com/...` → `text-embedding-3-small`                           |

### Resultado

- `memory-lancedb` inicializado com sucesso: `model: openai/text-embedding-3-small` (GitHub Models)
- Fallback automático e transparente para Azure se GitHub Models falhar

---

## [2026-03-03] Orquestrador — modelo primário restaurado para kimi-coding/k2p5

### Mudança

- Revertido o modelo primário do agente `orquestrador` de `anthropic/claude-sonnet-4-6` para `kimi-coding/k2p5`
- `anthropic/claude-sonnet-4-6` permanece como fallback
- **Justificativa**: kimi-coding/k2p5 era o modelo intencionado originalmente; a troca anterior foi temporária para teste

---

## [2026-03-03] Rebuild e push de imagens Docker para ACR e Docker Hub

### Contexto

Após as mudanças de i18n (tradução de skills e comandos) e a criação da feature `auto-translate`, as imagens Docker foram reconstruídas e publicadas nos dois registries para refletir o estado atualizado do repositório.

### Imagens Buildadas

| Tag        | Digest (Docker Hub)                                                       | Criação (UTC)       |
| ---------- | ------------------------------------------------------------------------- | ------------------- |
| `2026.3.2` | `sha256:a59c5008cfb5d03e879c1a55335627d0c4afbd2d85f7ae8a313ea634f4b6c3d6` | 2026-03-03 04:27:17 |
| `latest`   | `sha256:a59c5008cfb5d03e879c1a55335627d0c4afbd2d85f7ae8a313ea634f4b6c3d6` | 2026-03-03 04:27:17 |

### Registries Atualizados

| Registry                                  | Tags pushadas        | Status |
| ----------------------------------------- | -------------------- | ------ |
| `acrtemplateopenclaw.azurecr.io/openclaw` | `2026.3.2`, `latest` | ✅     |
| `renanbesserra/openclaw` (Docker Hub)     | `2026.3.2`, `latest` | ✅     |

### Mudanças incluídas nesta imagem vs. anterior

- 43 `skills/*/SKILL.md` com `description` traduzida para PT-BR
- `src/auto-reply/commands-registry.data.ts` — 35 descrições de comandos em PT-BR
- `src/agents/skills/auto-translate.ts` — novo módulo de auto-tradução de skills
- `src/agents/skills/refresh.ts` — integração auto-translate no watcher
- `src/config/types.skills.ts` — tipo `SkillsAutoTranslateConfig`
- `dist/` reconstruído pela `pnpm build` (build limpo, sem erros)

---

## [2026-03-03] Tradução de descriptions dos comandos de barra para PT-BR

**Arquivo:** `src/auto-reply/commands-registry.data.ts`

Todas as propriedades `description` dos comandos de barra definidos em `buildChatCommands()` foram traduzidas do inglês para PT-BR. Também foram traduzidas as `description` de alguns argumentos (`args`) internos onde aplicável.

| Comando                      | Antes                                                              | Depois                                                                                     |
| ---------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `/help`                      | `Show available commands.`                                         | `Mostrar comandos disponíveis.`                                                            |
| `/commands`                  | `List all slash commands.`                                         | `Listar todos os comandos de barra.`                                                       |
| `/skill`                     | `Run a skill by name.`                                             | `Execute uma habilidade pelo nome.`                                                        |
| `/skill` arg `name`          | `Skill name`                                                       | `Nome da habilidade`                                                                       |
| `/skill` arg `input`         | `Skill input`                                                      | `Contribuição de habilidades`                                                              |
| `/status`                    | `Show current status.`                                             | `Mostrar estado atual.`                                                                    |
| `/allowlist`                 | `List/add/remove allowlist entries.`                               | `Listar/adicionar/remover entradas da lista de permissões.`                                |
| `/approve`                   | `Approve or deny exec requests.`                                   | `Aprove ou negue solicitações executivas.`                                                 |
| `/context`                   | `Explain how context is built and used.`                           | `Explique como o contexto é construído e usado.`                                           |
| `/export-session`            | `Export current session to HTML file with full system prompt.`     | `Exporte a sessão atual para um arquivo HTML com prompt completo do sistema.`              |
| `/export-session` arg `path` | `Output path (default: workspace)`                                 | `Caminho de saída (padrão: espaço de trabalho)`                                            |
| `/tts`                       | `Control text-to-speech (TTS).`                                    | `Controle a conversão de texto em fala (TTS).`                                             |
| `/tts` arg `value`           | `Provider, limit, or text`                                         | `Provedor, limite ou texto`                                                                |
| `/whoami`                    | `Show your sender id.`                                             | `Mostre seu ID de remetente.`                                                              |
| `/session`                   | `Manage session-level settings (for example /session idle).`       | `Gerenciar configurações no nível da sessão (por exemplo, /sessão inativa).`               |
| `/subagents`                 | `List, kill, log, spawn, or steer subagent runs for this session.` | `Listar, eliminar, registrar, gerar ou orientar execuções de subagentes para esta sessão.` |
| `/acp`                       | `Manage ACP sessions and runtime options.`                         | `Gerencie sessões ACP e opções de tempo de execução.`                                      |
| `/debug`                     | `Set runtime debug overrides.`                                     | `Defina substituições de depuração em tempo de execução.`                                  |
| `/usage`                     | `Usage footer or cost summary.`                                    | `Rodapé de uso ou resumo de custos.`                                                       |
| `/stop`                      | `Stop the current run.`                                            | `Interrompa a execução atual.`                                                             |
| `/activation`                | `Set group activation mode.`                                       | `Definir modo de ativação do grupo.`                                                       |
| `/send`                      | `Set send policy.`                                                 | `Definir política de envio.`                                                               |
| `/reset`                     | `Reset the current session.`                                       | `Redefinir a sessão atual.`                                                                |
| `/new`                       | `Start a new session.`                                             | `SIniciar uma nova sessão.`                                                                |
| `/compact`                   | `Compact the session context.`                                     | `Compactar o contexto da sessão.`                                                          |
| `/think`                     | `Set thinking level.`                                              | `Definir nível de raciocínio.`                                                             |
| `/verbose`                   | `Toggle verbose mode.`                                             | `Alternar modo detalhado.`                                                                 |
| `/reasoning`                 | `Toggle reasoning visibility.`                                     | `Alternar visibilidade do raciocínio.`                                                     |
| `/elevated`                  | `Toggle elevated mode.`                                            | `Alternar modo elevado.`                                                                   |
| `/exec`                      | `Set exec defaults for this session.`                              | `Definir padrões de execução para esta sessão.`                                            |
| `/model`                     | `Show or set the model.`                                           | `Mostrar ou definir o modelo.`                                                             |
| `/models`                    | `List model providers or provider models.`                         | `Listar fornecedores de modelos ou modelos de fornecedores.`                               |
| `/queue`                     | `Adjust queue settings.`                                           | `Ajustar configurações da fila.`                                                           |
| `/bash`                      | `Run host shell commands (host-only).`                             | `Executar comandos do shell do host (apenas no host).`                                     |

> **Nota:** Os campos `description` dos argumentos internos (como `choices`, `type`, `captureRemaining`) e os valores de `argsMenu.title` **não** foram alterados — permanecem em inglês pois são texto técnico/de sistema.

---

## [2026-03-03] Auto-tradução de descriptions de Skills para PT-BR

### Contexto

Todas as skills do diretório `skills/` do repositório tinham a propriedade `description:` em inglês. Duas ações foram tomadas:

1. **Tradução manual em lote** — todos os arquivos `SKILL.md` do diretório `skills/` (43 arquivos) tiveram a `description` traduzida para PT-BR.
2. **Funcionalidade de auto-tradução automática** — nova feature no core que detecta novos `SKILL.md` adicionados (ex: via `clawhub install`) e traduz automaticamente a `description` para PT-BR via chamada a um endpoint LLM compatível com OpenAI.

---

### 1. Traduções manuais em lote

**43 arquivos `skills/*/SKILL.md` modificados.** Cada `description:` foi reescrita em PT-BR mantendo nomes de ferramentas, binários, CLIs e paths no original. Lista completa:

| Skill                | Descrição traduzida (resumida)                                       |
| -------------------- | -------------------------------------------------------------------- |
| `coding-agent`       | Delegue tarefas de codificação para agentes Codex, Claude Code ou Pi |
| `github`             | Operações GitHub via CLI `gh`                                        |
| `wacli`              | Envie mensagens WhatsApp via CLI wacli                               |
| `sag`                | Síntese de voz com ElevenLabs no estilo do `say` do macOS            |
| `oracle`             | Melhores práticas para CLI oracle                                    |
| `eightctl`           | Controle pods Eight Sleep                                            |
| `obsidian`           | Trabalhe com vaults do Obsidian                                      |
| `gog`                | CLI do Google Workspace                                              |
| `xurl`               | Requisições autenticadas à API do X (Twitter)                        |
| `nano-banana-pro`    | Gere/edite imagens via Gemini 3 Pro Image                            |
| `goplaces`           | API Google Places via CLI goplaces                                   |
| `nano-pdf`           | Edite PDFs com linguagem natural                                     |
| `himalaya`           | CLI para e-mails via IMAP/SMTP                                       |
| `healthcheck`        | Hardening de segurança para deployments OpenClaw                     |
| `openai-image-gen`   | Gere imagens em lote via API OpenAI                                  |
| `voice-call`         | Inicie chamadas de voz via plugin voice-call                         |
| `slack`              | Controle o Slack via ferramenta slack                                |
| `camsnap`            | Capture frames de câmeras RTSP/ONVIF                                 |
| `ordercli`           | CLI Foodora para pedidos                                             |
| `imsg`               | CLI iMessage/SMS                                                     |
| `openai-whisper`     | Reconhecimento de voz local                                          |
| `model-usage`        | Uso/custo por modelo via CodexBar CLI                                |
| `discord`            | Operações Discord via ferramenta de mensagens                        |
| `blucli`             | CLI BluOS para Sonos                                                 |
| `openai-whisper-api` | Transcrição via API Whisper da OpenAI                                |
| `skill-creator`      | Crie/atualize AgentSkills                                            |
| `blogwatcher`        | Monitore blogs e feeds RSS/Atom                                      |
| `openhue`            | Controle Philips Hue via CLI OpenHue                                 |
| `clawhub`            | CLI ClawHub para buscar/instalar/publicar skills                     |
| `gemini`             | CLI Gemini para Q&A e geração                                        |
| `apple-reminders`    | Lembretes da Apple via CLI remindctl                                 |
| `mcporter`           | CLI para servidores/ferramentas MCP                                  |
| `video-frames`       | Extraia frames de vídeos com ffmpeg                                  |
| `sherpa-onnx-tts`    | Síntese de voz local via sherpa-onnx                                 |
| `1password`          | CLI do 1Password                                                     |
| `apple-notes`        | Notas da Apple via CLI `memo`                                        |
| `bluebubbles`        | iMessages via BlueBubbles                                            |
| `notion`             | API Notion para páginas, databases e blocos                          |
| `gifgrep`            | Pesquise GIFs com CLI/TUI                                            |
| `session-logs`       | Pesquise logs de sessão com jq                                       |
| `weather`            | Clima via wttr.in ou Open-Meteo                                      |
| `bear-notes`         | Notas Bear via CLI grizzly                                           |
| `peekaboo`           | Capture a UI do macOS com CLI Peekaboo                               |
| `trello`             | Boards, listas e cards Trello via REST API                           |

---

### 2. Funcionalidade: auto-tradução automática ao instalar skills

#### Arquivos criados/modificados

| Arquivo                               | Tipo       | Natureza                                                                        |
| ------------------------------------- | ---------- | ------------------------------------------------------------------------------- |
| `src/agents/skills/auto-translate.ts` | Novo       | Módulo de detecção de idioma + chamada LLM + patch em disco                     |
| `src/agents/skills/refresh.ts`        | Modificado | Intercepta evento `"add"` do watcher para iniciar tradução                      |
| `src/config/types.skills.ts`          | Modificado | Novo tipo `SkillsAutoTranslateConfig` + campo `autoTranslate` em `SkillsConfig` |

#### Detalhes técnicos

**`src/agents/skills/auto-translate.ts`**

- `looksLikePtBr(text)` — heurística por densidade de acentos PT-BR e palavras-chave comuns
- `autoTranslateSkillDescription(filePath, config)` — pipeline completo:
  1. Verifica se `skills.autoTranslate.enabled` está ativo
  2. Lê o `SKILL.md` e extrai a `description` do frontmatter
  3. Chama `looksLikePtBr()` — pula se já estiver traduzido
  4. Chama o endpoint LLM compatível com OpenAI (`chat/completions`) com prompt de tradução técnica
  5. Reescreve o `description:` no arquivo usando `replaceDescriptionBlock()` (suporta inline, quoted e block-scalar YAML)
  6. Fire-and-forget — nunca lança erro, tudo é logado via `skills/auto-translate`

**`src/agents/skills/refresh.ts`**

- Evento `"add"` no watcher chokidar agora: para arquivos `SKILL.md` com `autoTranslate.enabled`, chama `autoTranslateSkillDescription` antes de executar `schedule(p)` para bumpar o snapshot de skills.

**`src/config/types.skills.ts`**

```typescript
export type SkillsAutoTranslateConfig = {
  enabled?: boolean; // default: false
  endpoint?: string; // OpenAI-compatible base URL
  apiKey?: SecretInput; // plain string ou SecretRef
  model?: string; // default: "kimi-k2-5"
  targetLocale?: string; // default: "pt-BR"
};
```

#### Configuração (via `openclaw config set` ou `openclaw.json`)

```bash
openclaw config set skills.autoTranslate.enabled true
openclaw config set skills.autoTranslate.endpoint "https://api.moonshot.cn/v1"
openclaw config set skills.autoTranslate.apiKey "sk-kimi-..."
openclaw config set skills.autoTranslate.model "kimi-k2-5"
```

Ou diretamente no `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "autoTranslate": {
      "enabled": true,
      "endpoint": "https://api.moonshot.cn/v1",
      "apiKey": "sk-kimi-...",
      "model": "kimi-k2-5"
    }
  }
}
```

#### Fluxo ao instalar uma skill com `clawhub install <nome>`

```
clawhub install <nome>
  └─ copia SKILL.md para ~/skills/<nome>/SKILL.md
       └─ chokidar detecta evento "add"
            └─ auto-translate.ts: looksLikePtBr? → NÃO
                 └─ POST endpoint/chat/completions (kimi-k2-5)
                      └─ replaceDescriptionBlock(content, translated)
                           └─ writeFileSync → SKILL.md atualizado
                                └─ schedule(p) → snapshot bumped
```

---

## [2026-03-03] Liberação de Acesso Elevated via Telegram e WhatsApp

### Problema

Pedidos via Telegram e WhatsApp eram negados com:

```
elevated is not available right now (runtime=sandboxed).
Failing gates: allowFrom (tools.elevated.allowFrom.telegram)
```

Causa raiz dupla:

1. `agents.defaults.sandbox.mode = "non-main"` — sessões não-principais (Telegram, WhatsApp) rodavam em modo sandboxed, sem acesso a ferramentas de exec/process/read/write
2. `tools.elevated.allowFrom` não configurado para Telegram/WhatsApp

### Mudanças aplicadas em `~/.openclaw/openclaw.json`

| Chave                               | Antes        | Depois                            |
| ----------------------------------- | ------------ | --------------------------------- |
| `agents.defaults.sandbox.mode`      | `"non-main"` | `"off"`                           |
| `tools.elevated.enabled`            | não definido | `true`                            |
| `tools.elevated.allowFrom.telegram` | não definido | `[756499526]`                     |
| `tools.elevated.allowFrom.whatsapp` | não definido | `["556185524929@s.whatsapp.net"]` |

### Resultado

- `runtime: sandboxed` → `runtime: direct`
- O comando `/elevated on` via Telegram agora liberado para o usuário `756499526`
- Ferramentas `exec`, `process`, `read`, `write`, `edit` disponíveis nas sessões Telegram/WhatsApp

---

## [2026-03-03] Ativação de Plugins: Memória Vetorial + Workflows + Utilitários

### Plugins Ativados

| Plugin           | ID               | Slot / Tipo                              |
| ---------------- | ---------------- | ---------------------------------------- |
| Memory (LanceDB) | `memory-lancedb` | Slot `memory` (substituiu `memory-core`) |
| LLM Task         | `llm-task`       | Ferramenta                               |
| Lobster          | `lobster`        | Workflow                                 |
| Diffs            | `diffs`          | Utilitário                               |
| OpenProse        | `open-prose`     | Comando `/prose`                         |

### Detalhes

#### `memory-lancedb` — Memória vetorial persistente

- Substitui o `memory-core` (file-backed) pelo LanceDB (vetorial + semântico)
- Dependências instaladas em `extensions/memory-lancedb/node_modules/`
- Slot de memória trocado via `plugins.slots.memory = "memory-lancedb"`
- Backend de embeddings: **Azure OpenAI** (`text-embedding-3-small`, endpoint `azrblnai.openai.azure.com`)
- `autoRecall: true` — injeta memórias relevantes automaticamente no contexto
- `autoCapture: true` — captura informações importantes das conversas
- Banco de dados em: `~/.openclaw/memory/lancedb`

#### `llm-task` — Tarefas LLM estruturadas

Ferramenta JSON para workflows que exigem chamadas LLM com saída tipada. Útil para pipelines automatizados.

#### `lobster` — Workflows com aprovação

Permite workflows pausáveis com comandos `/approve` e `/reject` para revisão humana antes de executar ações.

#### `diffs` — Viewer de diffs e imagens

Exibe diffs de código e imagens diretamente nos agentes.

#### `open-prose` — Escrita assistida

Adiciona o comando `/prose` para tarefas de escrita, revisão e formatação de texto.

### Configuração aplicada em `~/.openclaw/openclaw.json`

```json
"plugins": {
  "slots": { "memory": "memory-lancedb" },
  "entries": {
    "llm-task":       { "enabled": true },
    "lobster":        { "enabled": true },
    "diffs":          { "enabled": true },
    "open-prose":     { "enabled": true },
    "memory-lancedb": {
      "enabled": true,
      "config": {
        "embedding": {
          "apiKey": "<azure-openai-key>",
          "baseUrl": "https://azrblnai.openai.azure.com/openai/deployments/text-embedding-3-small/",
          "model": "text-embedding-3-small"
        },
        "autoRecall": true,
        "autoCapture": true
      }
    },
    "memory-core": { "enabled": false }
  }
}
```

---

## [2026-03-03] Google Antigravity Integration — v2026.3.2

Este documento descreve todas as mudanças realizadas no repositório OpenClaw para habilitar o provedor **google-antigravity** (Google One AI Premium / Google Cloud Antigravity sandbox) com autenticação OAuth, suporte ao modelo `gemini-3.1-pro-preview`, e compatibilidade do pipeline de ferramentas.

---

## Contexto

O Google disponibiliza modelos avançados (Gemini 3, Claude via gateway, GPT-OSS) através de um endpoint sandbox chamado **Antigravity** (`daily-cloudcode-pa.sandbox.googleapis.com`). O acesso é concedido via OAuth com conta Google assinante do Google One AI Premium.

O pi-ai já possuía a função `loginAntigravity` para o fluxo de login, mas o OpenClaw não tinha:

1. Um plugin de autenticação para `google-antigravity`
2. Suporte ao tipo de credencial `oauth` no resolvedor de API keys
3. O modelo `gemini-3.1-pro-preview` no catálogo de modelos implícitos
4. Reconhecimento de `google-antigravity` nos filtros de pipeline Google

---

## Arquivos Modificados

### `package.json`

**Mudança:** Atualização de dependência do pi-ai.

```diff
- "@mariozechner/pi-ai": "0.55.3",
+ "@mariozechner/pi-ai": "0.55.4",
```

**Motivo:** A versão 0.55.4 inclui correções no `loginAntigravity` e na serialização de credenciais OAuth usadas pelo novo provedor.

---

### `src/config/types.models.ts`

**Mudança:** Adicionado `"google-gemini-cli"` ao array `MODEL_APIS`.

```diff
  export const MODEL_APIS = [
    "openai-completions", "openai-responses", "openai-codex-responses",
    "anthropic-messages", "google-generative-ai",
+   "google-gemini-cli",
    "github-copilot", "bedrock-converse-stream", "ollama",
  ] as const;
```

**Motivo:** O Antigravity usa o protocolo `google-gemini-cli` como API de transporte. Sem esta entrada no array tipado, o TypeScript rejeitava a propriedade `api: "google-gemini-cli"` no `buildAntigravityCustomModelsProvider`.

---

### `src/config/validation.ts`

**Mudança:** Remoção de `google-antigravity-auth` da lista de plugins removidos/legados.

```diff
- const LEGACY_REMOVED_PLUGIN_IDS = new Set(["google-antigravity-auth"]);
+ const LEGACY_REMOVED_PLUGIN_IDS = new Set<string>([]);
```

**Motivo:** A entrada anteriormente impedia o carregamento do plugin `@openclaw/google-antigravity-auth`, gerando erro silencioso de validação. O plugin agora é oficial.

---

### `src/agents/auth-profiles/oauth.ts`

**Mudança:** `needsProjectId` passa a incluir `google-antigravity`.

```diff
  function buildOAuthApiKey(provider: string, credentials: OAuthCredentials): string {
-   const needsProjectId = provider === "google-gemini-cli";
+   const needsProjectId =
+     provider === "google-gemini-cli" || provider === "google-antigravity";
```

**Motivo:** O Antigravity requer que o `projectId` seja embutido no JSON da API key (junto com `token` e `refresh`), exatamente como o `google-gemini-cli`. Sem isso, as chamadas à API falhavam com erro de projeto não especificado.

---

### `src/agents/pi-embedded-runner/google.ts`

**Mudança:** Funções `sanitizeToolsForGoogle` e `logToolSchemasForGoogle` reconhecem `google-antigravity`.

```diff
- if (params.provider !== "google-gemini-cli") {
+ if (params.provider !== "google-gemini-cli" && params.provider !== "google-antigravity") {
```

**Motivo:** O Antigravity usa o mesmo pipeline de sanitização de tool schemas que o `google-gemini-cli`. Sem este patch, schemas com `$ref`, `additionalProperties` ou `patternProperties` eram enviados sem a devida limpeza, causando erros 400 na API.

---

### `src/agents/live-model-filter.ts`

**Mudança:** Prefixo `google-antigravity` incluído no grupo de providers Google.

```diff
- if (provider === "google" || provider === "google-gemini-cli") {
+ if (provider === "google" || provider === "google-gemini-cli" || provider === "google-antigravity") {
```

**Motivo:** O filtro de modelos "modernos" usa prefixos para identificar modelos válidos do Google. Sem esta entrada, modelos do Antigravity eram considerados outdated/incompatíveis no `isModernModelRef`.

---

### `src/agents/models-config.providers.ts`

Esta é a mudança principal — duas adições:

#### 1. Suporte OAuth em `resolveApiKeyFromProfiles`

```typescript
// For OAuth credentials, return the current access token so it can be used
// as the apiKey placeholder in models.json (satisfies pi-coding-agent
// validateConfig). Real token refresh is handled by the pi-ai AuthStorage
// OAuth mechanism independently of this value.
if (cred.type === "oauth") {
  const access = typeof cred.access === "string" ? cred.access.trim() : "";
  if (access) {
    return access;
  }
  continue;
}
```

**Motivo:** A função `resolveApiKeyFromProfiles` anteriormente só tratava credenciais do tipo `api_key` e `token`. Credenciais OAuth (como as do Antigravity) eram ignoradas silenciosamente, fazendo com que o provedor nunca aparecesse na lista de provedores implícitos.

#### 2. Função `buildAntigravityCustomModelsProvider` + injeção em `resolveImplicitProviders`

```typescript
const antigravityKey = resolveApiKeyFromProfiles({
  provider: "google-antigravity",
  store: authStore,
});
if (antigravityKey && !params.explicitProviders?.["google-antigravity"]) {
  providers["google-antigravity"] = buildAntigravityCustomModelsProvider(antigravityKey);
}
```

```typescript
const ANTIGRAVITY_BASE_URL = "https://daily-cloudcode-pa.sandbox.googleapis.com";

function buildAntigravityCustomModelsProvider(accessToken: string): ProviderConfig {
  return {
    baseUrl: ANTIGRAVITY_BASE_URL,
    api: "google-gemini-cli" as const,
    apiKey: accessToken,
    models: [
      {
        id: "gemini-3.1-pro-preview",
        name: "Gemini 3.1 Pro Preview (Antigravity)",
        reasoning: true,
        input: ["text", "image"],
        cost: { input: 2, output: 12, cacheRead: 0.2, cacheWrite: 2.375 },
        contextWindow: 1048576,
        maxTokens: 65535,
      },
    ],
  };
}
```

**Motivo:** O modelo `gemini-3.1-pro-preview` não estava no catálogo embutido do pi-ai v0.55.4 para o provedor `google-antigravity`. O Google descontinuou `gemini-3-pro-high` e `gemini-3-pro` em favor de `gemini-3.1-pro-preview`. Esta função injeta o modelo como entrada customizada só quando há OAuth válido, sem impactar usuários que não têm Antigravity configurado.

---

## Nova Extensão: `extensions/google-antigravity-auth/`

Plugin completo de autenticação OAuth para o provedor `google-antigravity`.

### `package.json`

```json
{
  "name": "@openclaw/google-antigravity-auth",
  "version": "2026.3.2",
  "private": true,
  "description": "OpenClaw Google Antigravity OAuth provider plugin",
  "type": "module",
  "openclaw": { "extensions": ["./index.ts"] }
}
```

### `openclaw.plugin.json`

```json
{
  "id": "google-antigravity-auth",
  "name": "Google Antigravity Auth",
  "description": "OAuth authentication for Google Antigravity (Gemini 3, Claude, GPT-OSS via Google One)",
  "version": "2026.3.2",
  "providers": ["google-antigravity"]
}
```

### `oauth.ts`

Importa `loginAntigravity` do `@mariozechner/pi-ai` e expõe a função de login que:

- Detecta ambiente remoto (Codespace/SSH) e inicia fluxo OAuth local com URL para colar
- Recebe redirect com código de autorização
- Salva credencial `google-antigravity:<email>` no auth store

### `index.ts`

Plugin principal que:

- Define `PROVIDER_ID = "google-antigravity"` e `DEFAULT_MODEL = "google-antigravity/gemini-3-pro-high"`
- Registra o comando `/login-antigravity` para autenticação interativa
- Usa `buildOauthProviderAuthResult` para expor o status de autenticação ao OpenClaw

---

## Estado Após as Mudanças

| Item                                 | Status                                                                     |
| ------------------------------------ | -------------------------------------------------------------------------- |
| Plugin `google-antigravity-auth`     | ✅ `loaded`                                                                |
| Credencial OAuth salva               | ✅ `google-antigravity:renanbesserra@gmail.com`                            |
| Modelos listados com `auth: yes`     | ✅ `gemini-3-flash`, `gemini-3-pro-high`, `claude-opus-4-6-thinking`, etc. |
| `gemini-3.1-pro-preview` no catálogo | ✅ (aguardando ativação do backend Google)                                 |
| Agente `general`                     | ✅ `kimi-coding/k2p5`                                                      |
| Agente `main`                        | ✅ `google-antigravity/claude-opus-4-6-thinking`                           |
| Build TypeScript                     | ✅ sem erros                                                               |

---

## Provedor Implícito: Comportamento

Com estas mudanças, quando um usuário tem `google-antigravity` no auth store:

- O resolvedor detecta automaticamente a credencial OAuth
- Injeta o provedor com `gemini-3.1-pro-preview` sem configuração manual
- O token de acesso serve como `apiKey` placeholder (refresh real é feito pelo pi-ai)
- O fluxo de ferramentas passa pela sanitização de schemas do Google

Sem credencial Antigravity configurada, **nenhuma mudança de comportamento** ocorre para outros usuários.

---

## Mudanças no Repositório — Resumo Completo

### Arquivos rastreados modificados (`git diff HEAD`)

| Arquivo                                   | Natureza da Mudança                                                                   |
| ----------------------------------------- | ------------------------------------------------------------------------------------- |
| `package.json`                            | `@mariozechner/pi-ai` bump `0.55.3` → `0.55.4`                                        |
| `pnpm-lock.yaml`                          | Gerado automaticamente pelo update do pi-ai                                           |
| `src/config/types.models.ts`              | Adicionado `"google-gemini-cli"` ao array `MODEL_APIS`                                |
| `src/config/validation.ts`                | Removido `"google-antigravity-auth"` de `LEGACY_REMOVED_PLUGIN_IDS`                   |
| `src/agents/auth-profiles/oauth.ts`       | `needsProjectId` inclui `google-antigravity`                                          |
| `src/agents/live-model-filter.ts`         | Filtro Google inclui `google-antigravity`                                             |
| `src/agents/pi-embedded-runner/google.ts` | Sanitização de tool schemas para `google-antigravity`                                 |
| `src/agents/models-config.providers.ts`   | Suporte OAuth em `resolveApiKeyFromProfiles` + `buildAntigravityCustomModelsProvider` |
| `.env.example`                            | Comentários traduzidos para PT-BR (edição incidental)                                 |
| `.vscode/extensions.json`                 | Adicionado `ms-windows-ai-studio.windows-ai-studio` às recomendações                  |

### Novos arquivos adicionados (não rastreados → commitados)

| Arquivo/Pasta                                             | Natureza                                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------- |
| `extensions/google-antigravity-auth/package.json`         | Manifest do plugin OAuth                                            |
| `extensions/google-antigravity-auth/openclaw.plugin.json` | Metadados do plugin para o OpenClaw                                 |
| `extensions/google-antigravity-auth/index.ts`             | Plugin principal (PROVIDER_ID, DEFAULT_MODEL, `/login-antigravity`) |
| `extensions/google-antigravity-auth/oauth.ts`             | Fluxo OAuth via `loginAntigravity` do pi-ai                         |
| `Dockerfile.deploy`                                       | Imagem Docker de produção com suporte ao Antigravity e kimi-coding  |
| `scripts/docker-bootstrap.sh`                             | Script de bootstrap do container (seed de config via ENV vars)      |
| `docs/reference/google-antigravity-integration.md`        | Este documento de GMUD                                              |

### Pasta `Prompts/` (91 arquivos)

Coleção de system prompts de ferramentas AI (Cursor, Claude, Cluely, Devin, etc.) adicionada ao diretório do repositório. Não faz parte do código-fonte do OpenClaw e não é rastreada pelo git.

### Imagens Docker publicadas

| Registro                                  | Tag                  |
| ----------------------------------------- | -------------------- |
| `docker.io/renanbesserra/openclaw`        | `2026.3.2`, `latest` |
| `acrtemplateopenclaw.azurecr.io/openclaw` | `2026.3.2`, `latest` |

### Infraestrutura Azure criada

| Recurso               | Tipo                             | Localização | Resource Group |
| --------------------- | -------------------------------- | ----------- | -------------- |
| `acrtemplateopenclaw` | Azure Container Registry (Basic) | `eastus`    | `rg-rbln`      |

### Backup realizado

| Arquivo                                                    | Conteúdo                                                                                     |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `~/openclaw-config-backup-20260303-014246.tar.gz` (1.3 MB) | Snapshot completo de `~/.openclaw/` incluindo agentes, credenciais, configurações e sessions |
