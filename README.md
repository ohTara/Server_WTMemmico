# Server_WTMemmico — Minecraft PaperMC + Geyser Server

Server Minecraft **Java + Bedrock cross-play** per 30 giocatori, vanilla+modded, esposto via Tailscale, con auto-backup e gestione systemd.

## Requisiti

- Pop!_OS / Ubuntu 24.04+ (o derivati Debian)
- 8 GB+ RAM (6 GB allocati al server)
- Java 25 (headless)
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
1. Installa Java 25 + dipendenze
2. Scarica PaperMC 1.21.11 (build 34) via API v3
3. Scarica plugin: Geyser, Floodgate, ViaVersion family, EssentialsX, più LuckPerms, CoreProtect, GriefPrevention, squaremap, SkinsRestorer, AuthMe e PacketEvents da Modrinth
4. Configura `server.properties`, `paper.yml`, `config.yml` (Geyser) e attiva RCON con una password casuale
5. Crea systemd user service `mc-server`
6. Installa gli strumenti in `~/minecraft-server/bin` (backup, ripristino, whitelist, avvisi Discord, firewall) e un timer systemd giornaliero (03:00)
7. Aggiunge alias bash (`mc-start`, `mc-stop`, `mc-logs`, `mc-cmd`, ecc.)
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
│   └── EssentialsXSpawn.jar  # Spawn management
├── config/                   # Config plugin (Geyser, etc.)
├── world/                    # Mondo Overworld
├── world_nether/             # Nether
├── world_the_end/            # The End
├── backups/                  # Backup automatici (tar.gz)
├── bin/                      # Strumenti: backup.sh, ripristina.sh, mc-rcon, mc-whitelist, mc-discord, firewall.sh
├── backup.sh                 # Collegamento a bin/backup.sh
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
| `mc-console` | Console interattiva: scrivi i comandi senza la `/`, `exit` per uscire (usa RCON) |
| `mc-backup` | Backup manuale mondi + config |
| `mc-backup-now` | Backup manuale solo locale (senza upload rclone) |
| `mc-backup-list` | Lista backup locali |
| `mc-version` | Versione PaperMC installata |
| `mc-cmd <comando>` | Manda un comando alla console del server acceso (es. `mc-cmd say ciao`, `mc-cmd list`) |
| `mc-whitelist` | Gestisce la lista dei giocatori ammessi (`list`, `add`, `remove`, `on`, `off`) |
| `mc-ripristina` | Riporta i mondi a un backup |
| `mc-discord "testo"` | Manda un messaggio sul canale Discord configurato |
| `mc-firewall` | Chiude le porte in entrata (playit.gg e Tailscale continuano a funzionare) |

### Systemd diretto

```bash
systemctl --user start mc-server
systemctl --user stop mc-server
systemctl --user restart mc-server
systemctl --user status mc-server
journalctl --user -u mc-server -f
```

## Accesso per gli amici (playit.gg)

Gli amici si collegano da qualsiasi rete senza installare nulla, basta che il PC sia acceso: il server e playit partono da soli all'avvio. Nessuna porta aperta sul router.

1. Installa l'agent da `playit.gg/download` (pacchetto `.deb`): gira come servizio di sistema `playit.service`.
2. Lancia `playit`, apri il link e collega il PC al tuo account.
3. Su playit.gg crea due tunnel assegnati all'agent:
   - **Minecraft Java (game)** → `127.0.0.1:25565`
   - **Minecraft Bedrock (game)** → `127.0.0.1:19132` (accetta "requires RakNet": Geyser usa `transport: both`, RakNet su 19132/udp e NetherNet su 19133/udp)
4. Passa agli amici, in privato, i due indirizzi che ti dà playit. Java: solo il nome (la porta la trova il record SRV); Bedrock: nome e porta.

## Console (Xbox, PlayStation, Switch) con MCXboxBroadcast

Le console non permettono di inserire un indirizzo. L'estensione di Geyser **MCXboxBroadcast** (in `plugins/Geyser-Spigot/extensions/`) fa comparire il server nella scheda **Amici** di Minecraft tramite un account Microsoft secondario.

1. Crea un account Microsoft nuovo ed entra una volta in Minecraft Bedrock con quello.
2. Scarica `MCXboxBroadcastExtension.jar` dalle release di `github.com/MCXboxBroadcast/Broadcaster` in `plugins/Geyser-Spigot/extensions/` e riavvia.
3. Nel log (`mc-logs`) compare un codice: aprilo su `microsoft.com/link` **con l'account secondario**.
4. In `extensions/mcxboxbroadcast/config.yml` imposta `remote-address` e `remote-port` sull'indirizzo playit di Bedrock, poi riavvia.
5. Gli amici aggiungono l'account secondario su Xbox e trovano il server in **Gioca → Amici**.

## Tailscale (accesso per l'amministratore)

Serve a te per raggiungere il PC da ovunque (SSH, mappa web, gioco) senza passare da playit; il firewall lascia aperte le porte di gioco e la mappa solo su `tailscale0`.

```bash
sudo tailscale up --operator=$USER   # login una volta sola
tailscale ip -4                      # IP 100.x.y.z
# Java 100.x.y.z:25565 · Bedrock 100.x.y.z:19132 · mappa http://100.x.y.z:8080
```

## Sicurezza

Con `online-mode=false` chiunque raggiunga la porta può entrare con qualsiasi nome, anche quello di un operatore. Per questo **AuthMe** chiede a ogni giocatore Java una password: `/register <password> <password>` la prima volta, poi `/login <password>`. Altre protezioni, da attivare a mano quando decidi:

```bash
mc-firewall          # 1. nessuna porta aperta in entrata (UFW); playit.gg e Tailscale funzionano lo stesso
mc-whitelist on      # 2. entra solo chi ha già giocato, più chi aggiungi
mc-whitelist add Mario      # nuovo amico su Java
mc-whitelist add .Mario     # nuovo amico su Bedrock (nome con il punto: passa da Floodgate)
```

3. **CoreProtect** registra chi piazza e rompe ogni blocco. In gioco, da operatore: `/co inspect` per interrogare un blocco, `/co rollback u:Nome t:1h r:20` per annullare un'ora di danni di un giocatore nel raggio di 20 blocchi.

`mc-firewall` chiede conferma prima di applicare le regole e lascia aperto SSH. La whitelist da sola non basta: in `online-mode=false` un nome ammesso si può imitare, per questo serve AuthMe.

I giocatori Bedrock hanno un `.` davanti al nome (Floodgate): lo script modifica `allowedNicknameCharacters` di AuthMe per accettarlo. Il `config.yml` di AuthMe nasce al primo avvio, quindi su un'installazione nuova rilancia lo script dopo aver avviato il server una volta.

**RCON** è la console a distanza usata dagli strumenti. La password è casuale, sta in `server.properties` (permessi 600) e la porta 25575 non viene aperta dal firewall.

## Backup & Restore

### Backup automatico
Timer systemd utente `mc-backup.timer`, ogni giorno alle 03:00. **Il server resta acceso**: lo script avvisa in chat, sospende il salvataggio automatico, crea l'archivio e lo riattiva. Solo se RCON non risponde ferma il server per la durata della copia.

```bash
systemctl --user list-timers mc-backup.timer   # prossima esecuzione
systemctl --user start mc-backup.service       # esecuzione immediata
cat ~/minecraft-server/backups/backup.log      # esito di ogni backup
```

L'archivio contiene `world/`, `world_nether/`, `world_the_end/`, `server.properties`, `config/`, `whitelist.json` e `ops.json`. Dopo la creazione viene verificato (si legge per intero e contiene `level.dat`); i backup vecchi si cancellano solo dopo un backup riuscito. I plugin non sono inclusi: si riscaricano con lo script di installazione.

### Backup manuale
```bash
mc-backup
```

Variabili d'ambiente:
```bash
export BACKUP_REMOTE="mc-backups:minecraft"  # rclone remote
export BACKUP_KEEP_DAYS=14                  # Rotazione giorni
export WORLD_NAME="world"                   # Mondo da backuppare
mc-backup
```

### Restore
```bash
mc-ripristina                                  # elenca i backup e chiede quale usare
mc-ripristina world-20261114-030000.tar.gz     # oppure indicane uno
```

Lo script controlla l'archivio, chiede di scrivere `RIPRISTINA`, ferma il server, **sposta** i mondi attuali in `backups/prima-del-ripristino-<data>/` (non li cancella) ed estrae quelli del backup. `server.properties` e `config/` non vengono toccati. Le cartelle `prima-del-ripristino-*` non hanno rotazione: cancellale quando non servono più.

### Cloud backup (rclone)
```bash
rclone config  # Crea remote "mc-backups" (S3, GDrive, Dropbox, ecc.)
# Lo script userà BACKUP_REMOTE per sync automatico
```

## Plugin aggiuntivi

Scaricati da Modrinth nella versione adatta a Paper e alla versione di Minecraft installata; se non esiste una versione compatibile il plugin viene saltato con un avviso.

| Plugin | A cosa serve | Per iniziare |
|---|---|---|
| LuckPerms | Permessi e ruoli | `/lp editor` apre l'editor web |
| CoreProtect | Registro dei blocchi e annullamento dei danni | `/co inspect`, `/co rollback` |
| GriefPrevention | Protezione dei terreni | Clic destro con la pala d'oro su due angoli |
| squaremap | Mappa web del mondo | `http://<ip-tailscale>:8080` |
| SkinsRestorer | Skin visibili con server offline | `/skin set <nome>` |
| AuthMe | Login con password per tutti i giocatori | `/register`, `/login` |
| PacketEvents | Serve ad AuthMe per nascondere l'inventario prima del login | — |

Per sceglierne solo alcuni: `MC_PLUGIN_EXTRA="luckperms coreprotect" ./install-mc-server.sh` (stringa vuota = nessuno).

## Avvisi su Discord

1. Nel canale Discord: *Modifica canale* → *Integrazioni* → *Webhook* → *Nuovo webhook* → *Copia URL webhook*.
2. Incolla l'indirizzo in `~/.config/mc-server/discord.env` (il file resta sul server, non va nella repo):
   ```bash
   DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
   ```
3. Attiva gli avvisi:
   ```bash
   systemctl --user enable --now mc-discord-watch
   mc-discord "Prova dal server"
   ```

Arrivano: server pronto, server spento, chi entra e chi esce, backup riuscito o fallito, ripristino di un backup. Senza webhook configurato gli strumenti funzionano uguale e non mandano nulla.

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

> **Nota:** Ri-eseguendolo, lo script aggiorna JAR, plugin e strumenti in `bin/` e riscrive il servizio systemd. In `server.properties` cambia solo le righe di RCON. **Non tocca** `world/`, `server.properties`, `config/paper.yml` e la configurazione di Geyser se esistono già. Per rigenerare uno di questi file con i valori predefiniti, cancellarlo prima di rilanciare lo script.

## File della repo

| File | Contenuto |
|---|---|
| `install-mc-server.sh` | Installazione e aggiornamento del server |
| `strumenti/` | Script installati in `~/minecraft-server/bin`: `backup.sh`, `ripristina.sh`, `mc-rcon`, `mc-whitelist`, `mc-discord`, `mc-discord-watch`, `firewall.sh` |
| `mc-server.service` | Copia di riferimento del servizio che lo script genera |
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
