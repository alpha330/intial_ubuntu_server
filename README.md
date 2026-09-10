🚀 VPS Setup Scripts
A collection of production-ready, interactive bash scripts for setting up and managing Ubuntu/Debian servers. Designed specifically for Iranian servers with built-in support for local mirrors, but works globally too.

📋 Table of Contents
Overview

Features

Available Scripts

Quick Start

Detailed Usage

1. Docker Installation Script

2. GitHub Repository Clone Script

Requirements

Troubleshooting

Security Notes

FAQ

License

🎯 Overview
This repository contains a set of battle-tested bash scripts to automate common server setup tasks. Each script is:

Interactive — Guides you through the process step-by-step

Idempotent — Safe to run multiple times

Smart — Detects your OS, checks for existing installations, and handles edge cases

Iran-friendly — Optional Iranian mirror support for faster, unrestricted access

Zero-config — Just run with curl and answer a few questions

These scripts were built to solve real-world problems: sanctions blocking Docker downloads, disk space filling up from Docker logs, repetitive setup tasks across multiple servers, and more.

✨ Features
Feature	Description
🌍 Geo-aware	Asks whether your server is inside or outside Iran and configures mirrors accordingly
🐳 Latest Docker	Installs Docker Engine, CLI, containerd, Buildx, and Compose plugin
📦 Full Dependencies	Installs Git, curl, wget, unzip, and other essentials
🔐 Private Repo Support	Handles Personal Access Tokens for private GitHub repositories
📝 Log Rotation	Pre-configures Docker log rotation to prevent disk bloat
🎨 Colored Output	Clear, color-coded messages for easy reading
🛡️ Safe	Backs up existing configs, validates inputs, and checks permissions
🚀 One-liner	Run directly via curl — no need to clone anything first
📜 Available Scripts
Script	Purpose	Typical Use Case
install-docker.sh	Installs Docker + Compose with optional Iranian mirrors	Fresh server that needs Docker
clone-repo.sh	Clones a GitHub repo to /opt with dependencies	Deploy a project from GitHub
⚡ Quick Start
Docker Installation
bash
bash <(curl -fsSL https://github.com/alpha330/intial_ubuntu_server/blob/main/install-docker.sh)
Clone a GitHub Repository
bash
bash <(curl -fsSL https://github.com/alpha330/intial_ubuntu_server/blob/main/clone-repo.sh)
Note: Replace YOUR_USERNAME/YOUR_REPO with your actual GitHub repository path.

📖 Detailed Usage
1. Docker Installation Script
File: install-docker.sh

What It Does
Verifies you're running as root

Detects your OS (Ubuntu or Debian)

Asks whether your server is inside or outside Iran

Removes any old Docker versions

Installs Docker from Iranian mirrors (if inside Iran) or official repos (if outside)

Configures /etc/docker/daemon.json with:

Iranian registry mirrors (if inside Iran)

Log rotation (10 MB per file, 3 files max)

Enables and starts the Docker service

Verifies the installation with a hello-world test

Interactive Prompts
text
Are you installing on a server INSIDE Iran or OUTSIDE Iran?

  1) Iran (use Iranian mirrors for faster & unrestricted access)
  2) Global (use official Docker repositories)

Enter choice [1 or 2]:
What Gets Installed
docker-ce — Docker Engine

docker-ce-cli — Docker CLI

containerd.io — Container runtime

docker-buildx-plugin — Buildx plugin

docker-compose-plugin — Compose v2 plugin

After Installation
bash
docker --version              # Verify Docker
docker compose version        # Verify Compose
docker run hello-world        # Test connectivity
docker ps                     # List running containers
docker system df              # Check disk usage
Iranian Registry Mirrors
When you select Iran, the following mirrors are configured in /etc/docker/daemon.json:

https://docker.arvancloud.ir

https://docker.iranserver.com

https://docker.kernel.ir

https://focker.ir

These allow you to pull Docker images without hitting sanctions-related blocks.

2. GitHub Repository Clone Script
File: clone-repo.sh

What It Does
Verifies you're running as root

Detects your OS

Installs Git, curl, wget, unzip, and certificates

Asks for your GitHub username, repository name, and branch

Detects whether the repo is public or private

Clones the repo into /opt/<repo-name>

Optionally starts the project with Docker Compose (if a compose file is found)

Interactive Prompts
text
Enter your GitHub username: alimahmoodi22
Enter repository name (e.g., my-project): alimahmoodi-site
Enter branch name (default: main): main
Is the repository private? (y/n): n
Private Repository Setup
If your repository is private, the script asks for a Personal Access Token (PAT). Here's how to create one:

Go to https://github.com/settings/tokens

Click Generate new token (classic)

Give it a descriptive name (e.g., VPS Clone)

Select the repo scope

Click Generate token and copy it immediately (it's shown only once)

⚠️ Important: GitHub no longer supports password authentication for Git operations. You must use a Personal Access Token.

Target Directory
The repository is cloned into:

text
/opt/<repository-name>
For example, cloning alimahmoodi-site results in /opt/alimahmoodi-site.

After Cloning
bash
cd /opt/<repo-name>
git status                    # Check status
git pull origin main          # Pull latest changes
docker compose up -d          # Start services (if compose file exists)
🛠️ Requirements
Requirement	Details
OS	Ubuntu 20.04+, Debian 11+ (or compatible)
Architecture	x86_64 / arm64
Privileges	Root (or sudo)
Network	Internet access to GitHub and/or Docker mirrors
Disk	At least 2 GB free for Docker installation
🐛 Troubleshooting
Docker installation fails behind sanctions
Symptom: curl: (7) Failed to connect to download.docker.com

Solution: Run the script and select Iran when prompted. This uses Iranian mirrors.

Repository not found when pushing/cloning
Symptom: ERROR: Repository not found.

Cause: The repository doesn't exist on GitHub, or your token lacks the repo scope.

Solution:

Verify the repository name and username

For private repos, ensure your token has the repo scope

Create the repository on GitHub first if it doesn't exist

bad interpreter: Text file busy
Symptom: ./script.sh: /bin/bash: bad interpreter: Text file busy

Cause: The script file is being edited or locked.

Solution:

bash
rm script.sh
# recreate the file
chmod +x script.sh
bash script.sh
[[: not found error
Symptom: script.sh: 46: [[: not found

Cause: The script is being run with sh instead of bash.

Solution:

bash
bash script.sh
# OR
chmod +x script.sh && ./script.sh
Docker logs filling up the disk
Symptom: Disk usage at 100%, /var/lib/docker/containers is huge.

Solution: The install-docker.sh script configures log rotation automatically. If you already have Docker installed:

bash
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
🔐 Security Notes
Tokens: Never commit Personal Access Tokens to Git. Use environment variables or a secrets manager.

Root Access: These scripts require root. Review the code before running on production servers.

Mirrors: Iranian mirrors are third-party services. While generally reliable, treat them as you would any external dependency.

Backups: The Docker script backs up /etc/docker/daemon.json before modifying it.

❓ FAQ
Can I use these scripts outside Iran?
Yes! Just select Global when prompted during the Docker installation. The scripts work anywhere.

Do I need to install Git manually?
No. The clone-repo.sh script installs Git automatically if it's missing.

What if my repository uses a branch other than main?
The script asks for the branch name. Just enter it when prompted (e.g., master, develop, production).

Can I run these scripts multiple times?
Yes. Both scripts are idempotent — they detect existing installations and skip redundant steps. The Docker script even backs up your daemon.json before overwriting it.

How do I update a cloned repository?
bash
cd /opt/<repo-name>
git pull origin <branch>
How do I uninstall Docker?
bash
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo rm /etc/docker/daemon.json
Does the Docker script work on ARM servers?
Yes. The script uses dpkg --print-architecture to detect your architecture automatically.

📁 Repository Structure
text
.
├── README.md
├── install-docker.sh       # Docker installation script
├── clone-repo.sh           # GitHub clone script
└── LICENSE
🤝 Contributing
Contributions are welcome! If you have ideas for improvements or additional scripts, feel free to open an issue or submit a pull request.

📄 License
This project is licensed under the MIT License. See the LICENSE file for details.

🙏 Acknowledgments
Docker's official installation documentation

Iranian mirror providers: ArvanCloud, IranServer, Kernel, Focker

The open-source community for continuous inspiration