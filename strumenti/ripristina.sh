#!/usr/bin/env bash
# ripristina.sh — riporta i mondi allo stato di un backup.
#
# Uso:  ripristina.sh                 elenca i backup e chiede quale usare
#       ripristina.sh ARCHIVIO.tar.gz ripristina quello indicato
#
# I mondi attuali NON vengono cancellati: sono spostati in
# backups/prima-del-ripristino-<data>/, da cui si possono rimettere a mano.
# server.properties e config non vengono toccati (restano nell'archivio).
set -euo pipefail

MC_DIR="${MC_DIR:-$HOME/minecraft-server}"
BACKUP_DIR="$MC_DIR/backups"
WORLD_NAME="${WORLD_NAME:-world}"
BIN="$MC_DIR/bin"

log()   { echo -e "\033[0;32m[✓]\033[0m $*"; }
errore() { echo -e "\033[0;31m[✗]\033[0m $*" >&2; exit 1; }

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" ]]; then
  mapfile -t ELENCO < <(find "$BACKUP_DIR" -maxdepth 1 -name "${WORLD_NAME}-*.tar.gz" | sort -r)
  [[ ${#ELENCO[@]} -gt 0 ]] || errore "Nessun backup in $BACKUP_DIR"
  echo "Backup disponibili (dal piu' recente):"
  for i in "${!ELENCO[@]}"; do
    printf "  %2d) %s  (%s)\n" "$((i + 1))" "$(basename "${ELENCO[$i]}")" "$(du -h "${ELENCO[$i]}" | cut -f1)"
  done
  read -r -p "Numero del backup da ripristinare (Invio per annullare): " scelta
  [[ "$scelta" =~ ^[0-9]+$ && "$scelta" -ge 1 && "$scelta" -le ${#ELENCO[@]} ]] || errore "Annullato"
  ARCHIVE="${ELENCO[$((scelta - 1))]}"
fi
[[ -f "$ARCHIVE" ]] || ARCHIVE="$BACKUP_DIR/$ARCHIVE"
[[ -f "$ARCHIVE" ]] || errore "Archivio non trovato: $ARCHIVE"

gzip -t "$ARCHIVE" || errore "Archivio danneggiato: $ARCHIVE"
CONTENUTO=$(tar -tzf "$ARCHIVE")      # elencato una volta sola: con pipefail "tar | grep -q" fallirebbe
grep -qx "$WORLD_NAME/level.dat" <<< "$CONTENUTO" \
  || errore "L'archivio non contiene il mondo \"$WORLD_NAME\""

echo
echo "Sto per riportare i mondi allo stato di: $(basename "$ARCHIVE")"
echo "Tutto cio' che e' stato costruito dopo quel backup andra' perso nel mondo attivo."
if [[ "${RIPRISTINA_SENZA_CONFERMA:-}" != "si" ]]; then
  read -r -p "Scrivi RIPRISTINA per confermare: " conferma
  [[ "$conferma" == "RIPRISTINA" ]] || errore "Annullato"
fi

ERA_ACCESO=false
if systemctl --user is-active mc-server >/dev/null 2>&1; then
  ERA_ACCESO=true
  "$BIN/mc-rcon" -q say "Il server si ferma per ripristinare un backup." 2>/dev/null || true
  log "Fermo il server..."
  systemctl --user stop mc-server
  sleep 5
fi

SALVATI="$BACKUP_DIR/prima-del-ripristino-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SALVATI"
for mondo in "$WORLD_NAME" "${WORLD_NAME}_nether" "${WORLD_NAME}_the_end"; do
  [[ -e "$MC_DIR/$mondo" ]] && mv "$MC_DIR/$mondo" "$SALVATI/"
done
log "Mondi attuali spostati in $SALVATI"

# Estrae solo i mondi presenti nell'archivio.
MONDI=()
for mondo in "$WORLD_NAME" "${WORLD_NAME}_nether" "${WORLD_NAME}_the_end"; do
  grep -q "^$mondo/" <<< "$CONTENUTO" && MONDI+=("$mondo")
done
tar -xzf "$ARCHIVE" -C "$MC_DIR" "${MONDI[@]}"
log "Ripristinati: ${MONDI[*]}"

if $ERA_ACCESO; then
  log "Riavvio il server..."
  systemctl --user start mc-server
fi
[[ -x "$BIN/mc-discord" ]] && "$BIN/mc-discord" ":rewind: Mondo ripristinato dal backup $(basename "$ARCHIVE")"
log "Fatto. Se serve tornare indietro, i mondi di prima sono in $SALVATI"
