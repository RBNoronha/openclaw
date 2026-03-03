# Backups de Configuração OpenClaw

Este diretório armazena backups locais do diretório `~/.openclaw`.

## Formato de arquivo

- `openclaw-config-backup-YYYYMMDD_HHMMSS.tar.gz` — backup comprimido completo
- `openclaw.json.snapshot-YYYYMMDD_HHMMSS.json` — snapshot legível do config principal

> **Atenção:** os arquivos `.tar.gz` e `.snapshot-*.json` são ignorados pelo git (contêm credenciais).  
> Apenas este README e o `.gitignore` são versionados.

## Como restaurar

```bash
# 1. Parar o gateway
pkill -f openclaw-gateway

# 2. Extrair backup
tar -xzf docs/reference/backups/openclaw-config-backup-YYYYMMDD_HHMMSS.tar.gz \
  -C /workspaces/.openclaw/

# 3. Reiniciar gateway
nohup openclaw gateway run --bind loopback --port 18789 > /tmp/openclaw-gateway.log 2>&1 &
```

## Histórico

| Data       | Arquivo                                         | Conteúdo                                                                                                       |
| ---------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 2026-03-03 | `openclaw-config-backup-20260303_103214.tar.gz` | Backup completo v2026.3.2 — 1073 entradas (agents, credentials, identity, workspaces, cron, devices, telegram) |
