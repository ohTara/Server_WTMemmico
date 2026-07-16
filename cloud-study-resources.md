# 📥 Guida passo-passo: Installazione delle risorse per studi di Cloud Specialist (Ubuntu/Debian)

Questa guida ti porta da un sistema “pulito” (nessun tool di cloud preinstallato) a un ambiente pronto per laboratori AWS, Azure, GCP, Terraform, Kubernetes e containerizzazione con Podman/Docker.  
Ogni blocco può essere copiato‑incollato nel terminale **come utente normale**; i comandi che richiedono privilegi di root sono preceduti da `sudo`.

---

## 🛠️ 0. Preparazione di base

```bash
# Aggiorna l'indice dei pacchetti e upgradera quelli installati
sudo apt-get update && sudo apt-get upgrade -y

# Installa utility essenziali
sudo apt-get install -y curl wget gnupg2 lsb-release ca-certificates \
                       software-properties-common unzip zip git \
                       vim-tiny   # editor leggero, sostituibile con nano/vim
```

Verifica:
```bash
git --version
curl --version
```

---

## ☁️ 1. AWS Command Line Interface (CLI)

```bash
# 1.1. Scarica il bundle ufficiale (versione 2)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 1.2. Verifica
aws --version

# 1.3. Configura profilo (richiede Access Key/Secret Key)
# aws configure   # eseguilo quando hai le credenziali
```

---

## 🔷 2. Azure Command Line Interface (CLI)

```bash
# 2.1. Aggiungi il repository Microsoft
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

# 2.2. Aggiorna e installa
sudo apt-get update
sudo apt-get install -y azure-cli

# 2.3. Verifica
az --version

# 2.4. Login (interactive)
# az login
```

---

## 🌐 3. Google Cloud SDK (gcloud)

```bash
# 3.1. Aggiungi il pacchetto chiave di Google
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# 3.2. Aggiungi il repository
echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# 3.3. Aggiorna e installa
sudo apt-get update
sudo apt-get install -y google-cloud-sdk

# 3.4. Verifica
gcloud --version

# 3.5. Inizializza (richiede progetto GCP)
# gcloud init
```

---

## 🏗️ 4. Terraform (Infrastructure as Code)

```bash
# 4.1. Aggiungi la chiave GPG ufficiale di HashiCorp
wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 4.2. Aggiungi il repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list

# 4.3. Aggiorna e installa
sudo apt-get update
sudo apt-get install -y terraform

# 4.4. Verifica
terraform --version
```

---

## ⚙️ 5. kubectl (Kubernetes CLI)

```bash
# 5.1. Scarica l'ultima versione stabile
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# 5.2. Rendi eseguibile e spostalo in PATH
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# 5.3. Verifica
kubectl version --client
```

---

## 🐳 6. Container Engine: Podman (daemonless, rootless) – oppure Docker

### 6.1. Podman (scelta consigliata per ambienti low‑RAM)

```bash
# Su Ubuntu 24.04 il pacchetto è già nei repo ufficiali
sudo apt-get install -y podman podman-docker

# Verifica
podman --version
# Test semplicissimo
podman run --rm hello-world
```

### 6.2. (Opzionale) Docker – se preferisci

```bash
# Aggiungi il repo ufficiale Docker
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verifica
docker --version
docker run --rm hello-world
```

> **Nota**: Per usare Docker senza `sudo` aggiungi il tuo utente al gruppo `docker`:
> ```bash
> sudo usermod -aG docker $USER
> newgrp docker   # oppure logout/login
> ```

---

## 📦 7. Altri tool utili per studi cloud

| Tool | Installazione | Verifica |
|------|---------------|----------|
| **jq** (JSON processor) | `sudo apt-get install -y jq` | `jq --version` |
| **yq** (YAML processor) | `sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq` | `yq --version` |
| **httpie** (client HTTP friendly) | `sudo apt-get install -y httpie` | `http --version` |
| **ansible** (automazione) | `sudo apt-get install -y ansible` | `ansible --version` |
| **helm** (Kubernetes package manager) | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash` | `helm version` |
| **terraform-docs** (genera documentazione da file .tf) | `curl -Lo terraform-docs.tar.gz https://github.com/terraform-docs/terraform-docs/releases/latest/download/terraform-docs-linux-amd64.tar.gz && tar -xzf terraform-docs.tar.gz && sudo mv terraform-docs /usr/local/bin/` | `terraform-docs --version` |
| **tflint** (linter Terraform) | `curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash` | `tflint --version` |
| **kubectx / kubens** (switch context/namespace) | `sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx && sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx && sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens` | `kubectx -h` |

---

## 🧪 8. Verifica finale dell’ambiente

```bash
# Versione di tutti i tool principali
echo "=== AWS ===" && aws --version
echo "=== Azure ===" && az --version
echo "=== GCP ===" && gcloud --version
echo "=== Terraform ===" && terraform --version
echo "=== kubectl ===" && kubectl version --client --short
echo "=== Podman ===" && podman --version
echo "=== Docker (se installato) ===" && docker --version 2>/dev/null || echo "Docker non installato"
echo "=== jq ===" && jq --version
echo "=== yq ===" && yq --version
echo "=== httpie ===" && http --version
```

Se tutti i comandi restituiscono una versione senza errori, il tuo laptop è pronto per:

* Laboratori AWS (EC2, S3, IAM, Lambda, …)  
* Laboratori Azure (VM, Storage, Functions, …)  
* Laboratori GCP (Compute Engine, Cloud Storage, Cloud Functions, …)  
* Esercizi di IaC con Terraform (moduli, workspace, state backend)  
* Sperimentazione con Kubernetes (kind, minikube, o cluster gestiti)  
* Test di containerizzazione con Podman (rootless, ideale per laptop con <2 GB RAM)  

---

## 📚 Prossimi passi consigliati

1. **Creare una cartella di lavoro** per i tuoi lab:  
   ```bash
   mkdir -p ~/cloud-labs/{aws,azure,gcp,terraform,k8s}
   ```
2. **Clonare repository di esempio** (es: Terraform AWS examples):  
   ```bash
   git clone https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git ~/cloud-labs/terraform/aws-ec2
   ```
3. **Seguire le guide ufficiali** dei provider per i primi esercizi (Getting Started).  
4. **Usare Podman per far girare il tuo server Minecraft** (vedi il file `minecraft-fix-protocol.md` già creato).  
5. **Sperimentare con Terraform** per deployare risorse su un account gratuito AWS/Azure/GCP.  

---

> 📝 **File salvato in:** `C:\Users\luca.tarallo\Documents\cloud-study-resources.md`  
> 🔗 **Contesto completo:** vedi anche la guida all’homeserver in [`GUIDA-SERVER-CLOUD.md`](GUIDA-SERVER-CLOUD.md) e il fix per Minecraft in [`minecraft-fix-protocol.md`](minecraft-fix-protocol.md).

Buono studio e buon divertimento con il tuo laboratorio cloud personale! 🚀