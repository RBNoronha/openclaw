import type { SecretInput } from "./types.secrets.js";

export type SkillsAutoTranslateConfig = {
  /**
   * Enable automatic translation of skill descriptions to PT-BR when a new
   * SKILL.md is detected by the file watcher. Default: false.
   */
  enabled?: boolean;
  /**
   * OpenAI-compatible base URL (without trailing slash).
   * Example: "https://api.moonshot.cn/v1"
   */
  endpoint?: string;
  /** API key for the translation endpoint. */
  apiKey?: SecretInput;
  /** Model ID to use for translation. Default: "moonshot-v1-8k" */
  model?: string;
  /**
   * Target language for descriptions. Default: "pt-BR"
   * Change only if you need a different locale.
   */
  targetLocale?: string;
};

export type SkillConfig = {
  enabled?: boolean;
  apiKey?: SecretInput;
  env?: Record<string, string>;
  config?: Record<string, unknown>;
};

export type SkillsLoadConfig = {
  /**
   * Additional skill folders to scan (lowest precedence).
   * Each directory should contain skill subfolders with `SKILL.md`.
   */
  extraDirs?: string[];
  /** Watch skill folders for changes and refresh the skills snapshot. */
  watch?: boolean;
  /** Debounce for the skills watcher (ms). */
  watchDebounceMs?: number;
};

export type SkillsInstallConfig = {
  preferBrew?: boolean;
  nodeManager?: "npm" | "pnpm" | "yarn" | "bun";
};

export type SkillsLimitsConfig = {
  /** Max number of immediate child directories to consider under a skills root before treating it as suspicious. */
  maxCandidatesPerRoot?: number;
  /** Max number of skills to load per skills source (bundled/managed/workspace/extra). */
  maxSkillsLoadedPerSource?: number;
  /** Max number of skills to include in the model-facing skills prompt. */
  maxSkillsInPrompt?: number;
  /** Max characters for the model-facing skills prompt block (approx). */
  maxSkillsPromptChars?: number;
  /** Max size (bytes) allowed for a SKILL.md file to be considered. */
  maxSkillFileBytes?: number;
};

export type SkillsConfig = {
  /** Optional bundled-skill allowlist (only affects bundled skills). */
  allowBundled?: string[];
  load?: SkillsLoadConfig;
  install?: SkillsInstallConfig;
  limits?: SkillsLimitsConfig;
  entries?: Record<string, SkillConfig>;
  /**
   * Automatically translate skill descriptions to PT-BR when a new SKILL.md
   * is added to any watched skills directory.
   */
  autoTranslate?: SkillsAutoTranslateConfig;
};
