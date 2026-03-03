#!/usr/bin/env bash
# start-gateway.sh — inicia o OpenClaw gateway em background.
# Executado automaticamente via .devcontainer/devcontainer.json (postStartCommand)
# e pode ser chamado manualmente: bash scripts/start-gateway.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="/tmp/openclaw"
LOG_FILE="$LOG_DIR/openclaw-gateway.log"
PORT=18789

mkdir -p "$LOG_DIR"

# Se já está rodando na porta, não faz nada
if ss -ltnp 2>/dev/null | grep -q ":${PORT} "; then
  echo "[openclaw] Gateway já está rodando na porta ${PORT}."
  exit 0
fi

# Matar processos residuais
pkill -9 -f "run-node.mjs.*gateway\|openclaw-gateway\|openclaw.*gateway" 2>/dev/null || true
sleep 1

echo "[openclaw] Iniciando gateway (loopback:${PORT})..."
nohup node "$REPO_ROOT/scripts/run-node.mjs" \
  gateway run --bind loopback --port "${PORT}" --force \
  > "$LOG_FILE" 2>&1 &

GW_PID=$!
echo "[openclaw] Gateway PID=$GW_PID | log: $LOG_FILE"

# Aguardar até 15s para confirmar que subiu
for i in $(seq 1 15); do
  sleep 1
  if ss -ltnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "[openclaw] Gateway online (${i}s)."
    exit 0
  fi
done

echo "[openclaw] AVISO: Gateway não respondeu em 15s — verifique $LOG_FILE" >&2
exit 1
