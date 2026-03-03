# Relatório de Mudanças e Atualizações — OpenClaw

> Este documento é atualizado a cada mudança, melhoria ou configuração aplicada ao ambiente OpenClaw.
> Ordem: mais recente primeiro.

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
