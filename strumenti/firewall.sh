#!/usr/bin/env bash
# firewall.sh — chiude il server a tutto cio' che non arriva da Tailscale.
#
# Da lanciare A MANO una volta sola:  ./firewall.sh
# Regole (UFW):
#   - in entrata tutto bloccato, in uscita tutto permesso
#   - SSH permesso con limite ai tentativi (per non chiudersi fuori)
#   - Minecraft Java 25565/tcp, Bedrock 19132/udp e mappa web 8080/tcp
#     solo dall'interfaccia tailscale0
#   - RCON (25575) non viene aperto: si usa solo da questa macchina
# online-mode=false e' accettabile solo finche' queste regole sono attive.
set -euo pipefail

INTERFACCIA="${TAILSCALE_IF:-tailscale0}"

ip link show "$INTERFACCIA" >/dev/null 2>&1 \
  || { echo "Interfaccia $INTERFACCIA non trovata: Tailscale e' installato e connesso?" >&2; exit 1; }
command -v ufw >/dev/null 2>&1 || sudo apt install -y ufw

echo "Sto per applicare queste regole con UFW:"
echo "  - blocco di tutte le connessioni in entrata, tranne:"
echo "  - SSH (22/tcp) con limite ai tentativi"
echo "  - 25565/tcp, 19132/udp e 8080/tcp solo da $INTERFACCIA"
echo "Chi gioca dalla rete di casa SENZA Tailscale non potra' piu' connettersi."
read -r -p "Procedo? [s/N] " risposta
[[ "$risposta" =~ ^[sS]$ ]] || { echo "Annullato."; exit 0; }

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit OpenSSH 2>/dev/null || sudo ufw limit 22/tcp
sudo ufw allow in on "$INTERFACCIA" to any port 25565 proto tcp comment 'Minecraft Java'
sudo ufw allow in on "$INTERFACCIA" to any port 19132 proto udp comment 'Minecraft Bedrock'
sudo ufw allow in on "$INTERFACCIA" to any port 8080 proto tcp comment 'Mappa web'
sudo ufw --force enable
sudo ufw status verbose
