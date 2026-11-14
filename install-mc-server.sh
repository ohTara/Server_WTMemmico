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
# Plugin aggiuntivi scaricati da Modrinth nella versione adatta al server.
# Per escluderne uno: MC_PLUGIN_EXTRA="luckperms coreprotect" ./install-mc-server.sh
MC_PLUGIN_EXTRA="${MC_PLUGIN_EXTRA-luckperms coreprotect griefprevention squaremap skinsrestorer authmereloaded}"
# Cartella della repo (per copiare gli strumenti) e indirizzo da cui scaricarli
# se lo script viene lanciato da solo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RAW="https://raw.githubusercontent.com/ohTara/Server_WTMemmico/main"
STRUMENTI=(backup.sh ripristina.sh mc-rcon mc-discord mc-discord-watch mc-whitelist firewall.sh)

# Colori
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# Prerequisiti
log "Verifica prerequisiti..."
# Java 25: le ultime versioni dei plugin (es. WorldEdit 7.4) non partono con Java 21
JAVA_MAJOR=$(java -version 2>&1 | awk -F'"' '/version/ {split($2, v, "."); print v[1]}' || true)
if [[ "${JAVA_MAJOR:-0}" -lt 25 ]]; then
  warn "Java 25 mancante (trovato: ${JAVA_MAJOR:-nessuno}), installo..."
  sudo apt update && sudo apt install -y openjdk-25-jre-headless
fi
command -v curl >/dev/null 2>&1 || sudo apt install -y curl
command -v jq >/dev/null 2>&1 || sudo apt install -y jq
command -v python3 >/dev/null 2>&1 || sudo apt install -y python3   # serve a mc-rcon
command -v rclone >/dev/null 2>&1 || { warn "rclone mancante, installo..."; curl https://rclone.org/install.sh | sudo bash; }

# ──────────────────────────────────────────────────────────────────────────────
# Directory
log "Creo directory $MC_DIR..."
mkdir -p "$MC_DIR"/{plugins,world,backups,config,bin}
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

)

for plugin in "${!PLUGINS[@]}"; do
  url="${PLUGINS[$plugin]}"
  log "  $plugin..."
  curl -fsSL "$url" -o "$plugin" 2>/dev/null || warn "  Fallito: $plugin (prova manuale)"
done

# Plugin aggiuntivi da Modrinth: per ognuno si chiede la versione piu' recente
# compatibile con Paper e con la versione di Minecraft installata. Se non ce n'e'
# una compatibile il plugin viene saltato (meglio assente che incompatibile).
#   luckperms       permessi e ruoli
#   coreprotect     registro di chi piazza/rompe blocchi, con annullamento dei danni
#   griefprevention protezione dei terreni con la pala d'oro
#   squaremap       mappa web del mondo (porta 8080)
#   skinsrestorer   mostra le skin anche col server in modalita' offline
#   authmereloaded  login con password (/register, /login): col server offline
#                   impedisce di entrare col nome di un altro
scarica_da_modrinth() {
  local slug="$1" url
  url=$(curl -fsSL -G "https://api.modrinth.com/v2/project/$slug/version" \
          --data-urlencode 'loaders=["paper"]' \
          --data-urlencode "game_versions=[\"$MC_VERSION\"]" 2>/dev/null \
        | jq -r '.[0].files | (map(select(.primary)) + .)[0].url // empty' 2>/dev/null || true)
  if [[ -z "$url" ]]; then
    warn "  $slug: nessuna versione per Paper $MC_VERSION, saltato"
    return 0
  fi
  log "  $slug..."
  if curl -fsSL "$url" -o "$slug.jar.nuovo"; then
    mv "$slug.jar.nuovo" "$slug.jar"
  else
    rm -f "$slug.jar.nuovo"
    warn "  Fallito: $slug (prova manuale)"
  fi
}
for slug in $MC_PLUGIN_EXTRA; do
  scarica_da_modrinth "$slug"
done

# AuthMe di base accetta solo [a-zA-Z0-9_]: i giocatori Bedrock hanno il "." di
# Floodgate davanti al nome e verrebbero cacciati. Il config.yml nasce al primo
# avvio: se non c'e' ancora, rilancia lo script dopo aver avviato il server.
AUTHME_CFG="$MC_DIR/plugins/AuthMe/config.yml"
if [[ -f "$AUTHME_CFG" ]]; then
  sed -i "s/^\( *allowedNicknameCharacters: \)'\[a-zA-Z0-9_\]\*'$/\1'\\\\.?[a-zA-Z0-9_]*'/" "$AUTHME_CFG"
fi

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
  # "both": RakNet su 19132/udp (richiesto dai tunnel playit.gg) e NetherNet,
  # il nuovo metodo di Bedrock, su 19133/udp. Geyser 2.12 non accetta piu' "raknet".
  transport: both
  webrtc-port: 19133
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
# RCON: la "console a distanza" con cui gli strumenti parlano al server acceso
# (backup senza spegnerlo, whitelist, avvisi in chat). Vale anche per un
# server.properties gia' esistente: si toccano solo queste righe.
imposta_proprieta() {   # imposta_proprieta chiave valore
  local file="$MC_DIR/server.properties"
  if grep -q "^$1=" "$file"; then
    sed -i "s|^$1=.*|$1=$2|" "$file"
  else
    echo "$1=$2" >> "$file"
  fi
}
PASSWORD_RCON=$(grep '^rcon.password=' "$MC_DIR/server.properties" | cut -d= -f2- || true)
if [[ -z "$PASSWORD_RCON" || "$PASSWORD_RCON" == "changeme" ]]; then
  log "Attivo RCON con una password casuale..."
  imposta_proprieta rcon.password "$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
imposta_proprieta enable-rcon true
grep -q '^rcon.port=' "$MC_DIR/server.properties" || imposta_proprieta rcon.port 25575
imposta_proprieta broadcast-rcon-to-ops false      # niente eco dei comandi agli operatori
chmod 600 "$MC_DIR/server.properties"              # contiene la password di RCON

# ──────────────────────────────────────────────────────────────────────────────
# Strumenti di gestione in $MC_DIR/bin (copiati dalla repo, o scaricati)
log "Installo gli strumenti in $MC_DIR/bin..."
for f in "${STRUMENTI[@]}"; do
  if [[ -f "$SCRIPT_DIR/strumenti/$f" ]]; then
    cp "$SCRIPT_DIR/strumenti/$f" "$MC_DIR/bin/$f"
  else
    curl -fsSL "$REPO_RAW/strumenti/$f" -o "$MC_DIR/bin/$f" || warn "  Non scaricato: $f"
  fi
  [[ -f "$MC_DIR/bin/$f" ]] && chmod +x "$MC_DIR/bin/$f"
done
ln -sf bin/backup.sh "$MC_DIR/backup.sh"           # percorso usato da timer e alias

# Avvisi su Discord: l'indirizzo del webhook resta fuori dalla repo
mkdir -p "$HOME/.config/mc-server"
if [[ ! -f "$HOME/.config/mc-server/discord.env" ]]; then
  cat > "$HOME/.config/mc-server/discord.env" << 'DISCORD_EOF'
# Incolla qui l'indirizzo del webhook del canale Discord e togli il # iniziale:
# (Discord: Impostazioni canale -> Integrazioni -> Webhook -> Nuovo webhook -> Copia URL)
#DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
DISCORD_EOF
  chmod 600 "$HOME/.config/mc-server/discord.env"
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
StartLimitIntervalSec=60
StartLimitBurst=3

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
ExecStopPost=-$MC_DIR/bin/mc-discord ":octagonal_sign: Server spento"
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mc-server

[Install]
WantedBy=default.target
EOF

# Annuncia su Discord chi entra, chi esce e quando il server e' pronto
cat > "$HOME/.config/systemd/user/mc-discord-watch.service" << EOF
[Unit]
Description=Avvisi Discord del server Minecraft

[Service]
ExecStart=$MC_DIR/bin/mc-discord-watch
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
if grep -q '^DISCORD_WEBHOOK=' "$HOME/.config/mc-server/discord.env"; then
  systemctl --user enable mc-discord-watch.service \
    && systemctl --user restart mc-discord-watch.service \
    || warn "Avvisi Discord non attivati: systemctl --user enable --now mc-discord-watch"
else
  warn "Avvisi Discord non configurati: vedi ~/.config/mc-server/discord.env"
fi
log "systemd service installato. Comandi:"
echo "  systemctl --user start mc-server    # Avvia"
echo "  systemctl --user stop mc-server     # Ferma"
echo "  systemctl --user restart mc-server  # Riavvia"
echo "  systemctl --user status mc-server   # Stato"
echo "  journalctl --user -u mc-server -f   # Log live"

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
alias mc-console='$HOME/minecraft-server/bin/mc-rcon'                 # console interattiva
alias mc-backup='$HOME/minecraft-server/backup.sh'
alias mc-backup-list='ls -lh $HOME/minecraft-server/backups/'
alias mc-backup-now='BACKUP_REMOTE="" $HOME/minecraft-server/backup.sh'
alias mc-version='cat $HOME/minecraft-server/paper.jar 2>/dev/null | strings | grep -i paper | head -1 || echo "Server non installato"'
ALIAS_EOF
fi

if ! grep -q "# Minecraft server: strumenti" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc << 'ALIAS2_EOF'

# Minecraft server: strumenti
alias mc-cmd='$HOME/minecraft-server/bin/mc-rcon'              # mc-cmd say ciao
alias mc-whitelist='$HOME/minecraft-server/bin/mc-whitelist'
alias mc-ripristina='$HOME/minecraft-server/bin/ripristina.sh'
alias mc-discord='$HOME/minecraft-server/bin/mc-discord'
alias mc-firewall='$HOME/minecraft-server/bin/firewall.sh'
ALIAS2_EOF
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
echo "Strumenti nuovi (apri un nuovo terminale per avere gli alias):"
echo "  mc-cmd say ciao        # comando alla console del server acceso"
echo "  mc-whitelist on        # ammette solo chi ha gia' giocato + chi aggiungi"
echo "  mc-ripristina          # riporta il mondo a un backup"
echo "  mc-firewall            # chiude le porte in entrata (playit e Tailscale ok)"
echo ""
warn "Se il server era gia' acceso, riavvialo (mc-restart): RCON e i plugin nuovi"
warn "partono solo al prossimo avvio."
echo ""
echo "Connessione (se Tailscale attivo):"
echo "  Java:  <tailscale-ip>:25565"
echo "  Bedrock: <tailscale-ip>:19132"
echo ""
warn "IMPORTANTE: Riavvia terminale (o 'source ~/.bashrc') per gli alias"