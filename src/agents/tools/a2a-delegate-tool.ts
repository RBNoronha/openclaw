import https from "node:https";
import http from "node:http";
import { Type } from "@sinclair/typebox";
import type { OpenClawConfig } from "../../config/config.js";
import type { A2APeerConfig } from "../../config/types.acp.js";
import { createSubsystemLogger } from "../../logging/subsystem.js";
import type { AnyAgentTool } from "./common.js";
import { jsonResult } from "./common.js";

const log = createSubsystemLogger("agents/a2a-delegate");

const DEFAULT_TIMEOUT_MS = 5 * 60_000;
const POLL_INTERVAL_MS = 2_000;

const A2ADelegateToolSchema = Type.Object({
  agentId: Type.String({ minLength: 1, maxLength: 64 }),
  message: Type.String({ minLength: 1 }),
  timeoutSeconds: Type.Optional(Type.Number({ minimum: 5, maximum: 600 })),
});

/** Resolve peer config from config or OPENCLAW_A2A_PEER_<ID> env var. */
function resolvePeer(cfg: OpenClawConfig, agentId: string): A2APeerConfig | undefined {
  const id = agentId.trim().toLowerCase();
  const fromConfig = cfg.a2a?.peers?.find((p) => p.id.toLowerCase() === id);
  if (fromConfig) return fromConfig;
  // Fallback: OPENCLAW_A2A_PEER_<UPPERCASE_ID>=https://...
  const envKey = `OPENCLAW_A2A_PEER_${id.toUpperCase().replace(/-/g, "_")}`;
  const endpoint = process.env[envKey]?.trim();
  if (endpoint) {
    return { id, endpoint };
  }
  return undefined;
}

function httpRequest(
  url: string,
  options: { method: string; headers: Record<string, string>; body?: string; timeoutMs: number },
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const lib = parsed.protocol === "https:" ? https : http;
    const req = lib.request(
      {
        hostname: parsed.hostname,
        port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
        path: parsed.pathname + parsed.search,
        method: options.method,
        headers: options.headers,
      },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (c: Buffer) => chunks.push(c));
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            body: Buffer.concat(chunks).toString("utf-8"),
          });
        });
      },
    );
    req.setTimeout(options.timeoutMs, () => {
      req.destroy(new Error("request timeout"));
    });
    req.on("error", reject);
    if (options.body) {
      req.write(options.body);
    }
    req.end();
  });
}

async function submitTask(
  peer: A2APeerConfig,
  input: string,
  timeoutMs: number,
): Promise<string> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (peer.token) {
    headers["Authorization"] = `Bearer ${peer.token}`;
  }

  // POST /a2a
  const postUrl = peer.endpoint.replace(/\/$/, "") + "/a2a";
  const body = JSON.stringify({ input });
  const postRes = await httpRequest(postUrl, {
    method: "POST",
    headers,
    body,
    timeoutMs: 15_000,
  });

  if (postRes.status !== 202) {
    throw new Error(`POST /a2a returned ${postRes.status}: ${postRes.body.slice(0, 200)}`);
  }

  let parsed: { taskId?: string };
  try {
    parsed = JSON.parse(postRes.body) as { taskId?: string };
  } catch {
    throw new Error(`POST /a2a response is not JSON: ${postRes.body.slice(0, 200)}`);
  }

  const taskId = typeof parsed.taskId === "string" ? parsed.taskId : "";
  if (!taskId) {
    throw new Error(`POST /a2a did not return a taskId: ${postRes.body.slice(0, 200)}`);
  }

  // Poll GET /a2a/tasks/:id
  const pollUrl = peer.endpoint.replace(/\/$/, "") + "/a2a/tasks/" + taskId;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
    const pollRes = await httpRequest(pollUrl, {
      method: "GET",
      headers,
      timeoutMs: 10_000,
    });
    if (pollRes.status !== 200) {
      log.warn("poll /a2a/tasks returned non-200", { taskId, status: pollRes.status });
      continue;
    }
    let pollParsed: { task?: { status?: string; output?: string } };
    try {
      pollParsed = JSON.parse(pollRes.body) as typeof pollParsed;
    } catch {
      continue;
    }
    const status = pollParsed.task?.status;
    if (status === "completed" || status === "failed") {
      return pollParsed.task?.output ?? "(no output)";
    }
  }

  throw new Error(`A2A task ${taskId} timed out after ${Math.round(timeoutMs / 1000)}s`);
}

export function createA2ADelegateTool(opts?: { config?: OpenClawConfig }): AnyAgentTool {
  return {
    label: "A2A Delegate",
    name: "a2a_delegate",
    description:
      "Delegates a task to a peer agent via the A2A HTTP protocol. " +
      "Use agentId to identify the peer (must be listed in a2a.peers config or " +
      "OPENCLAW_A2A_PEER_<ID> env var). Returns the peer agent's output when done.",
    parameters: A2ADelegateToolSchema,
    execute: async (_toolCallId, args) => {
      const params = args as Record<string, unknown>;
      const agentId = typeof params.agentId === "string" ? params.agentId.trim() : "";
      const message = typeof params.message === "string" ? params.message.trim() : "";
      const timeoutMs =
        typeof params.timeoutSeconds === "number"
          ? params.timeoutSeconds * 1000
          : DEFAULT_TIMEOUT_MS;

      if (!agentId) {
        return jsonResult({ status: "error", error: "agentId is required" });
      }
      if (!message) {
        return jsonResult({ status: "error", error: "message is required" });
      }

      const cfg = opts?.config;
      if (!cfg) {
        return jsonResult({ status: "error", error: "no config available" });
      }

      const peer = resolvePeer(cfg, agentId);
      if (!peer) {
        return jsonResult({
          status: "error",
          error:
            `No A2A peer found for agentId="${agentId}". ` +
            `Add it to a2a.peers in config or set OPENCLAW_A2A_PEER_${agentId.toUpperCase()}.`,
        });
      }

      log.info("delegating task via A2A", { agentId, endpoint: peer.endpoint });
      try {
        const output = await submitTask(peer, message, timeoutMs);
        return jsonResult({ status: "ok", agentId, output });
      } catch (err) {
        const error = err instanceof Error ? err.message : String(err);
        log.warn("A2A delegate failed", { agentId, error });
        return jsonResult({ status: "error", agentId, error });
      }
    },
  };
}
