# 🚀 VPS Setup Scripts

A collection of production-ready, interactive bash scripts for setting up and managing Ubuntu/Debian servers. Designed specifically for Iranian servers with built-in support for local mirrors, but works globally too.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Available Scripts](#-available-scripts)
- [Quick Start](#-quick-start)
- [Detailed Usage](#-detailed-usage)
  - [1. Docker Installation Script](#1-docker-installation-script)
  - [2. GitHub Repository Clone Script](#2-github-repository-clone-script)
  - [3. SSL Certificate Installer](#3-ssl-certificate-installer)
- [Requirements](#️-requirements)
- [Troubleshooting](#-troubleshooting)
- [Security Notes](#-security-notes)
- [FAQ](#-faq)
- [Repository Structure](#-repository-structure)
- [Contributing](#-contributing)
- [License](#-license)
- [Support](#-support)

---

## 🎯 Overview

This repository contains a set of battle-tested bash scripts to automate common server setup tasks. Each script is:

- **Interactive** — Guides you through the process step-by-step
- **Idempotent** — Safe to run multiple times
- **Smart** — Detects your OS, checks for existing installations, and handles edge cases
- **Iran-friendly** — Optional Iranian mirror support for faster, unrestricted access
- **Resilient** — Fallback chains for mirrors (if one fails, tries the next)
- **Zero-config** — Just run with `curl` and answer a few questions

These scripts were built to solve real-world problems: sanctions blocking Docker downloads, disk space filling up from Docker logs, repetitive setup tasks across multiple servers, SSL certificate acquisition, and more.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🌍 **Geo-aware** | Asks whether your server is inside or outside Iran and configures mirrors accordingly |
| 🐳 **Latest Docker** | Installs Docker Engine, CLI, containerd, Buildx, and Compose plugin |
| 🔁 **Mirror Fallback** | Tries multiple Iranian mirrors; falls back to official repos if all fail |
| 📦 **Full Dependencies** | Installs Git, curl, wget, unzip, Certbot, and other essentials |
| 🔐 **Private Repo Support** | Handles Personal Access Tokens for private GitHub repositories |
| 🔒 **SSL Automation** | Obtains and auto-renews Let's Encrypt certificates with Certbot |
| 🚦 **Port Management** | Detects and offers to stop services occupying port 80 |
| 📝 **Log Rotation** | Pre-configures Docker log rotation to prevent disk bloat |
| 🎨 **Colored Output** | Clear, color-coded messages for easy reading |
| 🛡️ **Safe** | Backs up existing configs, validates inputs, and checks permissions |
| 🚀 **One-liner** | Run directly via `curl` — no need to clone anything first |

---

## 📜 Available Scripts

| Script | Purpose | Typical Use Case |
|--------|---------|------------------|
| `install-docker.sh` | Installs Docker + Compose with resilient Iranian mirror fallback | Fresh server that needs Docker |
| `clone-repo.sh` | Clones a GitHub repo to `/opt` with dependencies | Deploy a project from GitHub |
| `install-ssl.sh` | Obtains SSL certificate from Let's Encrypt via Certbot | Secure a domain with HTTPS |

---

## ⚡ Quick Start

All scripts can be run directly via `curl` — no need to clone the repository first.

### Docker Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alpha330/intial_ubuntu_server/main/install-docker.sh)
```

### Clone a GitHub Repository

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alpha330/intial_ubuntu_server/main/clone-repo.sh)
```

### Install SSL Certificate

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alpha330/intial_ubuntu_server/main/install-ssl.sh)
```

> **Note:** All commands assume the repository is at `alpha330/intial_ubuntu_server`. Replace the path if you fork it.

---

## 📖 Detailed Usage

### 1. Docker Installation Script

**File:** `install-docker.sh`

#### What It Does

1. Verifies you're running as root
2. Detects your OS (Ubuntu or Debian)
3. Asks whether your server is **inside** or **outside** Iran
4. Removes any old Docker versions
5. **Tries multiple Iranian mirrors in order** (IranServer, MobinHost, Kernel, Shatel, ArvanCloud)
6. **Falls back to official Docker repos** if all Iranian mirrors fail
7. **Falls back to distro default repos** (`docker.io`) as a last resort
8. Configures `/etc/docker/daemon.json` with:
   - Iranian registry mirrors (if inside Iran)
   - Log rotation (10 MB per file, 3 files max)
9. Enables and starts the Docker service
10. Verifies the installation with a `hello-world` test

#### Interactive Prompts

```
Are you installing on a server INSIDE Iran or OUTSIDE Iran?

  1) Iran (use Iranian mirrors for faster & unrestricted access)
  2) Global (use official Docker repositories)

Enter choice [1 or 2]:
```

#### What Gets Installed

- `docker-ce` — Docker Engine
- `docker-ce-cli` — Docker CLI
- `containerd.io` — Container runtime
- `docker-buildx-plugin` — Buildx plugin
- `docker-compose-plugin` — Compose v2 plugin

#### Resilient Mirror Fallback Chain

When you select **Iran**, the script tries the following mirrors in order:

| Priority | Mirror | URL |
|----------|--------|-----|
| 1 | IranServer | `https://mirror.iranserver.com/docker-ce/linux/...` |
| 2 | MobinHost | `https://mirror.mobinhost.com/docker-ce/linux/...` |
| 3 | Kernel | `https://mirror.kernel.ir/docker-ce/linux/...` |
| 4 | Shatel | `https://mirror.shatel.ir/docker-ce/linux/...` |
| 5 | ArvanCloud | `https://mirror.arvancloud.ir/docker-ce/linux/...` |

If **all** mirrors fail, the script automatically falls back to:

1. **Official Docker Repo** (`download.docker.com`)
2. **Distro Default Repo** (`docker.io` from Ubuntu/Debian)

#### After Installation

```bash
docker --version              # Verify Docker
docker compose version        # Verify Compose
docker run hello-world        # Test connectivity
docker ps                     # List running containers
docker system df              # Check disk usage
```

#### Iranian Registry Mirrors

When you select **Iran**, the following mirrors are configured in `/etc/docker/daemon.json`:

- `https://docker.iranserver.com`
- `https://docker.kernel.ir`
- `https://docker.arvancloud.ir`
- `https://focker.ir`

These allow you to pull Docker images without hitting sanctions-related blocks.

---

### 2. GitHub Repository Clone Script

**File:** `clone-repo.sh`

#### What It Does

1. Verifies you're running as root
2. Detects your OS
3. Installs Git, curl, wget, unzip, and certificates
4. Asks for your GitHub username, repository name, and branch
5. Detects whether the repo is public or private
6. Clones the repo into `/opt/<repo-name>`
7. Optionally starts the project with Docker Compose (if a compose file is found)

#### Interactive Prompts

```
Enter your GitHub username: alpha330
Enter repository name (e.g., my-project): intial_ubuntu_server
Enter branch name (default: main): main
Is the repository private? (y/n): n
```

#### Private Repository Setup

If your repository is private, the script asks for a **Personal Access Token (PAT)**. Here's how to create one:

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Give it a descriptive name (e.g., `VPS Clone`)
4. Select the **`repo`** scope
5. Click **Generate token** and copy it immediately (it's shown only once)

> ⚠️ **Important:** GitHub no longer supports password authentication for Git operations. You **must** use a Personal Access Token.

#### Target Directory

The repository is cloned into:

```
/opt/<repository-name>
```

For example, cloning `intial_ubuntu_server` results in `/opt/intial_ubuntu_server`.

#### After Cloning

```bash
cd /opt/<repo-name>
git status                    # Check status
git pull origin main          # Pull latest changes
docker compose up -d          # Start services (if compose file exists)
```

---

### 3. SSL Certificate Installer

**File:** `install-ssl.sh`

#### What It Does

1. Verifies you're running as root
2. Detects your OS
3. Checks if **Certbot** is installed; installs it if missing
4. Asks for your **domain** and **email**
5. Checks if **port 80** is available
6. If port 80 is occupied, **identifies the service** (nginx, apache2, docker, etc.) and offers to stop it temporarily
7. Asks which **validation method** to use:
   - **Standalone** — Certbot runs a temporary web server on port 80
   - **Webroot** — Places challenge files in your existing webroot
   - **Nginx** — Certbot auto-configures Nginx
   - **DNS** — Manual TXT record (supports wildcard certificates)
8. Obtains the SSL certificate from **Let's Encrypt**
9. Configures **auto-renewal** (systemd timer or cron job)
10. Tests renewal with a dry-run

#### Interactive Prompts

```
Enter your domain (e.g., example.com): example.com
Enter your email (for Let's Encrypt notifications): admin@example.com

Checking port 80 availability...
[WARNING] Port 80 is already in use!
Process occupying port 80:
  LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=1234,fd=6))

Do you want to stop this service temporarily? (y/n): y
[INFO] Stopping nginx...
[SUCCESS] nginx stopped.

How would you like to validate domain ownership?

  1) Standalone (Certbot runs a temporary web server on port 80)
  2) Webroot (Place files in your existing web server's root)
  3) Nginx (Certbot automatically configures Nginx)
  4) DNS (Manual TXT record - for wildcard certs or port 80 blocked)

Enter choice [1-4]: 1
```

#### Validation Methods Explained

| Method | Best For | Requirements |
|--------|----------|--------------|
| **Standalone** | No web server running | Port 80 free |
| **Webroot** | Nginx/Apache with known webroot | Write access to webroot, port 80 open |
| **Nginx** | Nginx running, want auto-config | Nginx installed, port 80 open |
| **DNS** | Wildcard certs, port 80 blocked | Access to DNS management |

#### Certificate Location

After successful acquisition, certificates are stored at:

```
/etc/letsencrypt/live/<domain>/
├── fullchain.pem    # Full certificate chain (use this in your web server)
├── privkey.pem      # Private key
├── cert.pem         # Certificate only
└── chain.pem        # Intermediate chain
```

#### Auto-Renewal

The script automatically sets up renewal via:

- **Systemd timer** (`certbot.timer`) if available
- **Cron job** (`/etc/cron.d/certbot-renew`) as fallback

Renewal runs **twice daily** and reloads Nginx on success.

#### Useful Certbot Commands

```bash
certbot certificates                    # List all certificates
certbot renew --dry-run                 # Test renewal
certbot renew                           # Force renewal
certbot delete --cert-name <domain>     # Delete a certificate
```

---

## 🛠️ Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 20.04+, Debian 11+ (or compatible) |
| **Architecture** | x86_64 / arm64 |
| **Privileges** | Root (or `sudo`) |
| **Network** | Internet access to GitHub, Docker mirrors, and Let's Encrypt |
| **Disk** | At least 2 GB free for Docker installation |
| **DNS** | Domain must point to your server's IP (A record) |
| **Port 80** | Must be reachable from the internet for HTTP-01 challenge |

---

## 🐛 Troubleshooting

### Docker installation fails behind sanctions

**Symptom:** `curl: (7) Failed to connect to download.docker.com`

**Solution:** Run the script and select **Iran** when prompted. This uses Iranian mirrors with automatic fallback.

---

### `503 Service Unavailable` from ArvanCloud mirror

**Symptom:** `W: Failed to fetch https://mirror.arvancloud.ir/... 503 Service Unavailable`

**Solution:** The script automatically tries other mirrors (IranServer, MobinHost, Kernel, Shatel) before falling back to official repos. If ArvanCloud is down, the script will skip it and use the next available mirror.

---

### `Repository not found` when pushing/cloning

**Symptom:** `ERROR: Repository not found.`

**Cause:** The repository doesn't exist on GitHub, or your token lacks the `repo` scope.

**Solution:**
1. Verify the repository name and username
2. For private repos, ensure your token has the `repo` scope
3. Create the repository on GitHub first if it doesn't exist

---

### `bad interpreter: Text file busy`

**Symptom:** `./script.sh: /bin/bash: bad interpreter: Text file busy`

**Cause:** The script file is being edited or locked.

**Solution:**
```bash
rm script.sh
# recreate the file
chmod +x script.sh
bash script.sh
```

---

### `[[: not found` error

**Symptom:** `script.sh: 46: [[: not found`

**Cause:** The script is being run with `sh` instead of `bash`.

**Solution:**
```bash
bash script.sh
# OR
chmod +x script.sh && ./script.sh
```

---

### Docker logs filling up the disk

**Symptom:** Disk usage at 100%, `/var/lib/docker/containers` is huge.

**Solution:** The `install-docker.sh` script configures log rotation automatically. If you already have Docker installed:

```bash
# Clear existing logs
sudo find /var/lib/docker/containers -name "*.log" -exec truncate -s 0 {} \;

# Apply log rotation
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker
```

---

### Certbot fails with "port 80 is already in use"

**Symptom:** `Problem binding to port 80: Could not bind to IPv4 or IPv6.`

**Cause:** Another service (nginx, apache2, docker) is using port 80.

**Solution:** The `install-ssl.sh` script detects this and offers to stop the service temporarily. If you prefer to keep the service running, use **Webroot** or **Nginx** validation method instead of **Standalone**.

---

### SSL certificate renewal fails

**Symptom:** `certbot renew` returns errors.

**Solution:**
```bash
# Check the log
sudo tail -100 /var/log/letsencrypt/letsencrypt.log

# Test renewal manually
sudo certbot renew --dry-run --verbose

# Check if port 80 is still reachable
curl -I http://<your-domain>/.well-known/acme-challenge/test
```

---

## 🔐 Security Notes

- **Tokens:** Never commit Personal Access Tokens to Git. Use environment variables or a secrets manager.
- **Root Access:** These scripts require root. Review the code before running on production servers.
- **Mirrors:** Iranian mirrors are third-party services. While generally reliable, treat them as you would any external dependency.
- **Backups:** The Docker script backs up `/etc/docker/daemon.json` before modifying it.
- **SSL Keys:** Private keys in `/etc/letsencrypt/live/` should be readable only by root.
- **Auto-Renewal:** Certbot certificates expire after 90 days. The script configures auto-renewal, but monitor it periodically.

---

## ❓ FAQ

### Can I use these scripts outside Iran?

Yes! Just select **Global** when prompted during the Docker installation. The scripts work anywhere.

### Do I need to install Git manually?

No. The `clone-repo.sh` script installs Git automatically if it's missing.

### What if my repository uses a branch other than `main`?

The script asks for the branch name. Just enter it when prompted (e.g., `master`, `develop`, `production`).

### Can I run these scripts multiple times?

Yes. All scripts are idempotent — they detect existing installations and skip redundant steps. The Docker script even backs up your `daemon.json` before overwriting it.

### How do I update a cloned repository?

```bash
cd /opt/<repo-name>
git pull origin <branch>
```

### How do I uninstall Docker?

```bash
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo rm /etc/docker/daemon.json
```

### Does the Docker script work on ARM servers?

Yes. The script uses `dpkg --print-architecture` to detect your architecture automatically.

### Can I get a wildcard SSL certificate?

Yes! Use the **DNS** validation method in `install-ssl.sh`. When prompted, choose wildcard mode. Note that you'll need to manually add a TXT record to your DNS.

### How often do Let's Encrypt certificates expire?

Every **90 days**. The script configures auto-renewal, so you shouldn't need to do anything. To verify auto-renewal is working:

```bash
sudo certbot renew --dry-run
```

### What if I use Cloudflare for DNS?

For automatic DNS validation with Cloudflare, you can install the Cloudflare plugin:

```bash
sudo apt install python3-certbot-dns-cloudflare
```

Then use `--dns-cloudflare` with a credentials file. Currently, the script uses manual DNS mode, but you can extend it.

---

## 📁 Repository Structure

```
.
├── README.md
├── install-docker.sh       # Docker installation script
├── clone-repo.sh           # GitHub clone script
├── install-ssl.sh          # SSL certificate installer
└── LICENSE
```

---

## 🤝 Contributing

Contributions are welcome! If you have ideas for improvements or additional scripts, feel free to open an issue or submit a pull request.

Some ideas for future scripts:

- `install-nginx.sh` — Nginx + reverse proxy setup
- `install-postgres.sh` — PostgreSQL with backups
- `setup-firewall.sh` — UFW + Fail2ban
- `install-nodejs.sh` — Node.js via NVM
- `backup-script.sh` — Automated backups to S3/rsync

---

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## 🙏 Acknowledgments

- Docker's official installation documentation
- Certbot / Let's Encrypt documentation
- Iranian mirror providers: ArvanCloud, IranServer, Kernel, Focker, MobinHost, Shatel
- The open-source community for continuous inspiration

---


<p align="center">
  <strong>Made with ❤️ for the Iranian DevOps community</strong>
</p>
