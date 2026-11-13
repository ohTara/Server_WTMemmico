# Server_WTMemmico — Minecraft PaperMC + Geyser Server

Server Minecraft **Java + Bedrock cross-play** per 30 giocatori, vanilla+modded, esposto via Tailscale, con auto-backup e gestione systemd.

## Requisiti

- Pop!_OS / Ubuntu 24.04+ (o derivati Debian)
- 8 GB+ RAM (6 GB allocati al server)
- Java 21 (headless)
- Tailscale (per accesso remoto zero-config)

## Installazione rapida

```bash
# Clona repo
git clone https://github.com/ohTara/Server_WTMemmico.git ~/Server_WTMemmico
cd ~/Server_WTMemmico

# Rendi eseguibile e lancia
chmod +x install-mc-server.sh
./install-mc-server.sh
```

Lo script fa tutto:
1. Installa Java 21 + dipendenze
2. Scarica PaperMC 1.21.11 (build 34) via API v3
3. Scarica plugin: Geyser, Floodgate, ViaVersion family, EssentialsX, Spark
4. Configura `server.properties`, `paper.yml`, `config.yml` (Geyser)
5. Crea systemd user service `mc-server`
6. Crea script backup con rotazione + rclone e un timer systemd giornaliero (03:00)
7. Aggiunge alias bash (`mc-start`, `mc-stop`, `mc-logs`, ecc.)
8. Installa e configura Tailscale
9. Attiva il lingering, così il server resta acceso dopo il logout e parte al boot

## Struttura

```
~/minecraft-server/
├── paper.jar                 # PaperMC server (symlink)
├── server.properties         # Config server (porta, online-mode, ecc.)
├── paper.yml                 # Config PaperMC (ottimizzazioni)
├── plugins/
│   ├── Geyser-Spigot.jar     # Bedrock cross-play
│   ├── floodgate-spigot.jar  # Auth Bedrock senza account Java
│   ├── ViaVersion.jar        # Protocol translation 1.8-1.21.x
│   ├── ViaRewind.jar         # Supporto versioni legacy
│   ├── ViaBackwards.jar      # Supporto versioni intermedie
│   ├── EssentialsX.jar       # Comandi base (/home, /spawn, /tpa, ecc.)
│   ├── EssentialsXChat.jar   # Chat formatting
│   ├── EssentialsXSpawn.jar  # Spawn management
│   └── Spark.jar             # Profiler performance
├── config/                   # Config plugin (Geyser, etc.)
├── world/                    # Mondo Overworld
├── world_nether/             # Nether
├── world_the_end/            # The End
├── backups/                  # Backup automatici (tar.gz)
├── backup.sh                 # Script backup manuale
└── logs/                     # Log server
```

## Comandi (alias in `~/.bashrc`)

| Comando | Descrizione |
|---|---|
| `mc-start` | Avvia server |
| `mc-stop` | Ferma server (graceful, 60s timeout) |
| `mc-restart` | Riavvia completo |
| `mc-status` | Stato systemd |
| `mc-logs` | Log live (journalctl -f) |
| `mc-console` | Stato del servizio (non c'è una console interattiva: il server gira sotto systemd) |
| `mc-backup` | Backup manuale mondi + config |
| `mc-backup-now` | Backup manuale solo locale (senza upload rclone) |
| `mc-backup-list` | Lista backup locali |
| `mc-version` | Versione PaperMC installata |

### Systemd diretto

```bash
systemctl --user start mc-server
systemctl --user stop mc-server
systemctl --user restart mc-server
systemctl --user status mc-server
journalctl --user -u mc-server -f
```

## Tailscale / Accesso remoto

```bash
# Dopo install, autentica Tailscale
tailscale up

# Ottieni IP per connessione
tailscale ip -4
# Es: 100.x.y.z

# Condividi con amici:
# Java Edition  →  100.x.y.z:25565
# Bedrock       →  100.x.y.z:19132 (UDP)
```

**Sicurezza:** `online-mode=false` e nessuna whitelist: chiunque raggiunga la porta può entrare con qualsiasi nome, anche quello di un operatore. Va bene solo finché il server è raggiungibile unicamente dalla tailnet. Prima di aprire le porte sul router, impostare `online-mode=true` oppure `white-list=true`.

## Backup & Restore

### Backup automatico
Timer systemd utente `mc-backup.timer`, ogni giorno alle 03:00. Il server viene fermato per la durata dell'archivio e poi riavviato.

```bash
systemctl --user list-timers mc-backup.timer   # prossima esecuzione
systemctl --user start mc-backup.service       # esecuzione immediata
journalctl --user -u mc-backup.service -n 50   # log dell'ultimo backup
```

L'archivio contiene `world/`, `world_nether/`, `world_the_end/`, `server.properties` e `config/`. I plugin non sono inclusi: si riscaricano con lo script di installazione.

### Backup manuale
```bash
mc-backup
# oppure
~/minecraft-server/backup.sh
```

Variabili d'ambiente per backup:
```bash
export BACKUP_REMOTE="mc-backups:minecraft"  # rclone remote
export BACKUP_KEEP_DAYS=14                  # Rotazione giorni
export WORLD_NAME="world"                   # Mondo da backuppare
mc-backup
```

### Restore
```bash
mc-stop
# Estrai backup in ~/minecraft-server/
tar -xzf ~/minecraft-server/backups/world-20241112-030000.tar.gz -C ~/minecraft-server/
mc-start
```

### Cloud backup (rclone)
```bash
rclone config  # Crea remote "mc-backups" (S3, GDrive, Dropbox, ecc.)
# Lo script userà BACKUP_REMOTE per sync automatico
```

## Plugin opzionali (installazione manuale)

```bash
cd ~/minecraft-server/plugins

# LuckPerms — permessi avanzati, gruppi, prefissi
wget https://download.luckperms.net/1685/bukkit/loader/LuckPerms-Bukkit-5.4.130.jar

# CoreProtect — rollback blocchi, lookup, protezione
wget https://ci.coreprotect.net/job/CoreProtect/lastSuccessfulBuild/artifact/target/CoreProtect-*-SNAPSHOT.jar

# WorldEdit — world editing (richiede build compatibile Java 21)
# Cerca build su: https://dev.bukkit.org/projects/worldedit/files

mc-restart
```

## Configurazione chiave

### server.properties
```properties
server-port=25565
server-port-ipv6=25565
online-mode=false
max-players=30
view-distance=10
simulation-distance=6
motd=PaperMC + Geyser §bCross-Play
```

### paper.yml (estratto ottimizzazioni)
```yaml
paper-world:
  keep-spawn-loaded: false
  auto-save-interval: 6000
  use-faster-eigencraft-redstone: true
  hopper:
    cooldown-when-full: true
```

### Geyser config (`config/Geyser-Spigot/config.yml`)
```yaml
bedrock:
  address: 0.0.0.0
  port: 19132
  motd1: "PaperMC + Geyser"
  motd2: "Cross-Play Java/Bedrock"
  server-name: "WTMemmico Server"
```

## Java Flags (Aikar G1GC)

```bash
-Xms6G -Xmx6G \
-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
-XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true
```

## Troubleshooting

| Problema | Soluzione |
|---|---|
| Server non parte | `journalctl --user -u mc-server -f` |
| Server si ferma al logout | `sudo loginctl enable-linger $USER` |
| Geyser "zip file closed" | Race condition restart → `mc-restart` risolve |
| WorldEdit error Java version | Build richiede Java 25+ → usa build compatibile o rimuovi |
| Bedrock non connette | Verifica porta 19132 UDP + `tailscale ip -4` corretto |
| Lag / TPS basso | in gioco, da operatore: `/spark profiler start --timeout 60` → analizza il report |
| Permessi "permission denied" | `chmod +x install-mc-server.sh backup.sh` |
| Tailscale non installa | `curl -fsSL https://tailscale.com/install.sh \| sh` manuale |

## Log utili

```bash
# Server log live
journalctl --user -u mc-server -f

# Ultimi 100 righe
journalctl --user -u mc-server -n 100 --no-pager

# Solo errori
journalctl --user -u mc-server -p err -n 50 --no-pager

# Backup log
cat ~/minecraft-server/backups/backup.log 2>/dev/null || echo "Nessun log backup"
```

## Aggiornamenti

```bash
# Aggiorna PaperMC + plugin
cd ~/Server_WTMemmico
git pull
./install-mc-server.sh  # Ri-esegue: scarica nuove versioni, preserva mondi/config
```

> **Nota:** Ri-eseguendolo, lo script aggiorna JAR e plugin e riscrive il servizio systemd e `backup.sh`. **Non tocca** `world/`, `server.properties`, `config/paper.yml` e la configurazione di Geyser se esistono già. Per rigenerare uno di questi file con i valori predefiniti, cancellarlo prima di rilanciare lo script.

## File della repo

| File | Contenuto |
|---|---|
| `install-mc-server.sh` | Installazione e aggiornamento del server |
| `backup.sh`, `mc-server.service` | Copie di riferimento di ciò che lo script genera |
| `server.properties`, `paper*.yml`, `config/` | Configurazione di riferimento del server |

### Guide del vecchio homelab (luglio 2026)

Riguardano un'altra macchina: ASUS Vivobook con ≤2 GB di RAM, servizi in container Podman con limiti stretti (Minecraft a 800 MB e 4 giocatori). **Non descrivono questo server.**

| File | Contenuto |
|---|---|
| `guida-server-cloud.md` | Guida completa da zero: ottimizzazione, sicurezza, Samba, Jellyfin, Minecraft |
| `homelab-phases.md` | Jellyfin e Minecraft in Podman, unit systemd gestite con Terraform |
| `ssh-hardening-ubuntu24.04.md` | Hardening SSH |
| `minecraft-fix-protocol.md`, `minecraft-setup-home.md` | Ripristino del container Minecraft |
| `cloud-study-resources.md` | Installazione degli strumenti cloud su Ubuntu/Debian |

## Licenza

Uso personale — niente segreti/chiavi in repo. Usa variabili d'ambiente per `BACKUP_REMOTE`, token rclone, ecc.
