# 🖥️ HomeLab Server: Optimized Media/Gaming/Cloud Study Environment  
*A lightweight, secure Debian 12 server for media streaming, file sharing, and game servers—designed to run smoothly on old hardware (<2GB RAM) with zero-install access for friends.*

[![Maintenance](https://img.shields.io/badge/Maintained%20by-luca.tarallo-blue.svg)](https://github.com/luca.tarallo)  
[![Debian Version](https://img.shields.io/badge/Debian-12-blue.svg)](https://www.debian.org/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ✨ Key Features
- **🐧 OS-Optimized**: Debian 12 minimal install with ZRAM, sysctl tweaks, and service trimming for <200MB RAM idle usage
- **🔒 Security-First**: UFW hardening, SSH key-only auth, fail2ban, account policies, and service sandboxing
- **📁 Media Hub**: 
  - Samba NAS for cross-platform file sharing (Windows/macOS/Linux)
  - Jellyfin media server (optimized transcoding: 4Mbps max, 2 threads, <500MB RAM)
- **🎮 Game Server**: 
  - PaperMC Minecraft server (idle: ~180MB RAM, ~450MB with 2-3 players)
  - Zero-install access for friends (standard Minecraft client only)
- **🌐 Remote Access**: 
  - Port forwarding + fail2ban for secure external Minecraft/Jellyfin access
  - No software required on friends' devices
- **⚙️ Auto-Maintenance**: Unattended security updates + lightweight resource monitoring

## 🚀 Quick Start (High-Level)
> Detailed step-by-step instructions are in [`GUIDA-SERVER-CLOUD.md`](GUIDA-SERVER-CLOUD.md)

1. **Install Base OS**  
   → Flash [Debian 12 NetInst](https://www.debian.org/CD/netinst/) (select *SSH server + standard utilities only*)
2. **Initialize System**  
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install sudo vim-tiny curl wget gnupg2 ca-certificates ufw
   ```
3. **Apply Optimizations & Security**  
   → Follow phases 1-2 in the full guide (ZRAM, sysctl, UFW, SSH hardening)
4. **Deploy Services**  
   → Samba (phase 3) → Jellyfin (phase 4) → Minecraft (phase 5)
5. **Enable Remote Access**  
   → Configure port forwarding + fail2ban (phase 6) *after* verifying LAN functionality
6. **Activate Maintenance**  
   → Enable automatic updates and resource monitoring (phase 7)

## 📋 Prerequisites
- **Hardware**: Any x86_64 device with ≥1GB RAM (tested on ASUS Vivobook with 2GB RAM)
- **Network**: Router with port forwarding capability (or use Tailscale for zero-router-config alternative)
- **Skills**: Basic Linux CLI comfort (all commands are copy-paste ready)

## 🔧 Service Access
| Service      | LAN Access                     | Remote Access (Friends)               | Notes                                  |
|--------------|--------------------------------|---------------------------------------|----------------------------------------|
| **Samba**    | `\\YOUR_SERVER_IP\Media`       | ❌ (LAN-only recommended)             | User: `media` / Your-set-password      |
| **Jellyfin** | `http://YOUR_SERVER_IP:8096`   | `http://YOUR_PUBLIC_IP:8096` (optional)| First-time setup: create admin account |
| **Minecraft**| `YOUR_SERVER_IP:25565`         | `YOUR_PUBLIC_IP:25565`                | Use **official Mojang accounts**       |

> 💡 **Public IP Tip**: Run `curl ifconfig.me` on the server to find your public IP for remote access.

## ⚠️ Critical Notes
- **Security Order**: Always complete [Phase 2 (Security)](GUIDA-SERVER-CLOUD.md#️⃣-fase-2-sicurezza-di-base-prima-di-esporre-qualsiasi-servizio) before exposing any service to the internet.
- **Hardware Limits**: 
  - Minecraft server: Start/stop manually via SSH (`sudo -u minecraft /opt/mcserver/start.sh`) to save resources when unused
  - Jellyfin: Transcoded streams limited to 4Mbps/720p to protect old CPUs
- **Friends' Experience**: 
  - They need **only** the standard Minecraft Java Edition client (same version as server)
  - No additional software, mods, or configuration required on their end
  - Recommend using official Mojang accounts for automatic credential verification

## 🛠️ Maintenance Tips
- Check logs weekly: `journalctl -u sshd --since "1 day ago" | grep "Failed password"`
- Monitor resource usage: `ssh user@server "htop"` (install via `apt-get install -y htop`)
- View Minecraft blocks: `fail2ban-client status minecraft`
- Update manually (if preferred): `sudo apt update && sudo apt upgrade -y`

## 📖 Full Documentation
See [`GUIDA-SERVER-CLOUD.md`](GUIDA-SERVER-CLOUD.md) for:
- Exact copy-paste commands for every configuration step
- Hardware-specific tuning tips (RAM/CPU thresholds)
- Troubleshooting common issues (TPS drops, connection failures)
- Advanced optimizations (kernel parameters, ZRAM tweaks, systemd limits)

## 🎓 Relevance to Cloud Studies
This lab environment directly supports cloud specialization coursework by providing:
- Hands-on experience with **Linux server administration** (ubiquitous in cloud infra)
- Practice with **network security concepts** (firewalls, fail2ban, least-privilege)
- Exposure to **media streaming architectures** (transcoding, CDN-adjacent concepts)
- **Game server ops** as an analogy for scalable, stateful cloud services
- Foundational skills transferable to AWS EC2, Azure VMs, or GCP Compute Engine

## 🙏 Acknowledgments
- Inspired by [PaperMC](https://papermc.io/) optimizations for low-end hardware
- Jellyfin team's [official Debian repo](https://repo.jellyfin.org/debian/)
- Fail2ban community for service-specific jail templates
- Debian administrators' guides for hardening best practices

---

> **Got questions?** Open an issue or reach out via your preferred channel.  
> **Happy labbing!** 😄  
> *Built with ☕ for cloud specialists who believe the best learning happens by doing.*