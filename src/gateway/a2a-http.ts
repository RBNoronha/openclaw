import crypto from "node:crypto";
import fs from "node:fs";
import nodePath from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";
import { resolveAgentDir, resolveAgentWorkspaceDir } from "../agents/agent-scope.js";
import { runEmbeddedPiAgent } from "../agents/pi-embedded.js";
import { ensureAgentWorkspace } from "../agents/workspace.js";
import { loadConfig } from "../config/config.js";
import { resolveStateDir } from "../config/paths.js";
import { resolveSessionTranscriptPath } from "../config/sessions.js";
import type { A2AAgentCardConfig } from "../config/types.acp.js";
import { DEFAULT_AGENT_ID } from "../routing/session-key.js";
import { VERSION } from "../version.js";

export type A2ATask = {
  id: string;
  status: "pending" | "running" | "completed" | "failed";
  input: string;
  output?: string;
  createdAt: number;
  updatedAt: number;
  agentId?: string;
  sessionKey?: string;
};

type A2ARequestHandler = (
  req: IncomingMessage,
  res: ServerResponse,
) => Promise<boolean>;

// ─── Persistent task store ────────────────────────────────────────────────────
// Tasks survive gateway restarts via a JSON file in the state directory.
// Write-through: every mutation calls persistTaskStore() asynchronously.

const A2A_TASK_STORE = new Map<string, A2ATask>();
let _storeLoaded = false;

function taskStorePath(): string {
  return nodePath.join(resolveStateDir(), "a2a-tasks.json");
}

function loadTaskStore(): void {
  if (_storeLoaded) return;
  _storeLoaded = true;
  try {
    const raw = fs.readFileSync(taskStorePath(), "utf-8");
    const entries = JSON.parse(raw) as Array<[string, A2ATask]>;
    for (const [id, task] of entries) {
      // Tasks still "running" at startup were interrupted — mark as failed.
      if (task.status === "running" || task.status === "pending") {
        task.status = "failed";
        task.output = "interrupted: gateway restarted";
        task.updatedAt = Date.now();
      }
      A2A_TASK_STORE.set(id, task);
    }
  } catch {
    // File missing or corrupt — start fresh.
  }
}

function persistTaskStore(): void {
  try {
    const entries = Array.from(A2A_TASK_STORE.entries());
    // Keep only the 500 most-recent tasks to cap file size.
    const trimmed = entries.length > 500 ? entries.slice(entries.length - 500) : entries;
    fs.writeFileSync(taskStorePath(), JSON.stringify(trimmed), "utf-8");
  } catch {
    // Non-fatal: worst case tasks are lost on restart.
  }
}

function sendJson(res: ServerResponse, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function readJsonBody(req: IncomingMessage): Promise<{ ok: true; value: unknown } | { ok: false; error: string }> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    let size = 0;
    const MAX = 1_048_576; // 1 MB
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > MAX) {
        resolve({ ok: false, error: "payload too large" });
      } else {
        chunks.push(chunk);
      }
    });
    req.on("end", () => {
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString("utf-8")) as unknown;
        resolve({ ok: true, value: body });
      } catch {
        resolve({ ok: false, error: "invalid JSON" });
      }
    });
    req.on("error", () => resolve({ ok: false, error: "request error" }));
  });
}

function buildAgentCard(card: A2AAgentCardConfig, fallbackEndpoint: string): Record<string, unknown> {
  return {
    id: card.id ?? "openclaw-agent",
    name: card.name ?? "OpenClaw Agent",
    description: card.description ?? "OpenClaw multi-channel AI gateway agent",
    version: VERSION,
    endpoint: card.endpoint ?? fallbackEndpoint,
    skills: card.skills ?? [],
    auth: card.auth ?? { type: "none" },
  };
}

function resolveRequestEndpoint(req: IncomingMessage): string {
  const proto = String(req.headers["x-forwarded-proto"] ?? "https");
  const host = String(req.headers.host ?? "localhost");
  return `${proto}://${host}/a2a`;
}

/** Returns true if this request was handled by the A2A HTTP handler. */
export function createA2ARequestHandler(): A2ARequestHandler {
  return async (req, res) => {
    const cfg = loadConfig();
    const a2aEnabled = cfg.a2a?.enabled === true || process.env.OPENCLAW_A2A_ENABLED === "true";
    if (!a2aEnabled) {
      return false;
    }
    loadTaskStore();

    const url = new URL(req.url ?? "/", "http://localhost");
    const path = url.pathname;
    const method = (req.method ?? "GET").toUpperCase();

    // GET /.well-known/agent.json — Agent Card discovery
    if (path === "/.well-known/agent.json") {
      if (method !== "GET" && method !== "HEAD") {
        res.statusCode = 405;
        res.setHeader("Allow", "GET, HEAD");
        res.end("Method Not Allowed");
        return true;
      }
      const card = buildAgentCard(
        cfg.a2a?.agentCard ?? {},
        resolveRequestEndpoint(req),
      );
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=60");
      if (method === "HEAD") {
        res.end();
        return true;
      }
      res.end(JSON.stringify(card, null, 2));
      return true;
    }

    // POST /a2a — Receive a delegated A2A task
    if (path === "/a2a") {
      if (method !== "POST") {
        res.statusCode = 405;
        res.setHeader("Allow", "POST");
        res.end("Method Not Allowed");
        return true;
      }
      const body = await readJsonBody(req);
      if (!body.ok) {
        sendJson(res, 400, { ok: false, error: body.error });
        return true;
      }
      const payload = typeof body.value === "object" && body.value !== null
        ? (body.value as Record<string, unknown>)
        : {};
      const input = typeof payload.input === "string" ? payload.input.trim() : "";
      if (!input) {
        sendJson(res, 400, { ok: false, error: "input is required" });
        return true;
      }
      const taskId = crypto.randomUUID();
      const now = Date.now();
      const task: A2ATask = {
        id: taskId,
        status: "pending",
        input,
        createdAt: now,
        updatedAt: now,
        agentId: typeof payload.agentId === "string" ? payload.agentId : undefined,
        sessionKey: typeof payload.sessionKey === "string" ? payload.sessionKey : undefined,
      };
      A2A_TASK_STORE.set(taskId, task);
      task.status = "running";
      task.updatedAt = Date.now();
      persistTaskStore();
      sendJson(res, 202, {
        ok: true,
        taskId,
        status: task.status,
        message: "Task accepted. Poll /a2a/tasks/" + taskId + " for status.",
      });
      // Dispatch asynchronously after response is sent
      setImmediate(() => {
        dispatchA2ATask(task).catch((err: unknown) => {
          completeA2ATask(task.id, {
            output: `Error: ${String(err)}`,
            status: "failed",
          });
        });
      });
      return true;
    }

    // GET /a2a/tasks/:id — Task status
    const taskMatch = /^\/a2a\/tasks\/([^/]+)$/.exec(path);
    if (taskMatch) {
      if (method !== "GET" && method !== "HEAD") {
        res.statusCode = 405;
        res.setHeader("Allow", "GET, HEAD");
        res.end("Method Not Allowed");
        return true;
      }
      const taskId = taskMatch[1];
      const task = A2A_TASK_STORE.get(taskId ?? "");
      if (!task) {
        sendJson(res, 404, { ok: false, error: "task not found" });
        return true;
      }
      if (method === "HEAD") {
        res.statusCode = 200;
        res.end();
        return true;
      }
      sendJson(res, 200, {
        ok: true,
        task: {
          id: task.id,
          status: task.status,
          output: task.output,
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
        },
      });
      return true;
    }

    return false;
  };
}

/** Executes an A2A task by dispatching to the embedded Pi agent runner. */
async function dispatchA2ATask(task: A2ATask): Promise<void> {
  const cfg = loadConfig();
  const agentId = task.agentId ?? DEFAULT_AGENT_ID;
  const workspaceDirRaw = resolveAgentWorkspaceDir(cfg, agentId);
  const agentDir = resolveAgentDir(cfg, agentId);
  const workspace = await ensureAgentWorkspace({ dir: workspaceDirRaw });
  const workspaceDir = workspace.dir;
  const sessionId = crypto.randomUUID();
  const sessionFile = resolveSessionTranscriptPath(sessionId, agentId);
  const runId = crypto.randomUUID();

  const textParts: string[] = [];
  const result = await runEmbeddedPiAgent({
    sessionId,
    sessionFile,
    workspaceDir,
    agentDir,
    agentId,
    sessionKey: task.sessionKey,
    config: cfg,
    prompt: task.input,
    timeoutMs: 5 * 60_000,
    runId,
    onPartialReply: (payload) => {
      if (payload.text) {
        textParts.push(payload.text);
      }
    },
  });

  // Prefer aggregated streaming text; fall back to result payloads
  let output = textParts.join("");
  if (!output && result.payloads?.length) {
    output = result.payloads
      .filter((p) => p.text && !p.isError)
      .map((p) => p.text ?? "")
      .join("\n")
      .trim();
  }
  if (!output) {
    output = "(no output)";
  }

  completeA2ATask(task.id, { output, status: "completed" });
}

/** Updates an A2A task with output and marks it completed/failed. */
export function completeA2ATask(
  taskId: string,
  result: { output: string; status: "completed" | "failed" },
): void {
  const task = A2A_TASK_STORE.get(taskId);
  if (!task) {
    return;
  }
  task.output = result.output;
  task.status = result.status;
  task.updatedAt = Date.now();
  persistTaskStore();
}
