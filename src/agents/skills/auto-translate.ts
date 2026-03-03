/**
 * Automatic PT-BR translation of SKILL.md description fields.
 *
 * When skills are installed via clawhub or added to any watched skills
 * directory, this module detects non-PT-BR descriptions and rewrites them
 * in-place using an OpenAI-compatible chat/completions endpoint.
 *
 * Configuration (in openclaw.json under `skills.autoTranslate`):
 *   enabled      – boolean, default false
 *   endpoint     – OpenAI-compatible base URL
 *   apiKey       – API key (plain string or SecretRef)
 *   model        – model ID, default "kimi-k2-5"
 *   targetLocale – default "pt-BR"
 */

import fs from "node:fs";
import type { OpenClawConfig } from "../../config/config.js";
import { createSubsystemLogger } from "../../logging/subsystem.js";

const log = createSubsystemLogger("skills/auto-translate");

// ──────────────────────────────────────────────────────────────────
// Language detection heuristic
// ──────────────────────────────────────────────────────────────────

/**
 * Characters and digraphs that appear frequently in PT-BR but rarely in
 * English or other Latin languages (ç is also French but combined weight
 * still works well as a heuristic).
 */
const PT_BR_MARKERS = /[ãâçêõáéíóúàèìòùäëïö]/gi;

/**
 * Common PT-BR words that strongly indicate the text is already translated.
 * Checked case-insensitively.
 */
const PT_BR_KEYWORDS =
  /\b(quando|não|gerencie|controle|use\s+quando|extraia|pesquise|envie|inicie|configure|monitore|gere|capture|crie|delegue|obtenha|transcreva|reproduza|busque|ative|liste|exporte|faça|instale|gerenci|adicione|visualize|baixe|execute)\b/i;

/**
 * Returns true if the text is already in PT-BR (or close enough that we
 * should not overwrite it).
 */
export function looksLikePtBr(text: string): boolean {
  if (!text || text.trim().length === 0) return true;

  // Keyword match is a strong signal
  if (PT_BR_KEYWORDS.test(text)) return true;

  // Accent-density check: if > 2% of characters are PT-accented, treat as PT
  const matches = text.match(PT_BR_MARKERS);
  const accentCount = matches?.length ?? 0;
  const ratio = accentCount / text.length;
  if (ratio > 0.02) return true;

  return false;
}

// ──────────────────────────────────────────────────────────────────
// In-file description patcher
// ──────────────────────────────────────────────────────────────────

/**
 * Rewrites only the `description:` line(s) in a SKILL.md frontmatter block.
 * Handles inline (`description: text`), single-quoted, double-quoted, and
 * multi-line block-scalar forms.
 */
export function patchDescriptionInContent(content: string, newDescription: string): string {
  // Normalise: escape any single-quotes in the translation so we can always
  // emit a single-quoted YAML scalar.
  const escaped = newDescription.replace(/'/g, "''");
  const replacement = `description: '${escaped}'`;

  // Match description including possible multi-line block-scalar values
  // (lines indented after `description: |` or `description: >`).
  const descPattern =
    /^(description:\s*)(['"])(.*)\2\s*$|^(description:\s*[|>][+-]?\s*\n(?:[ \t]+[^\n]*\n?)*)|^(description:\s*)(.+)$/m;

  if (descPattern.test(content)) {
    // Replace the entire description entry (including multi-line body)
    return (
      content
        .replace(/^description:[ \t]*(['"])([\s\S]*?)\1[ \t]*$/m, replacement)
        // Single-quoted multi-char form not matched above → try plain inline
        .replace(/^(description:[ \t]*)(.+)$/m, replacement)
    );
  }

  return content;
}

/**
 * More robust replace: first try to match known forms, then fall back to a
 * simple line-by-line approach that handles `description: |` block scalars.
 */
function replaceDescriptionBlock(original: string, newDescription: string): string {
  const escaped = newDescription.replace(/'/g, "''");
  const newLine = `description: '${escaped}'`;

  const lines = original.split("\n");
  let inFrontmatter = false;
  let frontmatterStart = false;
  let inDescription = false;
  const result: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Detect frontmatter boundaries
    if (i === 0 && line.trim() === "---") {
      inFrontmatter = true;
      frontmatterStart = true;
      result.push(line);
      continue;
    }
    if (inFrontmatter && line.trim() === "---") {
      inFrontmatter = false;
      result.push(line);
      continue;
    }

    if (inFrontmatter) {
      // If we were collecting a multi-line description, skip continuation lines
      if (inDescription) {
        if (line.startsWith(" ") || line.startsWith("\t")) {
          // continuation of block scalar – skip
          continue;
        } else {
          // End of block scalar
          inDescription = false;
        }
      }

      // Check if this line starts the description field
      const inlineMatch = line.match(/^(description:\s*)(['"])(.*)\2\s*$/);
      const inlinePlain = line.match(/^description:[ \t]+(.+)$/);
      const blockScalar = line.match(/^description:[ \t]*[|>][+-]?\d*[ \t]*$/);

      if (inlineMatch || inlinePlain) {
        result.push(newLine);
        continue;
      }
      if (blockScalar) {
        result.push(newLine);
        inDescription = true;
        continue;
      }
    }

    result.push(line);

    // Reset frontmatterStart after first line
    if (frontmatterStart && i > 0) {
      frontmatterStart = false;
    }
  }

  return result.join("\n");
}

// ──────────────────────────────────────────────────────────────────
// LLM translation call
// ──────────────────────────────────────────────────────────────────

type TranslateOptions = {
  endpoint: string;
  apiKey: string;
  model: string;
  targetLocale: string;
  timeoutMs?: number;
};

async function callTranslationApi(
  description: string,
  opts: TranslateOptions,
): Promise<string | null> {
  const { endpoint, apiKey, model, targetLocale, timeoutMs = 15_000 } = opts;
  const url = `${endpoint.replace(/\/$/, "")}/chat/completions`;

  const prompt =
    `You are a concise technical translator. Translate the following skill description to ${targetLocale}. ` +
    `Keep technical terms (CLI names, tool names, API names, file paths) in their original form. ` +
    `Return ONLY the translated text, no quotes, no explanation.\n\n` +
    `Description: ${description}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        stream: false,
        max_tokens: 512,
        temperature: 0.1,
        messages: [{ role: "user", content: prompt }],
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      log.warn(
        `Translation API returned ${res.status} for description "${description.slice(0, 60)}…"`,
      );
      return null;
    }

    const json = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const translated = json?.choices?.[0]?.message?.content?.trim();
    return translated || null;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log.warn(`Translation API call failed: ${msg}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ──────────────────────────────────────────────────────────────────
// Resolving SecretInput to a plain string
// ──────────────────────────────────────────────────────────────────

function resolveSecretInputSync(secret: unknown): string | undefined {
  if (typeof secret === "string") return secret;
  // SecretRef objects (env var refs, etc.) cannot be resolved synchronously
  // without full secret resolution. Fall back to undefined so the feature
  // is simply skipped rather than crashing.
  return undefined;
}

// ──────────────────────────────────────────────────────────────────
// Public API
// ──────────────────────────────────────────────────────────────────

export type AutoTranslateResult =
  | { translated: false; reason: string }
  | { translated: true; original: string; result: string };

/**
 * Reads `skillFilePath`, checks if the `description` field is already in
 * PT-BR (or the configured `targetLocale`), and if not, translates it and
 * writes the updated content back to disk.
 *
 * Safe to call on any SKILL.md – it is a no-op when:
 *   - `skills.autoTranslate.enabled` is falsy
 *   - the description is already in the target locale
 *   - the endpoint / API key is not configured
 *   - any I/O or API error occurs (errors are logged, not thrown)
 */
export async function autoTranslateSkillDescription(
  skillFilePath: string,
  config?: OpenClawConfig,
): Promise<AutoTranslateResult> {
  const autoTranslateCfg = config?.skills?.autoTranslate;

  if (!autoTranslateCfg?.enabled) {
    return { translated: false, reason: "autoTranslate not enabled" };
  }

  const endpoint = autoTranslateCfg.endpoint?.trim();
  if (!endpoint) {
    return { translated: false, reason: "autoTranslate.endpoint not configured" };
  }

  const apiKey = resolveSecretInputSync(autoTranslateCfg.apiKey);
  if (!apiKey) {
    return { translated: false, reason: "autoTranslate.apiKey not configured or is a SecretRef" };
  }

  const model = autoTranslateCfg.model?.trim() || "kimi-k2-5";
  const targetLocale = autoTranslateCfg.targetLocale?.trim() || "pt-BR";

  // Read the file
  let content: string;
  try {
    content = fs.readFileSync(skillFilePath, "utf-8");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return { translated: false, reason: `Could not read file: ${msg}` };
  }

  // Extract existing description from frontmatter (simple line scan)
  const descMatch = content.match(/^description:[ \t]*(['"]?)([\s\S]*?)\1[ \t]*$/m);
  const descPlain = content.match(/^description:[ \t]+(.+)$/m);
  const rawDescription = (descMatch?.[2] ?? descPlain?.[1] ?? "").trim();

  if (!rawDescription) {
    return { translated: false, reason: "No description found in frontmatter" };
  }

  if (looksLikePtBr(rawDescription)) {
    return { translated: false, reason: "Description is already in PT-BR" };
  }

  log.info(`Auto-translating skill description for: ${skillFilePath}`);

  const translated = await callTranslationApi(rawDescription, {
    endpoint,
    apiKey,
    model,
    targetLocale,
  });

  if (!translated) {
    return { translated: false, reason: "Translation API returned empty result" };
  }

  // Patch the file in-place
  const patched = replaceDescriptionBlock(content, translated);
  if (patched === content) {
    log.warn(`Could not patch description in ${skillFilePath} – content unchanged`);
    return { translated: false, reason: "File patch had no effect" };
  }

  try {
    fs.writeFileSync(skillFilePath, patched, "utf-8");
    log.info(`Translated description written to ${skillFilePath}`);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return { translated: false, reason: `Could not write file: ${msg}` };
  }

  return { translated: true, original: rawDescription, result: translated };
}
