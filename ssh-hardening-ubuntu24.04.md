# 🔐 Hardening SSH su Ubuntu 24.04 – Correzione dei comandi

Hai provato a modificare `/etc/ssh/sshd_config` e a riavviare il servizio senza i privilegi di amministratore, quindi hai ottenuto gli errori  
`Permission denied` da `sed` e l’impossibilità di acquisire il lock di `dpkg`.  
Su Ubuntu il servizio SSH si chiama **`ssh`** (non `sshd`) e qualsiasi modifica a file sotto `/etc` o l’installazione di pacchetti richiede `sudo`.

Di seguito trovi il blocco corretto da eseguire **una sola volta** (copia‑incolla intero nel terminale). Dopo l’). Dopo l’esecuzione, il server SSH sarà più, il server SSH sarà più sicuro e potrai proseguire con la configurazione dell’homeserver.

---

```bash
# 1. Aggiorna l'indice dei pacchetti (opzionale ma consigliato)
sudo apt-get update

# 2. Installa i pacchetti per la qualità delle password e il blocco dopo tentativi falliti
sudo apt-get install -y libpam-pwquality libpam-tally2

# 3. Hardening di /etc/ssh/sshd_config
#    - Disabilita login root diretto
#    - Disabilita autenticazione con password
#    - Limita a 3 tentativi di autenticazione
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config

# 4. (Facoltativo) Abilita l'autenticazione con chiave pubblica se non lo è già
#    Assicurati che la linea seguente sia presente e non commentata:
#    PubkeyAuthentication yes
sudo grep -q '^PubkeyAuthentication' /etc/ssh/sshd_config || \
    echo 'PubkeyAuthentication yes' | sudo tee -a /etc/ssh/sshd_config

# 5. Ricarica la configurazione di SSH (il servizio
sudo systemctl reload ssh   # su Ubuntu il servizio si chiama "ssh"
# oppure, se preferisci un restart completo:
# sudo systemctl restart ssh

# 6. Verifica che il servizio sia attivo e in ascolto sulla porta 22
systemctl status ssh --no-pager
ss -tlnp | grep ':22'
```

### 📌 Cosa fa ogni passaggio

| Passo | Descrizione |
|------|--------------|
| **1** | Aggiorna la lista dei pacchetti così che `apt-get install` trovi le versioni più recenti. |
| **2** | Installa `libpam-pwquality` (policy di complessità password) e `libpam-tally2` (blocco dopo troppi tentativi falliti). |
| **3** | Modifica direttamente il file di configurazione SSH con `sudo sed`. Le espressioni regolari gestiscono sia le linee già commentate (`#`) che quelle non commentate. |
| **4** | Assicura che l’autenticazione con chiave pubblica sia abilitata (necessario se disabiliti le password). |
| **5** | Ricarica il daemon SSH senza interrompere le connessioni esistenti. |
| **6** | Controlla che il servizio sia `active (running)` e che ascolti sulla porta TCP 22. |

---

## ✅ Verifica finale

Dopo aver eseguito il blocco sopra, dovresti vedere qualcosa di simile:

```
$ systemctl status ssh --no-pager
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/lib/systemd/system/ssh.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2026-07-16 10:12:34 CEST; 5min ago
   Main PID: 1234 (sshd)
      Tasks: 1 (limit: 4587)
     Memory: 4.2M
        CPU: 120ms
     CGroup: /system.slice/ssh.service
             └─1234 /usr/sbin/sshd -D

$ ss -tlnp | grep ':22'
LISTEN 0      128          0.0.0.0:22          0.0.0.0:*    users:(("sshd",pid=1234,fd=3))
LISTEN 0      128             [::]:22             [::]:*    users:(("sshd",pid=1234,fd=3))
```

Se il servizio è attivo e in ascolto sulla porta 22, l’hardening è stato applicato correttamente.

---

## 🚀 Prossimi passi (facoltativi)

1. **Testa l’accesso con chiave SSH** da un’altra macchina (assicurati di avere la tua chiave pubblica in `~/.ssh/authorized_keys` sull’utente `luca`).  
2. **Disabilita definitivamente l’accesso con password** (se non l’hai già fatto) e verifica che l’accesso tramite password venga rifiutato.  
3. **Prosegui con la configurazione del server Minecraft** (se ancora necessario) usando lo script corretto che ti ho fornito nei messaggi precedenti – ora che SSH è sicuro, puoi continuare a lavorare sull’homeserver senza preoccupazioni.

---

> 📝 **File salvato in:** `C:\Users\luca.tarallo\Documents\ssh-hardening-ubuntu24.04.md`  
> 🔗 **Contesto completo:** vedi anche la guida all’homeserver in [`GUIDA-SERVER-CLOUD.md`](GUIDA-SERVER-CLOUD.md) e il fix per Minecraft in [`minecraft-fix-protocol.md`](minecraft-fix-protocol.md).

Hai ora un SSH più sicuro e puoi proseguire serenamente con la configurazione del tuo laboratorio cloud domestico. Buon lavoro! 🚀