#!/usr/bin/env bash
# firewall.sh — chiude il PC alle connessioni in entrata (playit.gg resta attivo).
#
# Da lanciare A MANO una volta sola:  ./firewall.sh
# Regole (UFW):
#   - in entrata tutto bloccato, in uscita tutto permesso
#   - SSH permesso con limite ai tentativi (per non chiudersi fuori)
#   - Minecraft Java 25565/tcp, Bedrock 19132/udp e mappa web 8080/tcp
#     solo dall'interfaccia tailscale0, se Tailscale e' presente
#   - RCON (25575) non viene aperto: si usa solo da questa macchina
# playit.gg non ha bisogno di porte aperte: il suo programma si collega verso
# l'esterno e passa i giocatori al server dall'interno del PC (127.0.0.1).
# Con online-mode=false il plugin di login (AuthMe) deve restare attivo.
set -euo pipefail

INTERFACCIA="${TAILSCALE_IF:-tailscale0}"

TAILSCALE=false
ip link show "$INTERFACCIA" >/dev/null 2>&1 && TAILSCALE=true
command -v ufw >/dev/null 2>&1 || sudo apt install -y ufw

echo "Sto per applicare queste regole con UFW:"
echo "  - blocco di tutte le connessioni in entrata, tranne:"
echo "  - SSH (22/tcp) con limite ai tentativi"
$TAILSCALE && echo "  - 25565/tcp, 19132/udp e 8080/tcp solo da $INTERFACCIA"
echo "Si entra solo tramite playit.gg$($TAILSCALE && echo " o Tailscale"): chi usa l'IP"
echo "di casa (192.168.x.x) non potra' piu' connettersi."
read -r -p "Procedo? [s/N] " risposta
[[ "$risposta" =~ ^[sS]$ ]] || { echo "Annullato."; exit 0; }

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit OpenSSH 2>/dev/null || sudo ufw limit 22/tcp
if $TAILSCALE; then
  sudo ufw allow in on "$INTERFACCIA" to any port 25565 proto tcp comment 'Minecraft Java'
  sudo ufw allow in on "$INTERFACCIA" to any port 19132 proto udp comment 'Minecraft Bedrock'
  sudo ufw allow in on "$INTERFACCIA" to any port 8080 proto tcp comment 'Mappa web'
fi
sudo ufw --force enable
sudo ufw status verbose
