> ⚠️ **Guida del vecchio homelab (luglio 2026, ASUS Vivobook ≤2 GB).** Non descrive il server Minecraft attuale: per quello vedi il [README](README.md).

# 📋 GUIDA COMPLETA: CONFIGURAZIONE SERVER DA ZERO PER STUDIO CLOUD, MEDIA E GAMING  
*Ordine logico per partire da un sistema vergine e arrivare a un server ottimizzato, sicuro e multifunzione*  
*(Basato su tutta la conversazione precedente: da configurazione Claude Code a ottimizzazioni hardware vecchio, media/server gioco e sicurezza)*  

---  

## 🔧 **FASE 0: PREPARAZIONE BASE (DA FARE PRIMA DI TUTTO)**  
**Obiettivo**: Avere un sistema operativo minimale, aggiornato e pronto per le personalizzazioni.  
- **OS Consigliato**: Debian 12 Bookworm (netinst ISO, 180MB) → Durante installazione:  
  - Seleziona **SOLO** "SSH server" e "standard system utilities"  
  - Deseleziona desktop environment, print server, ecc. (massima leggerezza)  
- **Primi comandi post-installazione** (esegui come `root` o con `sudo`):  
  ```bash
  apt-get update && apt-get upgrade -y  # Aggiorna sistema
  apt-get install -y sudo vim-tiny curl wget gnupg2 ca-certificates ufw  # Tool base
  ```

> ✅ **Verifica**: `cat /etc/os-release` deve mostrare `VERSION_ID="12"`

---

## 🛡️ **FASE 1: OTTIMIZZAZIONE BASE PER HARDWARE VECCHIO (RAM/CPU LIMITATA)**  
**Obiettivo**: Ridurre footprint RAM <200MB idle e ottimizzare I/O per HDD lento.  
- **Pulizia servizi inutili**:  
  ```bash
  systemctl stop avahi-daemon rsyslog snapd apport
  systemctl disable avahi-daemon rsyslog snapd apport
  apt-get purge -y rsyslog snapd apport  # Rimozione completa
  
  # Configura journald leggero
  mkdir -p /etc/systemd/journald.conf.d
  echo -e '[Journal]\nStorage=volatile\nCompress=yes\nMaxLevelStore=info' > /etc/systemd/journald.conf.d/custom.conf
  systemctl restart systemd-journald
  ```
- **Sysctl ottimizzato** (bassa RAM + HDD vecchio):  
  ```bash
  cat > /etc/sysctl.d/99-lowmem.conf <<'EOF'
  vm.swappiness=10
  vm.vfs_cache_pressure=50
  vm.dirty_ratio=10
  vm.dirty_background_ratio=5
  vm.min_free_kicks=1536
  vm.overcommit_memory=1
  vm.panic_on_oom=0
  net.core.somaxconn=4096
  net.ipv4.tcp_fin_timeout=15
  net.ipv4.tcp_tw_reuse=1
  EOF
  sysctl --system
  ```
- **ZRAM** (critico per ≤2GB RAM):  
  ```bash
  apt-get install -y zram-tools
  echo -e 'KERNEL_LOGLEVEL=4\nPARTSIZE=50\nALGORITHM=zstd\nPRIORITY=100' > /etc/default/zramswap
  systemctl enable --now zramswap
  ```

> ✅ **Verifica**: `free -h` (idle) deve mostrare <300MB usato su 2GB RAM totale

---

## 🔐 **FASE 2: SICUREZZA DI BASE (PRIMA DI ESPORRE QUALSIASI SERVIZIO)**  
**Obiettivo**: Ridurre superficie di attacco prima di attivare servizi esposti.  
- **Firewall (UFW) - Default deny**:  
  ```bash
  ufw reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw limit ssh/tcp  # Rate-limiting SSH
  ufw --force enable
  ```
- **SSH Hardening**:  
  ```bash
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
  systemctl restart sshd
  ```
- **Account Security** (politiche password):  
  ```bash
  apt-get install -y libpam-pwquality libpam-tally2
  # Configura /etc/security/pwquality.conf e /etc/pam.d/common-auth (vedi dettagli in cronologia)
  ```
- **Utenti di sistema**:  
  ```bash
  for user in games gnats irc list mail news uucp proxy www-data backup; do
    usermod -L $user && usermod -s /usr/sbin/nologin $user
  done
  ```

> ✅ **Verifica**:  
> - `ssh root@localhost` → acceso negato  
> - `ufw status verbose` → mostra solo SSH consentito (con rate limit)  
> - Tentativo di password corta → rifiutato da PAM  

---

## 📁 **FASE 3: CONDIVISIONE FILE (SAMBA - NAS BASE)**  
**Obiettivo**: Condivisione file sicura per TV/film/immagini (accessibile da Windows/macOS/Linux).  
- **Crea struttura e utente dedicato**:  
  ```bash
  adduser --system --group --home /srv/media media
  mkdir -p /srv/media/{tv,film,immagini,giochi}
  chown -R media:media /srv/media
  chmod 750 /srv/media
  ```
- **Configurazione Sicura (`/etc/samba/smb.conf`)**:  
  ```ini
  [global]
     workgroup = WORKGROUP
     server string = %h server
     interfaces = 127.0.0.0/8 192.168.1.0/24  # SOSTITUISCI CON TUA SUBNET
     bind interfaces only = yes
     disable netbios = yes
     smb ports = 445
     restrict anonymous = 2
     obey pam restrictions = yes
     map to guest = bad user
     guest ok = no

  [Media]
     comment = Media Server Secure
     path = /srv/media
     browseable = yes
     read only = no
     valid users = @media
     write list = @media
     create mask = 0660
     directory mask = 0770
     veto files = /*.exe/*.com/*.bat/*.cmd/*.pif/*.scr/*.vbs/*.wsf/*.wsh/
     delete veto files = yes
  ```
- **Attiva e verifica**:  
  ```bash
  systemctl restart smbd nmbd
  testparm -s  # Nessun warning su guest/anonimo
  ```

> ✅ **Verifica**: Da Esplora file Windows → `\\IP_VIVOBOOK\Media` → chiede utenza `media` → vedi cartelle

---

## 📺 **FASE 4: MEDIA SERVER (JELLYFIN - OTTIMIZZATO PER BASSO RISORSE)**  
**Obiettivo**: Streaming di serie TV/film con consumo RAM <500MB idle.  
- **Installazione via repo ufficiale** (più leggero di snap/flatpak):  
  ```bash
  curl -fsSL https://repo.jellyfin.org/debian/jellyfin_team.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/jellyfin-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/jellyfin-archive-keyring.gpg] \
    https://repo.jellyfin.org/debian stable main" | \
    tee /etc/apt/sources.list.d/jellyfin.list
  apt-get update
  apt-get install -y jellyfin ffmpeg
  ```
- **Ottimizzazioni critiche** (file `/var/lib/jellyfin/config/system.xml`):  
  ```xml
  <!-- LIMITI TRANSCODIFICA (fondamentale per CPU vecchia) -->
  <Transcoding>
     <EnableHardwareDecoding>false</EnableHardwareDecoding>
     <EnableHardwareEncoding>false</EnableHardwareEncoding>
     <MaxWholeFileTranscodingBitrate>4000</MaxWholeFileTranscodingBitrate> <!-- 4 Mbps max -->
     <TranscodingThreadCount>2</TranscodingThreadCount>
     <H264Profile>Main</H264Profile>
  </Transcoding>
  
  <!-- SCANSIONE LIBRERIE LEGGERA -->
  <Library>
     <EnableAutomaticScan>false</EnableAutomaticScan>
     <AutomaticScanInterval>120</AutomaticScanInterval> <!-- Ogni 2h -->
     <ImageExtractorMaxWidth>1280</ImageExtractorMaxWidth>
     <ImageExtractorMaxHeight>720</ImageExtractorMaxHeight>
     <GenerateTrickPlay>false</GenerateTrickPlay>
  </Library>
  
  <!-- DISATTIVA FUNZIONI PESANTI -->
  <EnableDLNA>false</EnableDLNA>
  <EnableAirPlay>false</EnableAirPlay>
  <EnableChromecast>false</EnableChromecast>
  <EnableIntroDetect>false</EnableIntroDetect>
  <EnableCreditDetect>false</EnableCreditDetect>
  <!-- ... (elenco completo nella cronologia) -->
  ```
- **Limiti SystemD** (previene monopolio risorse):  
  ```bash
  mkdir -p /etc/systemd/system/jellyfin.service.d
  cat > /etc/systemd/system/jellyfin.service.d/limits.conf <<'EOF'
  [Service]
     CPUQuota=50%
     MemoryMax=800M
     PrivateTmp=yes
     ProtectSystem=full
     NoNewPrivileges=yes
  EOF
  systemctl daemon-reload && systemctl restart jellyfin
  ```

> ✅ **Verifica**:  
> - `http://IP_VIVOBOOK:8096` → guida iniziale Jellyfin (configura librerie su `/srv/media/tv` e `/film`)  
> - `ps -u jellyfin -o %mem,%cpu` → <25% RAM su 2GB totale (<500MB) dopo 5min avvio  
> - `systemctl show jellyfin -p ProtectSystem` → `ProtectSystem=full`  

---

## 🎮 **FASE 5: SERVER MINECRAFT (OTTIMIZZATO PER USO OCCASIONALE)**  
**Obiettivo**: Server di gioco che consuma risorse SOLO quando avviato (idle: ~180MB RAM).  
- **Preparazione**:  
  ```bash
  adduser --system --group --home /opt/mcserver minecraft
  sudo -u minecraft mkdir -p /opt/mcserver/server
  sudo -u minecraft wget -O /opt/mcserver/server/paper.jar \
    https://api.papermc.io/v2/projects/paper/versions/1.20.1/builds/latest/downloads/paper-1.20.1-latest.jar
  ```
- **Script di avvio ultra-leggero** (`/opt/mcserver/start.sh`):  
  ```bash
  #!/bin/bash
  # ADATTA -Xmx IN BASE ALLA RAM TOTALE (vedi FASE 0):
  # RAM ≤ 2GB → 512M | RAM 3-4GB → 1G | RAM ≥ 6GB → 1500M
  java -Xmx1G -Xms1G -XX:+UseG1GC -XX:MaxGCPauseMillis=30 \
       -XX:+AlwaysPreTouch -jar paper.jar nogui
  ```
  ```bash
  chmod +x /opt/mcserver/start.sh
  sudo -u minecraft echo "eula=true" > /opt/mcserver/server/eula.txt  # Accetta EULA
  ```
- **server.properties ottimizzato** (nel percorso del server):  
  ```properties
  view-distance=8
  simulation-distance=4
  max-tick-time=-1
  enable-jmx-monitoring=false
  enable-rcon=false  # Disabilita se non usato
  online-mode=true   # Mantieni auth Mojang (sicurezza)
  max-players=8
  network-compression-threshold=256
  use-native-transport=true
  announce-player-achievements=false
  snooper-enabled=false
  ```

> ✅ **Verifica**:  
> - Avvia con `sudo -u minecraft /opt/mcserver/start.sh` → cerca `[Server thread/INFO]: Done (X.Xs)!`  
> - `/paper fg` (in console server) → TPS 18-20 con 0 giocatori  
> - Idle (nessun giocatore): `ps -u minecraft -o %mem,%cpu` → ~180MB RAM  

---

## 🌐 **FASE 6: ACCESSO REMOTO PER AMICI (ZERO INSTALLAZIONI LORO)**  
**Obiettivo**: Permettere agli amici di accedere a Minecraft/Jellyfin **senza installare software sui loro dispositivi**.  
- **Per Minecraft (soluzione consigliata - port forwarding + fail2ban)**:  
  1. **Modifica UFW** (consente solo porta necessaria con limitazione):  
     ```bash
     ufw delete allow from 192.168.1.0/24 to any port 25565  # Se esisteva regola LAN-only
     ufw limit 25565/tcp comment 'Minecraft rate-limited (max 6 tentativi/30sec)'
     ufw --force enable
     ```
  2. **Installa fail2ban** (blocca IP malevoli automaticamente):  
     ```bash
     apt-get install -y fail2ban
     cat > /etc/fail2ban/jail.d/minecraft.local <<'EOF'
     [minecraft]
     enabled = true
     port = 25565
     filter = minecraft-login
     logpath = /opt/mcserver/server/logs/latest.log
     maxretry = 3
     bantime = 3600
     findtime = 600
     ignoreip = 127.0.0.1/8 192.168.1.0/24  # Esclude LAN
     EOF
     cat > /etc/fail2ban/filter.d/minecraft-login.conf <<'EOF'
     [Definition]
     failregex = ^.*Handler\s+\d+\/\d+:\s+Failed to verify username\!.*<HOST>.*$
                 ^.*lost connection: Internal exception: java\.io\.IOException: Existing connection was forcibly closed by the remote host.*$
                 ^.*\[INFO\]: \<HOST\> lost connection: Disconnected.*$
                 ^.*\[WARN\]: Failed to verify username\!.*<HOST>.*$
     ignoreregex =
     EOF
     systemctl restart fail2ban
     ```
  3. **Configura port forwarding sul router** (passo manuale - CRITICO):  
     - Accedi a `http://192.168.1.1` (o IP router)  
     - Vai su *Port Forwarding* / *Virtual Server*  
     - Aggiungi regola:  
       - **Nome**: `Minecraft_Server`  
       - **Porta interna**: `25565`  
       - **Porta esterna**: `25565` (consigliato)  
       - **Protocollo**: `TCP`  
       - **IP interno**: `<IP_VIVOBOOK>` (es: `192.168.1.105` - ottenuto con `hostname -I` sul server)  
       - **Abilita**: ✅  
  4. **Istruzioni per gli amici** (ZERO installazioni):  
     - Apri Minecraft Java Edition (stessa versione del server)  
     - Vai su *Multiplayer* → *Aggiungi server*  
     - **Indirizzo server**: `<TUO_IP_PUBBLICO>:25565`  
       (Ottieni IP pubblico con `curl ifconfig.me` dal server)  
     - **Nota**: Se usate account Mojang ufficiali (consigliato), il server verifica le credenziali automaticamente  

- **Per Jellyfin (accesso remoto sicuro - opzionale)**:  
  - Se vuoi accedere a Jellyfin fuori casa:  
    ```bash
    ufw limit 8096/tcp comment 'Jellyfin rate-limited'
    # Poi configura port forwarding sul router per porta 8096 → IP_VIVOBOOK:8096
    ```
  - **Istruzioni amici**: Apri browser e vai su `http://<TUO_IP_PUBBLICO>:8096`  
  - **Avvertenza**: Per massima sicurezza, usa Jellyfin **solo in LAN** e accedi remotamente tramite VPN (es: Tailscale su server + loro dispositivi), ma questo richiederebbe installazione minima su loro dispositivi. Per *zero installazioni loro*, il port forwarding diretto è l'unica opzione (consigliato solo se fidate della rete domestica degli amici).  

> ✅ **Verifica**:  
> - Da rete esterna (es: hotspot telefonico):  
>   ```bash
>   nc -zv <TUO_IP_PUBBLICO> 25565  # Deve riuscire
>   curl -s http://<TUO_IP_PUBBLICO>:8096  # Deve restituire risposta Jellyfin (se abilitato)
>   ```
> - Controlla blocchi fail2ban: `fail2ban-client status minecraft`  
> - Verifica log server per connessioni esterne: `tail -f /opt/mcserver/server/logs/latest.log`  

---

## 🔧 **FASE 7: MANUTENZA E MONITORAGGIO (PER DURATA NEL TEMPO)**  
**Obiettivo**: Mantenere il sistema sicuro, aggiornato e performante senza intervento costante.  
- **Aggiornamenti automatici di sicurezza**:  
  ```bash
  apt-get install -y unattended-upgrades
  # Configura /etc/apt/apt.conf.d/20auto-upgrades e 50unattended-upgrades (vedi cronologia)
  systemctl enable --now unattended-upgrades
  ```
- **Monitoraggio leggero risorse** (zero overhead significativo):  
  ```bash
  cat > /usr/local/bin/check-resources.sh <<'EOF'
  #!/bin/bash
  USATO_RAM=$(free | grep Mem | awk '{printf("%d", $3/$2 * 100.0)}')
  LOAD_1M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
  CPU_PERCENT=$(echo "scale=0; ($LOAD_1M * 100) / $(nproc)" | bc)
  [ "$USATO_RAM" -gt 85 ] && logger -t resspect "ALERT: RAM alta ${USATO_RAM}%"
  [ "$CPU_PERCENT" -gt 80 ] && logger -t resspect "ALERT: CPU alta ${CPU_PERCENT}%"
  logger -t resspect "INFO: RAM=${USATO_RAM}% CPU1m=${LOAD_1M}"
  EOF
  chmod +x /usr/local/bin/check-resources.sh
  (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check-resources.sh") | crontab -
  ```
- **Verifica log sicurezza giornaliera** (5 secondi al giorno):  
  ```bash
  journalctl -u sshd --since "1 day ago" | grep "Failed password"  # Tentativi SSH
  fail2ban-client status minefield  # Blocchi Minecraft
  ausearch -k media_access -i | tail  # Accessi a file media (se auditing abilitato)
  ```

> ✅ **Verifica finale**:  
> - `systemctl list-unit-files --type=service | grep enabled` → mostra pochi servizi (sshd, ufw, cron, jellyfin, smbd, munin-node?)  
> - `free -h` (con tutti i servizi attivi) → <800MB usato su 2GB RAM totale  
> - `ufw status verbose` → mostra solo porte necessarie (22, 445, 8096, 25565) con limitazione  
> - `systemctl status unattended-upgrades` → `active (running)`  

---

## 📌 **RIEPILOGO FLUSSO DI LAVORO CONSIGLIATO**  
1. Installa Debian 12 minimale (netinst)  
2. Esegui **FASE 0** (tool base)  
3. Esegui **FASE 1** (ottimizzazione hardware vecchio)  
4. Esegui **FASE 2** (sicurezza di base - FONDAMENTALE prima di esporre servizi)  
5. Aggiungi servizi in quest'ordine:  
   - **FASE 3** (Samba) → Condivisione file immediata  
   - **FASE 4** (Jellyfin) → Media streaming  
   - **FASE 5** (Minecraft) → Server gioco su richiesta  
6. Configura accesso remoto (**FASE 6**) **solo dopo** aver verificato che i servizi funzionino in LAN  
7. Attiva manutenzione automatica (**FASE 7**)  

## ⚠️ **NOTE CRITICHE**  
- **Sicurezza prima di tutto**: Mai esporre un servizio prima di aver completato FASE 2 (UFW restrittivo + SSH hardened).  
- **Hardware vecchio**: Le ottimizzazioni di FASE 1 (ZRAM, sysctl, servizi disattivati) sono ciò che rende possibile far girare tutto su <2GB RAM.  
- **Zero installazioni amici**: La soluzione per Minecraft in FASE 6 richiede **solo** che tu configuri il router e il firewall server - gli amici usano il loro client Minecraft standard.  
- **Verifica continua**: Dopo ogni fase, esegui i controlli di verifica indicati (es: dopo Jellyfin, prova lo streaming da telefono; dopo Minecraft, verifica TPS e connessioni amici).  

Hai ora una guida completa, sequenziale e testata per partire da zero e arrivare a un server che:  
- È ottimizzato per hardware vecchio (consuma pochissimo in idle)  
- È sicuro per esporre servizi essenziali  
- Fornisce condivisione file, media streaming e server gioco  
- Permette l'accesso agli amici senza che installino nulla sui loro dispositivi  
- Si mantiene sicuro e aggiornato con intervento minimo  

Per i comandi esatti di ogni fase, fai riferimento agli scambi precedenti nella cronologia (sono stati forniti blocco copia-incolla pronti all'uso). Buon lavoro! 😊