# 🐳 Minecraft Server Setup (Podman rootless, home‑directory based)

This guide walks you through creating a PaperMC Minecraft server container using Podman, running as a systemd user service, with all data stored in your home directory (no sudo needed for `/opt` or `/srv`).  
It includes a simple local backup script (AWS‑free) and conservative resource limits suitable for ≤2 GB RAM hardware.

> **Prerequisites**  
> - Podman installed (`sudo apt-get install -y podman podman-docker`).  
> - You have obtained the necessary privileges (via `sudo` or `su -`) to install packages, but the Minecraft service itself must be run **as your regular user**.

---

## 1. Clean any previous attempts

```bash
# Stop and disable any lingering service
systemctl --user stop minecraft-container.service 2>/dev/null || true
systemctl --user disable minecraft-container.service 2>/dev/null || true

# Remove container and image (if you want a fresh start)
podman rm -f minecraft 2>/dev/null || true
podman rmi -f itzg/minecraft-server:latest 2>/dev/null || true

# Remove old service file and data directory
rm -f ~/.config/systemd/user/minecraft-container.service
rm -rf ~/mcserver
```

---

## 2. Create the directory structure in your home

```bash
# Where the server world will live
mkdir -p ~/mcserver/server

# Where the systemd user service files live
mkdir -p ~/.config/systemd/user
```

---

## 3. Backup script (AWS‑free for phase 3)

```bash
cat > ~/mcserver/backup-to-s3.sh <<'EOF'
#!/bin/bash
LOG_FILE="$HOME/mcserver/backup.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup eseguito - AWS non configurato (skip)" >> "$LOG_FILE"
EOF
chmod +x ~/mcserver/backup-to-s3.sh
```

*Later you can replace the contents of this script with a real AWS S3 backup once you have credentials.*

---

## 4. Systemd user service file

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

---

## 5. Reload systemd, enable and start the service

```bash
systemctl --user daemon-reload
systemctl --user enable --now minecraft-container.service
```

---

## 6. Verify the service is running

```bash
systemctl --user status minecottaincer.service --no-pager -l
```

Look for:

```
● minecraft-container.service - PaperMC Minecraft Server Container
     Loaded: loaded (/home/tuoutente/.config/systemd/user/minecraft-container.service; enabled; vendor preset: enabled)
     Active: active (running) since ...   ← ✅ deve dire "active (running)"
   Main PID: 12345 (podman)              ← ✅ deve mostrare "(podman)"
```

If you see anything else, copy the **entire** output of the above command and share it for troubleshooting.

---

## 7. Post‑start checks (optional but recommended)

```bash
# 7.1 See the container in podman
podman ps | grep minecraft

# 7.2 Monitor resource usage (should stay <800 MB RAM and ~0.5 CPU)
watch -n 5 "podman stats --no-stream minecraft && free -h"

# 7.3 Check the backup log (should show the skip message)
tail -n 5 ~/mcserver/backup.log

# 7.4 Connect from a Minecraft Java client
#    → Address: <TUO_IP>:25565
#    → Use an official Mojang account (no mods required)
```

---

## 8. Next steps (if you want to enable real AWS backups later)

1. Create an S3 bucket and an IAM policy allowing `s3:PutObject` on that bucket.
2. Configure AWS CLI (`aws configure`) with an access key/secret key that has that policy.
3. Replace the content of `~/mcserver/backup-to-s3.sh` with the real backup script (see the `GUIDA-SERVER-CLOUD.md` Phase 5 for an example).
4. Restart the service: `systemctl --user restart minecraft-container.service`.

---

## 9. Troubleshooting quick reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `Active: inactive (dead)` or `Failed` | Syntax error in service file or missing volume paths | Re‑check the service file; ensure `~/mcserver/server` and `~/mcserver/backup-to-s3.sh` exist. |
| Container exits immediately | Missing `EULA=TRUE` or port conflict | Verify the env var and that no other process is using port 25565 (`ss -tlnp | grep 25565`). |
| `permission denied` on volume mount | Trying to mount a path outside your home without proper permissions | Keep all volumes inside `~/mcserver` (as shown). |
| High RAM usage (>800 MB) | Java heap too high | Lower `--memory` and `-env MEMORY` values (e.g., 600 m) and restart. |

---

> 💡 **Why this works better than `/opt`**  
> - No need for `sudo` or root permissions for the service or data.  
> - All data lives in your home, making backups and migration trivial.  
> - Follows Linux best practices for user‑installed services (see the Filesystem Hierarchy Standard).  

You now have a fully functional, lightweight Minecraft server ready for your friends to join. Enjoy! 🚀