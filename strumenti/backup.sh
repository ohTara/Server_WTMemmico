#!/usr/bin/env bash
# backup.sh — backup dei mondi Minecraft con verifica e rotazione.
#
# Se RCON e' attivo il backup avviene A SERVER ACCESO: avvisa in chat, sospende
# il salvataggio automatico, copia e lo riattiva. Se RCON non risponde ma il
# server e' acceso, lo ferma per il tempo della copia (come faceva prima).
# L'archivio viene controllato prima di cancellare i backup vecchi; l'esito
# finisce in backups/backup.log e, se configurato, su Discord.
set -euo pipefail

MC_DIR="${MC_DIR:-$HOME/minecraft-server}"
BACKUP_DIR="$MC_DIR/backups"
BACKUP_REMOTE="${BACKUP_REMOTE:-}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
WORLD_NAME="${WORLD_NAME:-world}"
BIN="$MC_DIR/bin"

mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d-%H%M%S)
ARCHIVE="$BACKUP_DIR/${WORLD_NAME}-${DATE}.tar.gz"
LOG="$BACKUP_DIR/backup.log"

log()  { echo -e "\033[0;32m[✓]\033[0m $*"; echo "$(date '+%F %T') $*" >> "$LOG"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; echo "$(date '+%F %T') ATTENZIONE: $*" >> "$LOG"; }
rcon() { "$BIN/mc-rcon" -q "$@" 2>/dev/null; }
discord() { [[ -x "$BIN/mc-discord" ]] && "$BIN/mc-discord" "$@" || true; }

SALVATAGGIO_SOSPESO=false
SERVER_FERMATO=false

# Qualunque cosa succeda, il server torna nello stato di prima.
ripristina_server() {
  if $SALVATAGGIO_SOSPESO; then rcon save-on || true; SALVATAGGIO_SOSPESO=false; fi
  if $SERVER_FERMATO; then systemctl --user start mc-server || true; SERVER_FERMATO=false; fi
}
fallito() {
  ripristina_server
  rm -f "$ARCHIVE"
  warn "Backup FALLITO (riga $1)"
  discord ":x: Backup del server **fallito**: controlla backups/backup.log"
  exit 1
}
trap 'fallito $LINENO' ERR
trap ripristina_server EXIT

if systemctl --user is-active mc-server >/dev/null 2>&1; then
  if rcon list; then
    log "Server acceso: backup a caldo tramite RCON"
    rcon say "Backup del mondo in corso: potreste notare un attimo di lag." || true
    rcon save-off
    SALVATAGGIO_SOSPESO=true
    rcon save-all flush
    sleep "${BACKUP_ATTESA_SALVATAGGIO:-5}"      # tempo perche' i dati arrivino su disco
  else
    warn "RCON non risponde: fermo il server per il tempo del backup"
    systemctl --user stop mc-server
    SERVER_FERMATO=true
    sleep 5
  fi
fi

# Overworld, Nether, End e configurazione (solo cio' che esiste)
ITEMS=()
for item in "$WORLD_NAME" "${WORLD_NAME}_nether" "${WORLD_NAME}_the_end" \
            server.properties config whitelist.json ops.json; do
  [[ -e "$MC_DIR/$item" ]] && ITEMS+=("$item")
done
# Senza il mondo principale non e' un backup: meglio fallire che archiviare solo la configurazione.
[[ -d "$MC_DIR/$WORLD_NAME" ]] || { warn "Mondo \"$WORLD_NAME\" non trovato in $MC_DIR"; false; }

log "Creo archivio: $ARCHIVE"
# A server acceso un file puo' cambiare durante la lettura: tar lo segnala con
# codice 1, che non e' un errore; da 2 in su l'archivio non e' affidabile.
esito=0
tar -czf "$ARCHIVE" -C "$MC_DIR" "${ITEMS[@]}" || esito=$?
[[ $esito -le 1 ]]

ripristina_server

# Verifica: l'archivio si legge per intero e contiene il mondo.
gzip -t "$ARCHIVE"
CONTENUTO=$(tar -tzf "$ARCHIVE")
if [[ -e "$MC_DIR/$WORLD_NAME/level.dat" ]]; then
  grep -qx "$WORLD_NAME/level.dat" <<< "$CONTENUTO"
fi
DIMENSIONE=$(du -h "$ARCHIVE" | cut -f1)
log "Archivio verificato ($DIMENSIONE)"

if [[ -n "$BACKUP_REMOTE" ]]; then
  log "Carico su $BACKUP_REMOTE..."
  rclone copy "$ARCHIVE" "$BACKUP_REMOTE"
fi

# La rotazione parte solo dopo un backup riuscito: non resta mai senza copie.
log "Pulizia backup locali > ${KEEP_DAYS} giorni..."
find "$BACKUP_DIR" -name "${WORLD_NAME}-*.tar.gz" -mtime "+${KEEP_DAYS}" -delete
if [[ -n "$BACKUP_REMOTE" ]]; then
  log "Pulizia backup remoti > ${KEEP_DAYS} giorni..."
  rclone delete "$BACKUP_REMOTE" --min-age "${KEEP_DAYS}d" --include "${WORLD_NAME}-*.tar.gz"
fi

log "Backup completato: $ARCHIVE"
discord ":floppy_disk: Backup del server completato ($DIMENSIONE)"
