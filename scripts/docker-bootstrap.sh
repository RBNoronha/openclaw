#!/bin/bash
# docker-bootstrap.sh — Seeds OpenClaw config from ENV vars on first run,
# then starts the gateway.
#
# Environment Variables (all optional — only used when ~/.openclaw does not exist):
#   OPENCLAW_GATEWAY_TOKEN    — auth token for the gateway (required for external access)
#   KIMI_API_KEY              — Kimi Code API key (kimi-coding provider)
#   ANTHROPIC_TOKEN           — Anthropic Claude token (anthropic provider)
#   GEMINI_API_KEY            — Google Gemini API key (google provider)
#   OPENCLAW_GATEWAY_BIND     — bind mode: "loopback" (default) | "lan"
#   OPENCLAW_GATEWAY_PORT     — port (default: 18789)

set -e

CONFIG_DIR="${HOME}/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
KIMI_KEY="${KIMI_API_KEY:-}"
ANTHROPIC_TOKEN_VAL="${ANTHROPIC_TOKEN:-}"
GEMINI_KEY="${GEMINI_API_KEY:-}"

# Only seed config if it doesn't exist yet
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[bootstrap] First run detected — seeding ${CONFIG_FILE} from ENV vars..."
  mkdir -p "$CONFIG_DIR"

  # Build minimal config JSON
  # Agents, tasks and per-model settings should be configured via
  # `openclaw config set` or by mounting a full ~/.openclaw volume.
  CONFIG_JSON='{
  "version": 1,
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "'"${GATEWAY_TOKEN}"'"
    }
  },
  "agents": {
    "defaults": {
      "model": "kimi-coding/k2p5"
    }
  }
}'

  echo "$CONFIG_JSON" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "[bootstrap] Config written."

  # Seed API keys if provided
  if [ -n "$KIMI_KEY" ]; then
    echo "[bootstrap] Configuring kimi-coding provider..."
    node /app/openclaw.mjs config set providers.kimi-coding.apiKey "$KIMI_KEY" 2>/dev/null || true
  fi
  if [ -n "$ANTHROPIC_TOKEN_VAL" ]; then
    echo "[bootstrap] Configuring anthropic provider..."
    node /app/openclaw.mjs config set providers.anthropic.apiKey "$ANTHROPIC_TOKEN_VAL" 2>/dev/null || true
  fi
  if [ -n "$GEMINI_KEY" ]; then
    echo "[bootstrap] Configuring google provider..."
    node /app/openclaw.mjs config set providers.google.apiKey "$GEMINI_KEY" 2>/dev/null || true
  fi
else
  echo "[bootstrap] Existing config found — skipping seed."
fi

BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

echo "[bootstrap] Starting OpenClaw gateway on ${BIND}:${PORT}..."
exec node /app/openclaw.mjs gateway --bind "$BIND" --port "$PORT"
