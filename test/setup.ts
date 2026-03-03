import fs from "node:fs";
// Fix world-writable permissions caused by container default POSIX ACLs on /tmp.
// The discovery.ts security checks reject world-writable paths, so test fixture
// directories and files need proper (0o755/0o644) permissions.
// Some container environments (e.g. Codespaces) set a default ACL on /tmp with
// "other:rw-" that overrides the process umask, giving all new dirs 0o756 and
// files 0o646 — both world-writable. We monkey-patch the core fs creation
// functions to auto-chmod after each creation. Tests that intentionally need
// world-writable paths (e.g. "blocks world-writable plugin paths") still work
// because they explicitly call fs.chmodSync(path, 0o777) afterwards.
import path from "node:path";
import { afterAll, afterEach, beforeEach, vi } from "vitest";

/** chmod all newly-created dirs from firstCreated down to leafDir (inclusive). */
function chmodNewDirs(leafDir: string, firstCreated: string | undefined): void {
  const leaf = path.resolve(leafDir);
  try {
    fs.chmodSync(leaf, 0o755);
  } catch {
    /* ignore */
  }
  if (typeof firstCreated === "string") {
    const top = path.resolve(firstCreated);
    let cur = path.dirname(leaf);
    while (cur.length >= top.length && cur !== top && cur !== path.dirname(cur)) {
      try {
        fs.chmodSync(cur, 0o755);
      } catch {
        /* ignore */
      }
      cur = path.dirname(cur);
    }
    try {
      fs.chmodSync(top, 0o755);
    } catch {
      /* ignore */
    }
  }
}

const _origMkdirSync = fs.mkdirSync.bind(fs);
(fs as Record<string, unknown>).mkdirSync = function patchedMkdirSync(
  dirPath: Parameters<typeof fs.mkdirSync>[0],
  options: Parameters<typeof fs.mkdirSync>[1],
): ReturnType<typeof fs.mkdirSync> {
  const firstCreated = _origMkdirSync(dirPath, options);
  if (typeof dirPath === "string") {
    chmodNewDirs(dirPath, firstCreated);
  }
  return firstCreated;
};

const _origWriteFileSync = fs.writeFileSync.bind(fs);
(fs as Record<string, unknown>).writeFileSync = function patchedWriteFileSync(
  filePath: Parameters<typeof fs.writeFileSync>[0],
  data: Parameters<typeof fs.writeFileSync>[1],
  options: Parameters<typeof fs.writeFileSync>[2],
): void {
  _origWriteFileSync(filePath, data, options);
  if (typeof filePath === "string") {
    try {
      fs.chmodSync(filePath, 0o644);
    } catch {
      // ignore
    }
  }
};

const _origMkdirAsync = fs.promises.mkdir.bind(fs.promises);
(fs.promises as Record<string, unknown>).mkdir = async function patchedMkdirAsync(
  dirPath: Parameters<typeof fs.promises.mkdir>[0],
  options: Parameters<typeof fs.promises.mkdir>[1],
): Promise<string | undefined> {
  const firstCreated = await _origMkdirAsync(dirPath, options);
  if (typeof dirPath === "string") {
    chmodNewDirs(dirPath, firstCreated);
  }
  return firstCreated;
};

const _origWriteFileAsync = fs.promises.writeFile.bind(fs.promises);
(fs.promises as Record<string, unknown>).writeFile = async function patchedWriteFileAsync(
  filePath: Parameters<typeof fs.promises.writeFile>[0],
  data: Parameters<typeof fs.promises.writeFile>[1],
  options: Parameters<typeof fs.promises.writeFile>[2],
): Promise<void> {
  await _origWriteFileAsync(filePath, data, options);
  if (typeof filePath === "string") {
    try {
      await fs.promises.chmod(filePath, 0o644);
    } catch {
      // ignore
    }
  }
};

// Ensure Vitest environment is properly set
process.env.VITEST = "true";
// Config validation walks plugin manifests; keep an aggressive cache in tests to avoid
// repeated filesystem discovery across suites/workers.
process.env.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS ??= "60000";
// Vitest vm forks can load transitive lockfile helpers many times per worker.
// Raise listener budget to avoid noisy MaxListeners warnings and warning-stack overhead.
const TEST_PROCESS_MAX_LISTENERS = 128;
if (process.getMaxListeners() > 0 && process.getMaxListeners() < TEST_PROCESS_MAX_LISTENERS) {
  process.setMaxListeners(TEST_PROCESS_MAX_LISTENERS);
}

import type {
  ChannelId,
  ChannelOutboundAdapter,
  ChannelPlugin,
} from "../src/channels/plugins/types.js";
import type { OpenClawConfig } from "../src/config/config.js";
import type { OutboundSendDeps } from "../src/infra/outbound/deliver.js";
import { withIsolatedTestHome } from "./test-env.js";

// Set HOME/state isolation before importing any runtime OpenClaw modules.
const testEnv = withIsolatedTestHome();
afterAll(() => testEnv.cleanup());

const [{ installProcessWarningFilter }, { setActivePluginRegistry }, { createTestRegistry }] =
  await Promise.all([
    import("../src/infra/warning-filter.js"),
    import("../src/plugins/runtime.js"),
    import("../src/test-utils/channel-plugins.js"),
  ]);

installProcessWarningFilter();

const pickSendFn = (id: ChannelId, deps?: OutboundSendDeps) => {
  switch (id) {
    case "discord":
      return deps?.sendDiscord;
    case "slack":
      return deps?.sendSlack;
    case "telegram":
      return deps?.sendTelegram;
    case "whatsapp":
      return deps?.sendWhatsApp;
    case "signal":
      return deps?.sendSignal;
    case "imessage":
      return deps?.sendIMessage;
    default:
      return undefined;
  }
};

const createStubOutbound = (
  id: ChannelId,
  deliveryMode: ChannelOutboundAdapter["deliveryMode"] = "direct",
): ChannelOutboundAdapter => ({
  deliveryMode,
  sendText: async ({ deps, to, text }) => {
    const send = pickSendFn(id, deps);
    if (send) {
      // oxlint-disable-next-line typescript/no-explicit-any
      const result = await send(to, text, { verbose: false } as any);
      return { channel: id, ...result };
    }
    return { channel: id, messageId: "test" };
  },
  sendMedia: async ({ deps, to, text, mediaUrl }) => {
    const send = pickSendFn(id, deps);
    if (send) {
      // oxlint-disable-next-line typescript/no-explicit-any
      const result = await send(to, text, { verbose: false, mediaUrl } as any);
      return { channel: id, ...result };
    }
    return { channel: id, messageId: "test" };
  },
});

const createStubPlugin = (params: {
  id: ChannelId;
  label?: string;
  aliases?: string[];
  deliveryMode?: ChannelOutboundAdapter["deliveryMode"];
  preferSessionLookupForAnnounceTarget?: boolean;
}): ChannelPlugin => ({
  id: params.id,
  meta: {
    id: params.id,
    label: params.label ?? String(params.id),
    selectionLabel: params.label ?? String(params.id),
    docsPath: `/channels/${params.id}`,
    blurb: "test stub.",
    aliases: params.aliases,
    preferSessionLookupForAnnounceTarget: params.preferSessionLookupForAnnounceTarget,
  },
  capabilities: { chatTypes: ["direct", "group"] },
  config: {
    listAccountIds: (cfg: OpenClawConfig) => {
      const channels = cfg.channels as Record<string, unknown> | undefined;
      const entry = channels?.[params.id];
      if (!entry || typeof entry !== "object") {
        return [];
      }
      const accounts = (entry as { accounts?: Record<string, unknown> }).accounts;
      const ids = accounts ? Object.keys(accounts).filter(Boolean) : [];
      return ids.length > 0 ? ids : ["default"];
    },
    resolveAccount: (cfg: OpenClawConfig, accountId?: string | null) => {
      const channels = cfg.channels as Record<string, unknown> | undefined;
      const entry = channels?.[params.id];
      if (!entry || typeof entry !== "object") {
        return {};
      }
      const accounts = (entry as { accounts?: Record<string, unknown> }).accounts;
      const match = accountId ? accounts?.[accountId] : undefined;
      return (match && typeof match === "object") || typeof match === "string" ? match : entry;
    },
    isConfigured: async (_account, cfg: OpenClawConfig) => {
      const channels = cfg.channels as Record<string, unknown> | undefined;
      return Boolean(channels?.[params.id]);
    },
  },
  outbound: createStubOutbound(params.id, params.deliveryMode),
});

const createDefaultRegistry = () =>
  createTestRegistry([
    {
      pluginId: "discord",
      plugin: createStubPlugin({ id: "discord", label: "Discord" }),
      source: "test",
    },
    {
      pluginId: "slack",
      plugin: createStubPlugin({ id: "slack", label: "Slack" }),
      source: "test",
    },
    {
      pluginId: "telegram",
      plugin: {
        ...createStubPlugin({ id: "telegram", label: "Telegram" }),
        status: {
          buildChannelSummary: async () => ({
            configured: false,
            tokenSource: process.env.TELEGRAM_BOT_TOKEN ? "env" : "none",
          }),
        },
      },
      source: "test",
    },
    {
      pluginId: "whatsapp",
      plugin: createStubPlugin({
        id: "whatsapp",
        label: "WhatsApp",
        deliveryMode: "gateway",
        preferSessionLookupForAnnounceTarget: true,
      }),
      source: "test",
    },
    {
      pluginId: "signal",
      plugin: createStubPlugin({ id: "signal", label: "Signal" }),
      source: "test",
    },
    {
      pluginId: "imessage",
      plugin: createStubPlugin({ id: "imessage", label: "iMessage", aliases: ["imsg"] }),
      source: "test",
    },
  ]);

// Creating a fresh registry before every single test was measurable overhead.
// The registry is treated as immutable by production code; tests that need a
// custom registry set it explicitly.
const DEFAULT_PLUGIN_REGISTRY = createDefaultRegistry();

beforeEach(() => {
  setActivePluginRegistry(DEFAULT_PLUGIN_REGISTRY);
});

afterEach(() => {
  // Guard against leaked fake timers across test files/workers.
  if (vi.isFakeTimers()) {
    vi.useRealTimers();
  }
});
