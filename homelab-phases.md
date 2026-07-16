# 📖 Guida alle fasi successive dell’homeschool Cloud Lab  
*(continua dopo la configurazione Samba – vedere `samba-setup-ubuntu24.04.md`)*  

Questo documento riassume le fasi **2‑5** della guida completa `GUIDA-SERVER-CLOUD.md`, adattate per un sistema Ubuntu 24.04 LTS con privilegi di root ottenuti tramite `su -` o tramite `sudo` configurato (vedi la sezione **Ottenere privilegi** nel file precedente).  

---

## 📺 Fase 2 – Containerizzare Jellyfin (Media Server con transcodifica limitata)

> **Obiettivo:** far girare Jellyfin in un container Podman rootless, limitando RAM e CPU per evitare OOM su hardware con ≤2 GB RAM, e abilitare l’accelerazione hardware Intel Quick Sync se disponibile.

### 1. Prerequisiti
- Podman già installato (`sudo apt-get install -y podman podman-docker`).
- Accesso al dispositivo `/dev/dri` (verifica con `vainfo`). Se non disponibile, ometti il flag `--device=/dev/dri`.

### 2. Creare la struttura di servizio
```bash
# Directory per la configurazione di Jellyfin (memorizza metadata, cache, log)
mkdir -p ~/jellyfin/config
mkdir -p ~/jellyfin/cache   # opzionale, per separare la cache

# Directory dei media (puntare allo stesso share Samba creato in precedenza)
# Assumiamo che lo share sia montato in /srv/media oppure che si voglia usare direttamente la cartella dell’utente:
mkdir -p ~/jellyfin/media
# Se vuoi usare la share Samba già montata, fai un bind mount:
# sudo mount --bind /srv/media ~/jellyfin/media   # oppure aggiungi voce in /etc/fstab
```

### 3. File di servizio Systemd (user)
```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/jellyfin-container.service <<'EOF'
[Unit]
Description=Jellyfin Media Server Container
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=%i
WorkingDirectory=%h
ExecStart=/usr/bin/podman run --name jellyfin \
  --replace \
  --volume ~/jellyfin/config:/config \
  --volume ~/jellyfin/cache:/cache \
  --volume ~/jellyfin/media:/media:ro \
  --publish 8096:8096/tcp \
  --publish 8920:8920/tcp \
  --restart=unless-stopped \
  --memory=500m \
  --cpus=1.0 \
  --device=/dev/dri \
  --env PUID=1000 \
  --env PGID=1000 \
  --env TZ=Europe/Rome \
  docker.io/jellyfin/jellyfin:latest

ExecStop=/usr/bin/podman stop -t 20 jellyfin
TimeoutStopSec=40
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
```

### 4. Avviare e verificare
```bash
systemctl --user daemon-reload
systemctl --user enable --now jellyfin-container.service
systemctl --user status jellyfin-container.service --no-pager -l
```
- Controlla che compaia `Active: active (running)`.
- Accedi da browser: `http://<TUO_IP>:8096` e completa la wizard iniziale (imposta lingua, impostazioni biblioteca puntando a `~/jellyfin/media` o al percorso Samba montato).

### 5. Limitazione transcodifica (opzionale)
Nella UI di Jellyfin → **Dashboard → Playback → Transcoding** imposta:
- **Maximum number of transcode slots:** `2`
- **Transcode quality:** `Balanced` o `Fast` (per CPU limitata).

---

## 🎮 Fase 3 – Containerizzare Minecraft (PaperMC) con backup S3 (AWS‑free per fase 3)

> **Obiettivo:** far girare un server Minecraft PaperMC in un container Podman rootless, limitando RAM a 800 MB e CPU a 0.5 core, con script di backup locale (senza AWS) pronto per essere esteso in seguito.

### 1. Pulizia (se necessario)
```bash
systemctl --user stop minecraft-container.service 2>/dev/null || true
systemctl --user disable minecraft-container.service 2>/dev/null || true
podman rm -f minecraft 2>/dev/null || true
rm -f ~/.config/systemd/user/minecraft-container.service
rm -rf ~/mcserver
```

### 2. Creare le directory
```bash
mkdir -p ~/mcserver/server
mkdir -p ~/.config/systemd/user
```

### 3. Script di backup (AWS‑free)
```bash
cat > ~/mcserver/backup-to-s3.sh <<'EOF'
#!/bin/bash
LOG_FILE="$HOME/mcserver/backup.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup eseguito - AWS non configurato (skip)" >> "$LOG_FILE"
EOF
chmod +x ~/mcserver/backup-to-s3.sh
```

### 4. File di servizio Systemd (user)
```bash
cat > ~/.config/systemd/user/minecraft-container.service <<'EOF'
[Unit]
Description=PaperMC Minecraft Server Container
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=%i
WorkingDirectory=%h
ExecStart=/usr/bin/podman run --name minecraft \
  --replace \
  --volume ~/mcserver/server:/data \
  --volume ~/mcserver/backup-to-s3.sh:/opt/backup.sh \
  --publish 25565:25565/tcp \
  --restart=unless-stopped \
  --memory=800m \
  --cpus=0.5 \
  --env EULA=TRUE \
  --env MEMORY=800M \
  --env ONLINE_MODE=TRUE \
  --env MAX_PLAYERS=4 \
  --env VIEW_DISTANCE=6 \
  --env SIMULATION_DISTANCE=3 \
  itzg/minecraft-server:latest

ExecStop=/usr/bin/podman stop -t 20 minecraft
TimeoutStopSec=40
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
```

### 5. Avviare e verificare
```bash
systemctl --user daemon-reload
systemctl --user enable --now minecraft-container.service
systemctl --user status minecottaincer.service --no-pager -l
```
- Cerca `Active: active (running)` e `Main PID: … (podman)`.
- Verifica risorse:
  ```bash
  watch -n 5 "podman stats --no-stream minecraft && free -h"
  ```
- Connetti gli amici con client Minecraft Java (versione 1.20.x o successiva) all’indirizzo `<TUO_IP>:25565`. Nessun mod richiesto.

### 6. (Facoltativo) Abilitare backup S3 reale
Quando avrai configurato un bucket AWS e le credenziali:
1. Modifica `~/mcserver/backup-to-s3.sh` sostituendo il contenuto con lo script reale (vedi `GUIDA-SERVER-CLOUD.md` sezione “Phase 5: Configure AWS S3 Backups”).
2. Assicurati che il container possa leggere `~/.aws/credentials` (monta la cartella oppure copia le credenziali dentro il container).

---

## 🏗️ Fase 4 – Gestione IaC con Terraform (facoltativa ma consigliata)

> **Obiettivo:** gestire i file di servizio Systemd (Samba, Jellyfin, Minecraft) come codice, così da poter ridistribuire l’intero stack con un singolo `terraform apply`.

### 1. Installare Terraform (se non fatto)
```bash
# già fatto dallo script di installazione risorse
terraform --version
```

### 2. Creare la directory di lavoro
```bash
mkdir -p ~/homelab-terraform
cd ~/homelab-terraform
```

### 3. File `main.tf` (provider locale)
```hcl
terraform {
  required_version = ">= 1.5.0"
  backend "local" {}
}

# Risorsa generica che copia il file di servizio e ricarica systemd
resource "null_resource" "samba" {
  triggers = {
    config = file("${path.module}/templates/samba-container.service")
  }
  provisioner "local-exec" {
    command = <<EOT
      cp ${path.module}/templates/samba-container.service ~/.config/systemd/user/
      systemctl --user daemon-reload
      systemctl --user restart samba-container.service
    EOT
  }
}

resource "null_resource" "jellyfin" {
  triggers = {
    config = file("${path.module}/templates/jellyfin-container.service")
  }
  provisioner "local-exec" {
    command = <<EOT
      cp ${path.module}/templates/jellyfin-container.service ~/.config/systemd/user/
      systemctl --user daemon-reload
      systemctl --user restart jellyfin-container.service
    EOT
  }
}

resource "null_resource" "minecraft" {
  triggers = {
    config = file("${path.module}/templates/minecraft-container.service")
  }
  provisioner "local-exec" {
    command = <<EOT
      cp ${path.module}/templates/minecraft-container.service ~/.config/systemd/user/
      systemctl --user daemon-reload
      systemctl --user restart minecraft-container.service
    EOT
  }
}
```

### 4. Cartella `templates/` e copia dei file di servizio
```bash
mkdir -p templates
cp ~/.config/systemd/user/samba-container.service templates/
cp ~/.config/systemd/user/jellyfin-container.service templates/
cp ~/.config/systemd/user/minecraft-container.service templates/
```
*(Se alcuni servizi non esistono ancora, crea prima i file di servizio come indicato nelle fasi precedenti, poi copiali.)*

### 5. Inizializzare e applicare
```bash
terraform init
terraform apply   # conferma con "yes"
```
Ogni volta che modifichi uno dei file in `templates/` e rilanci `terraform apply`, Terraform riconoscerà la modifica (tramite il `triggers = { config = file(...) }`) e ricopierà il servizio, ricaricando systemd e riavviando il container.

### 6. (Facoltativo) Gestire il backend S3 per lo state
Se desideri salvare lo stato su AWS S3 (richiede credenziali AWS configurate):
- Cambia il backend in `main.tf`:
  ```hcl
  terraform {
    backend "s3" {
      bucket = "il-tuo-bucket-terraform-state"
      key    = "homelab/terraform.tfstate"
      region = "us-east-1"
    }
  }
  ```
- Esegui nuovamente `terraform init` per migrare lo stato.

---

## 🔧 Fase 5 – Manutenzione e monitoraggio (facoltativo)

| Attività | Comando / Nota |
|----------|----------------|
| **Controllo risorse container** | `watch -n 5 "podman stats --no-stream && free -h"` |
| **Log journald** | `journalctl --user -u samba-container.service -f` <br> `journalctl --user -u jellyfin-container.service -f` <br> `journalctl --user -u minecottaincer.service -f` |
| **Aggravamento log** (facoltativo) | Modifica `/etc/systemd/journald.conf` → `Storage=persistent` e `SystemMaxUse=100M` |
| **Aggiornare container** | `systemctl --user restart <servizio>-container.service` (Podman pullerà l’immagine più recente se usando `:latest`) |
| **Backup manuale dei mondi Minecraft** | `cp -r ~/mcserver/server/world ~/mcserver/backup/world_$(date +%F_%H%M%S)` |
| **Verifica connessioni Samba** | `smbclient //localhost/Media -U media%<pw> -c "ls"` |
| **Test Jellyfin API** | `curl -s http://localhost:8096/System/Info | jq .` |

---

## 📂 Dove salvare questo documento

Per avere una copia permanente accanto alle altre guide:

```bash
cp /home/luca/Documents/homelab-phases.md /home/luca/Documents/
# oppure, se preferisci un nome più descrittivo:
cp /home/luca/Documents/homelab-phases.md /home/luca/Documents/homeserver-fasi-successive.md
```

Puoi poi aprirlo con qualsiasi editor di testo (`nano`, `vim`, `code`, …) per consultarlo o estenderlo.

---

### 🎉 Prossimi passi consigliati

1. **Terminare la fase Samba** (se ancora non fatto) usando `samba-setup-ubuntu24.04.md`.
2. **Applicare le fasi 2‑4** in sequenza: Jellyfin → Minecraft → Terraform.
3. **Facoltativo:** abilitare i backup S3 veri e propri (fase 5 della guida originale) una volta che avrai un account AWS e le credenziali IAM pronte.
4. **Documentare** ogni passaggio con dei commit in un repo Git (es. `~/homelab-ctrl`) per tenere traccia delle modifiche infrastrutturali – perfetto per il tuo percorso di Cloud Specialist.

Buona realizzazione del tuo laboratorio cloud domestico! 🚀  
*(Se incontri difficoltà, copia l’output del comando problematico e chiedi aiuto – sarò felice di guidarti passo‑passo.)*