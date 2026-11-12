#!/usr/bin/env bash
# backup.sh — Backup mondo Minecraft con rotazione
set -euo pipefail

MC_DIR="${MC_DIR:-$HOME/minecraft-server}"
BACKUP_DIR="$MC_DIR/backups"
BACKUP_REMOTE="${BACKUP_REMOTE:-}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"

mkdir -p "$BACKUP_DIR"

DATE=$(date +%Y%m%d-%H%M%S)
WORLD_NAME="${WORLD_NAME:-world}"
ARCHIVE="$BACKUP_DIR/${WORLD_NAME}-${DATE}.tar.gz"

log() { echo -e "\033[0;32m[✓]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# Ferma server se in esecuzione (opzionale, per consistency)
WAS_RUNNING=false
if systemctl --user is-active mc-server >/dev/null 2>&1; then
  WAS_RUNNING=true
  log "Server in esecuzione, fermo per backup..."
  systemctl --user stop mc-server
  sleep 5
fi

log "Creo archivio: $ARCHIVE"
tar -czf "$ARCHIVE" -C "$MC_DIR" "$WORLD_NAME"

# Riavvia se era running
if [[ "$WAS_RUNNING" == "true" ]]; then
  log "Riavvio server..."
  systemctl --user start mc-server
fi

# Upload remoto se configurato
if [[ -n "$BACKUP_REMOTE" ]]; then
  log "Carico su $BACKUP_REMOTE..."
  rclone copy "$ARCHIVE" "$BACKUP_REMOTE" --progress
fi

# Rotazione locale
log "Pulizia backup locali > ${KEEP_DAYS} giorni..."
find "$BACKUP_DIR" -name "${WORLD_NAME}-*.tar.gz" -mtime +${KEEP_DAYS} -delete

# Rotazione remoto
if [[ -n "$BACKUP_REMOTE" ]]; then
  log "Pulizia backup remoti > ${KEEP_DAYS} giorni..."
  rclone delete "$BACKUP_REMOTE" --min-age ${KEEP_DAYS}d --include "${WORLD_NAME}-*.tar.gz"
fi

log "Backup completato: $ARCHIVE"
