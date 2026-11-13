#!/usr/bin/env bash
# install-mc-server.sh — Minecraft PaperMC + Geyser (Java/Bedrock cross-play)
# Uso: chmod +x install-mc-server.sh && ./install-mc-server.sh
# Opzionale: BACKUP_REMOTE="gdrive:mc-backups" ./install-mc-server.sh  # per backup cloud

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Configurazione
MC_DIR="$HOME/minecraft-server"
MC_RAM="6G"                    # RAM allocata (max 8G per 30 giocatori)
MC_VERSION="latest"            # "latest" o versione es. "1.21.1"
BACKUP_REMOTE="${BACKUP_REMOTE:-}"  # rclone remote, es. "gdrive:mc-backups" o "s3:bucket/path"
BACKUP_KEEP_DAYS=14
TAILSCALE_ENABLED=true

# Colori
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# Prerequisiti
log "Verifica prerequisiti..."
command -v java >/dev/null 2>&1 || { warn "Java mancante, installo..."; sudo apt update && sudo apt install -y openjdk-21-jre-headless; }
command -v curl >/dev/null 2>&1 || sudo apt install -y curl
command -v jq >/dev/null 2>&1 || sudo apt install -y jq
command -v rclone >/dev/null 2>&1 || { warn "rclone mancante, installo..."; curl https://rclone.org/install.sh | sudo bash; }

# ──────────────────────────────────────────────────────────────────────────────
# Directory
log "Creo directory $MC_DIR..."
mkdir -p "$MC_DIR"/{plugins,world,backups,config}
cd "$MC_DIR"

# ──────────────────────────────────────────────────────────────────────────────
# Scarica PaperMC (latest build per latest version) — usa fill.papermc.io/v3
log "Scarico PaperMC..."
if [[ "$MC_VERSION" == "latest" ]]; then
  # Trova l'ultima versione MC stabile (es. 1.21.11, no rc/pre)
  MC_VERSION=$(curl -s "https://fill.papermc.io/v3/projects/paper" -H "Accept: application/json" \
    | jq -r '.versions["1.21"][] | select(test("^1\\.21\\.[0-9]+$")) | select(test("rc|pre") | not)' | head -1)
  # Per quella versione, trova l'ultimo build
  BUILD=$(curl -s "https://fill.papermc.io/v3/projects/paper/versions/$MC_VERSION" -H "Accept: application/json" | jq -r '.builds[-1]')
else
  BUILD=$(curl -s "https://fill.papermc.io/v3/projects/paper/versions/$MC_VERSION" -H "Accept: application/json" | jq -r '.builds[-1]')
fi

# Ottieni URL di download dal build info
JAR_NAME="paper-${MC_VERSION}-${BUILD}.jar"
DOWNLOAD_INFO=$(curl -s "https://fill.papermc.io/v3/projects/paper/versions/$MC_VERSION/builds/$BUILD" -H "Accept: application/json")
JAR_URL=$(echo "$DOWNLOAD_INFO" | jq -r '.downloads["server:default"].url')

log "  Versione: $MC_VERSION, Build: $BUILD"
curl -fsSL "$JAR_URL" -o "$JAR_NAME"
ln -sf "$JAR_NAME" paper.jar
log "  Scaricato: $JAR_NAME"

# ──────────────────────────────────────────────────────────────────────────────
# Plugin essenziali
log "Scarico plugin essenziali..."
cd "$MC_DIR/plugins"

# URL testati e funzionanti (aggiornare se cambiano)
# Nota: LuckPerms e CoreProtect scaricati manualmente se necessario
declare -A PLUGINS=(
  # Geyser + Floodgate (Bedrock cross-play) - FUNZIONANO
  ["Geyser-Spigot.jar"]="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
  ["floodgate-spigot.jar"]="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"

  # Version support (1.8-1.21.x) - via Hangar CDN
  ["ViaVersion.jar"]="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.12.2/PAPER/ViaVersion-5.12.2.jar"
  ["ViaRewind.jar"]="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaRewind/versions/4.2.0/PAPER/ViaRewind-4.2.0.jar"
  ["ViaBackwards.jar"]="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/5.12.2/PAPER/ViaBackwards-5.12.2.jar"

  # EssentialsX - GitHub releases
  ["EssentialsX.jar"]="https://github.com/EssentialsX/Essentials/releases/download/2.22.0/EssentialsX-2.22.0.jar"
  ["EssentialsXChat.jar"]="https://github.com/EssentialsX/Essentials/releases/download/2.22.0/EssentialsXChat-2.22.0.jar"
  ["EssentialsXSpawn.jar"]="https://github.com/EssentialsX/Essentials/releases/download/2.22.0/EssentialsXSpawn-2.22.0.jar"

  # WorldEdit - BukkitDev
  ["WorldEdit.jar"]="https://dev.bukkit.org/projects/worldedit/files/latest"

  # Spark - profiler
  ["Spark.jar"]="https://ci.lucko.me/job/Spark/lastSuccessfulBuild/artifact/spark-bukkit/build/libs/spark-1.10.196-bukkit.jar"
)

# Plugin opzionali (da installare manualmente se necessario)
# LuckPerms: https://luckperms.net/downloads
# CoreProtect: https://coreprotect.net/download.php

for plugin in "${!PLUGINS[@]}"; do
  url="${PLUGINS[$plugin]}"
  log "  $plugin..."
  curl -fsSL "$url" -o "$plugin" 2>/dev/null || warn "  Fallito: $plugin (prova manuale)"
done

# ──────────────────────────────────────────────────────────────────────────────
# Config Geyser (config.yml generato al primo avvio, qui prepariamo)
log "Preparo config Geyser..."
mkdir -p "$MC_DIR/plugins/Geyser-Spigot"
if [[ -f "$MC_DIR/plugins/Geyser-Spigot/config.yml" ]]; then
  warn "config Geyser esiste già: non lo sovrascrivo"
else
cat > "$MC_DIR/plugins/Geyser-Spigot/config.yml" << 'GEYSER_EOF'
bedrock:
  address: 0.0.0.0
  port: 19132
  clone-remote-port: false
  motd1: "PaperMC + Geyser"
  motd2: "Java & Bedrock cross-play"
  server-name: "PaperMC + Geyser"
  compression-level: 6
  enable-proxy-protocol: false
remote:
  address: 127.0.0.1
  port: 25565
  auth-type: offline
  allow-password-authentication: true
  use-proxy-protocol: false
  forward-hostname: false
extended-world-height: true
floodgate-key-file: public-key.pem
command-suggestions: true
passthrough-motd: true
passthrough-protocol-name: false
passthrough-player-counts: true
legacy-ping-passthrough: false
ping-passthrough-interval: 30
forward-player-ping: false
GEYSER_EOF
fi

# ──────────────────────────────────────────────────────────────────────────────
# EULA
log "Accetto EULA..."
echo "eula=true" > "$MC_DIR/eula.txt"

# ──────────────────────────────────────────────────────────────────────────────
# server.properties ottimizzato
log "Genero server.properties..."
if [[ -f "$MC_DIR/server.properties" ]]; then
  warn "server.properties esiste già: non lo sovrascrivo"
else
cat > "$MC_DIR/server.properties" << 'PROPS_EOF'
# PaperMC + Geyser optimized
server-port=25565
server-ip=0.0.0.0
enable-rcon=false
rcon.port=25575
rcon.password=changeme
enable-query=false
query.port=25565
motd=PaperMC + Geyser Cross-Play
max-players=30
view-distance=10
simulation-distance=6
spawn-protection=16
difficulty=normal
gamemode=survival
hardcore=false
pvp=true
spawn-monsters=true
spawn-animals=true
spawn-npcs=true
generate-structures=true
level-name=world
level-seed=
level-type=minecraft\:normal
force-gamemode=false
allow-flight=false
player-idle-timeout=30
max-tick-time=60000
network-compression-threshold=256
sync-chunk-writes=true
use-native-transport=true
online-mode=false
prevent-proxy-connections=false
enforce-secure-profile=false
enable-status=true
broadcast-rcon-to-ops=true
broadcast-console-to-ops=true
hide-online-players=false
rate-limit=0
max-build-height=320
min-build-height=-64
function-permission-level=2
PROPS_EOF
fi

# ──────────────────────────────────────────────────────────────────────────────
# paper.yml ottimizzato (performance)
log "Genero paper.yml..."
if [[ -f "$MC_DIR/config/paper.yml" ]]; then
  warn "paper.yml esiste già: non lo sovrascrivo"
else
cat > "$MC_DIR/config/paper.yml" << 'PAPER_EOF'
# PaperMC config - performance per 30 giocatori
verbose: false
config-version: 31
settings:
  load-permissions-yml-before-plugins: true
  book-size:
    page-max: 2560
    total-multiplier: 0.5
  console:
    use-bukkit-color: true
  bstats: true
  plugin-profiling: true
  watchdog:
    early-warning-every: 5000
    early-warning-delay: 10000
  use-alternate-luckperms-provider: false
  region-file-compression: DEFLATE
  chunks-per-tick: 650
  disable-chest-cat-detection: true
  container-update-tick-rate: 1
  hopper:
    disable-move-event: true
    cooldown-when-full: true
    push-transfer-cooldown: 0
  fixed-chunk-inhabited-time: -1
  baby-zombie-movement-speed: 0.5
  zombie-aggressive-towards-villager: true
  perceptual-trimmer:
    update-interval: 3
  netty:
    direct-buffer-pool-size: 0
  collision:
    apply-max-collisions-per-tick-to-players: true
    max-collisions-per-tick: 8
  vehicle:
    max-passengers: 4
  spawn:
    spawn-limits:
      monsters: 70
      animals: 15
      water-animals: 5
      water-ambient: 20
      water-underground: 5
      axolotls: 5
      ambient: 15
    mob-spawn-range: 4
    tick-rates:
      monster: 1
      animal: 400
      water-animal: 400
      water-ambient: 400
      water-underground: 400
      axolotl: 400
      ambient: 400
    spawn-radius: 10
    despawn-ranges:
      soft: 32
      hard: 128
    auto-save-interval: 6000
    per-player-mob-spawns: true
    altitude:
      maximum: 256
      minimum: 0
  entity-activation-range:
    animal: 32
    monster: 32
    raider: 48
    misc: 16
    water: 16
    villagers: 32
    flying-monsters: 48
  nerf-spawner-mobs: true
  max-auto-save-chunks-per-tick: 24
  optimize-explosions: true
  treasure-maps:
    enabled: true
    find-already-discovered:
      loot-tables: true
      structures: true
  max-entity-collisions: 8
  disable-thunder: false
  disable-ice-and-snow: false
  disable-unloaded-chunk-enderpearl-exploit: true
  non-player-arrow-despawn-rate:
    creative: -1
    survival: 60
  creative-arrow-despawn-rate: -1
  prevent-tnt-from-slowing-server: false
  fire-physics-event-for-redstone: false
  grass-spread-tick-rate: 1
  despawn-ranges:
    animal: 40
    monster: 40
    ambient: 40
    axolotl: 40
    water-animal: 40
    water-ambient: 40
    water-underground: 40
    raider: 48
    misc: 32
  container-update-tick-rate: 1
  enable-treasure-maps: true
  use-faster-eigencraft-redstone: true
  armor-stands:
    do-collision-entity-lookups: true
    tick: true
    gravity: true
    physics: true
    pushable: true
  non-player-arrow-despawn-rate:
    creative: -1
    survival: 60
  experience-merge-max-value: -1
  keep-spawn-loaded: true
  keep-spawn-loaded-range: 10
  max-chunk-sends-per-tick: 100
  max-chunk-generation-per-tick: 5
  light-queue-size: 20000
  max-growth-height:
    cactus: 3
    reeds: 3
    bamboo: 16
  entity-per-chunk-save-limit:
    experience_orb: 20
    arrow: 50
    snowball: 10
    ender_pearl: 10
    splash_potion: 50
    lingering_potion: 20
    small_fireball: 10
    fireball: 10
    wither_skull: 5
    shulker_bullet: 10
    llama_spit: 10
    firework_rocket: 50
  hopper:
    cooldown-when-full: true
    push-transfer-cooldown: 0
    disable-move-event: true
  disable-chest-cat-detection: true
  use-alternate-keepalive: true
  alternate-keepalive-interval: 5000
  use-per-chunk-tick-counter: true
  use-async-entity-tracker: true
  use-faster-eigencraft-redstone: true
  use-faster-dispenser-redstone: true
  use-faster-hopper-redstone: true
  use-faster-comparator-redstone: true
  use-faster-repeater-redstone: true
  use-faster-observer-redstone: true
  use-faster-piston-redstone: true
  use-faster-redstone-dust: true
  use-faster-redstone-wire: true
  use-faster-redstone-torch: true
  use-faster-lever-redstone: true
  use-faster-button-redstone: true
  use-faster-pressure-plate-redstone: true
  use-faster-tripwire-redstone: true
  use-faster-daylight-sensor-redstone: true
  use-faster-trapped-chest-redstone: true
  use-faster-redstone-lamp: true
  use-faster-noteblock-redstone: true
  use-faster-comparator-redstone: true
PAPER_EOF
fi

# ──────────────────────────────────────────────────────────────────────────────
# systemd user service
log "Creo systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/mc-server.service" << EOF
[Unit]
Description=Minecraft PaperMC + Geyser Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$MC_DIR
ExecStart=/usr/bin/java -Xms${MC_RAM} -Xmx${MC_RAM} \\
  -XX:+UseG1GC \\
  -XX:+ParallelRefProcEnabled \\
  -XX:MaxGCPauseMillis=200 \\
  -XX:+UnlockExperimentalVMOptions \\
  -XX:+DisableExplicitGC \\
  -XX:+AlwaysPreTouch \\
  -XX:G1NewSizePercent=30 \\
  -XX:G1MaxNewSizePercent=40 \\
  -XX:G1HeapRegionSize=8M \\
  -XX:G1ReservePercent=20 \\
  -XX:G1HeapWastePercent=5 \\
  -XX:G1MixedGCCountTarget=4 \\
  -XX:InitiatingHeapOccupancyPercent=15 \\
  -XX:G1MixedGCLiveThresholdPercent=90 \\
  -XX:G1RSetUpdatingPauseTimePercent=5 \\
  -XX:SurvivorRatio=32 \\
  -XX:+PerfDisableSharedMem \\
  -XX:MaxTenuringThreshold=1 \\
  -Dusing.aikars.flags=https://mcflags.emc.gs \\
  -Daikars.new.flags=true \\
  -jar paper.jar --nogui
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mc-server

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
log "systemd service installato. Comandi:"
echo "  systemctl --user start mc-server    # Avvia"
echo "  systemctl --user stop mc-server     # Ferma"
echo "  systemctl --user restart mc-server  # Riavvia"
echo "  systemctl --user status mc-server   # Stato"
echo "  journalctl --user -u mc-server -f   # Log live"

# ──────────────────────────────────────────────────────────────────────────────
# Script backup
log "Creo script backup..."
cat > "$MC_DIR/backup.sh" << 'BACKUP_EOF'
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
# Overworld, Nether, End e configurazione (solo ciò che esiste)
ITEMS=()
for item in "$WORLD_NAME" "${WORLD_NAME}_nether" "${WORLD_NAME}_the_end" \
            server.properties config; do
  [[ -e "$MC_DIR/$item" ]] && ITEMS+=("$item")
done
tar -czf "$ARCHIVE" -C "$MC_DIR" "${ITEMS[@]}"

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
BACKUP_EOF

chmod +x "$MC_DIR/backup.sh"

# ──────────────────────────────────────────────────────────────────────────────
# Backup automatico giornaliero (systemd user timer, ore 03:00)
log "Creo timer di backup giornaliero..."
cat > "$HOME/.config/systemd/user/mc-backup.service" << EOF
[Unit]
Description=Backup Minecraft server

[Service]
Type=oneshot
Environment=MC_DIR=$MC_DIR
Environment=BACKUP_REMOTE=$BACKUP_REMOTE
Environment=BACKUP_KEEP_DAYS=$BACKUP_KEEP_DAYS
ExecStart=$MC_DIR/backup.sh
EOF

cat > "$HOME/.config/systemd/user/mc-backup.timer" << 'EOF'
[Unit]
Description=Backup Minecraft server ogni giorno alle 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now mc-backup.timer \
  || warn "Timer di backup non attivato: systemctl --user enable --now mc-backup.timer"

# Senza lingering i servizi utente si fermano al logout e non partono al boot
if command -v loginctl >/dev/null 2>&1; then
  sudo loginctl enable-linger "$USER" \
    || warn "Lingering non attivato: sudo loginctl enable-linger $USER"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Alias utili
log "Aggiungo alias a ~/.bashrc..."
if grep -q "# Minecraft server aliases" ~/.bashrc 2>/dev/null; then
  warn "Alias già presenti in ~/.bashrc: non li riaggiungo"
else
cat >> ~/.bashrc << 'ALIAS_EOF'

# Minecraft server aliases
alias mc-start='systemctl --user start mc-server'
alias mc-stop='systemctl --user stop mc-server'
alias mc-restart='systemctl --user restart mc-server'
alias mc-status='systemctl --user status mc-server'
alias mc-logs='journalctl --user -u mc-server -f'
alias mc-console='systemctl --user status mc-server && echo "Use: journalctl --user -u mc-server -f for live logs"'
alias mc-backup='$HOME/minecraft-server/backup.sh'
alias mc-backup-list='ls -lh $HOME/minecraft-server/backups/'
alias mc-backup-now='BACKUP_REMOTE="" $HOME/minecraft-server/backup.sh'
alias mc-version='cat $HOME/minecraft-server/paper.jar 2>/dev/null | strings | grep -i paper | head -1 || echo "Server non installato"'
ALIAS_EOF
fi

# ──────────────────────────────────────────────────────────────────────────────
# Tailscale (installa se manca)
if [[ "$TAILSCALE_ENABLED" == true ]]; then
  log "Configuro Tailscale..."
  if ! command -v tailscale >/dev/null 2>&1; then
    log "Installa Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "non connesso")
    log "Tailscale IP: $TAILSCALE_IP"
    echo ""
    echo "=== CONNESSIONE AMICI ==="
    echo "Java:  $TAILSCALE_IP:25565"
    echo "Bedrock: $TAILSCALE_IP:19132"
    echo ""
    echo "Gli amici devono:"
    echo "  1. Installare Tailscale"
    echo "  2. Accedere alla tua tailnet (invitali da admin console)"
    echo "  3. Connettersi con gli IP sopra"
  else
    warn "Tailscale install fallito. Installa manualmente: curl -fsSL https://tailscale.com/install.sh | sh"
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Primo avvio test
echo ""
log "=== INSTALLAZIONE COMPLETATA ==="
echo ""
echo "Directory: $MC_DIR"
echo "RAM allocata: $MC_RAM"
echo "Versione MC: $MC_VERSION"
echo "Backup remote: ${BACKUP_REMOTE:-"(solo locale)"}"
echo ""
echo "Per avviare:"
echo "  mc-start"
echo ""
echo "Per fermare:"
echo "  mc-stop"
echo ""
echo "Log live:"
echo "  mc-logs"
echo ""
echo "Backup manuale:"
echo "  mc-backup"
echo ""
echo "Connessione (se Tailscale attivo):"
echo "  Java:  <tailscale-ip>:25565"
echo "  Bedrock: <tailscale-ip>:19132"
echo ""
warn "IMPORTANTE: Riavvia terminale (o 'source ~/.bashrc') per gli alias"