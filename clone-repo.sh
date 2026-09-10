#!/bin/bash

# ======================================================
#  Docker Auto-Install Script
#  Features:
#  - Interactive: Asks user for location (Iran/Global)
#  - Auto-detect OS (Ubuntu/Debian)
#  - Install Docker & Docker Compose (latest)
#  - Configure Iranian mirrors if selected
#  - Idempotent: Safe to run multiple times
# ======================================================

set -e

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Functions ----------
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------- Check Root ----------
if [ "$EUID" -ne 0 ]; then
  log_error "Please run as root (use sudo)."
  exit 1
fi

# ---------- Detect OS ----------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    log_error "This script supports Ubuntu and Debian only. Detected: $OS"
    exit 1
fi

log_success "Detected OS: $OS $VER"

# ---------- Ask User: Iran or Global? ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Server Location${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "Are you installing on a server INSIDE Iran or OUTSIDE Iran?"
echo ""
echo "  1) Iran (use Iranian mirrors for faster & unrestricted access)"
echo "  2) Global (use official Docker repositories)"
echo ""
read -p "Enter choice [1 or 2]: " LOCATION
echo ""

case $LOCATION in
    1)
        SERVER_LOCATION="iran"
        log_info "Selected: Iran (Iranian mirrors will be configured)"
        ;;
    2)
        SERVER_LOCATION="global"
        log_info "Selected: Global (Official Docker repos)"
        ;;
    *)
        log_error "Invalid choice. Please run again and select 1 or 2."
        exit 1
        ;;
esac

# ---------- Install Dependencies ----------
log_info "Installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common > /dev/null 2>&1
log_success "Prerequisites installed."

# ---------- Remove Old Docker Versions ----------
log_info "Removing any old Docker versions..."
apt-get remove -y -qq docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose > /dev/null 2>&1 || true
apt-get autoremove -y -qq > /dev/null 2>&1 || true
log_success "Old versions removed."

# ---------- Install Docker ----------
if [ "$SERVER_LOCATION" = "global" ]; then
    # ---------- Global: Official Docker Repo ----------
    log_info "Adding official Docker GPG key and repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    log_info "Installing Docker Engine, CLI, containerd, Buildx, and Compose plugin..."
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    log_success "Docker installed from official repositories."

else
    # ---------- Iran: Use Iranian Mirror for Docker Packages ----------
    log_info "Configuring Docker installation from Iranian mirror..."

    # Use the official Docker GPG key (can be fetched via mirror if needed, but GPG key is not geo-blocked usually)
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || \
      curl -fsSL https://mirror.arvancloud.ir/docker-ce/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Use an Iranian mirror for Docker packages
    # ArvanCloud is a popular and reliable mirror. You can change this to another mirror if you prefer.
    DOCKER_MIRROR="https://mirror.arvancloud.ir/docker-ce/linux/$OS"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_MIRROR \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    log_info "Installing Docker Engine, CLI, containerd, Buildx, and Compose plugin from mirror..."
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    log_success "Docker installed from Iranian mirror."
fi

# ---------- Configure Docker Daemon (Mirrors & Log Rotation) ----------
log_info "Configuring Docker daemon..."

# Backup existing daemon.json if it exists
if [ -f /etc/docker/daemon.json ]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%s)
    log_info "Backed up existing daemon.json"
fi

# Create daemon.json
if [ "$SERVER_LOCATION" = "iran" ]; then
    # Iranian registry mirrors (popular and reliable ones)
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.arvancloud.ir",
    "https://docker.iranserver.com",
    "https://docker.kernel.ir",
    "https://focker.ir"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    log_success "Configured Iranian Docker registry mirrors."
else
    # Global: Only log rotation, no mirror needed
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    log_success "Configured Docker log rotation."
fi

# ---------- Restart Docker ----------
log_info "Restarting Docker service..."
systemctl daemon-reload
systemctl enable docker > /dev/null 2>&1
systemctl restart docker
sleep 2

# ---------- Verify Installation ----------
log_info "Verifying installation..."
if docker --version > /dev/null 2>&1; then
    DOCKER_VER=$(docker --version)
    log_success "Docker installed: $DOCKER_VER"
else
    log_error "Docker installation failed!"
    exit 1
fi

if docker compose version > /dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version)
    log_success "Docker Compose installed: $COMPOSE_VER"
else
    log_error "Docker Compose installation failed!"
    exit 1
fi

# Test Docker
log_info "Running hello-world test..."
if docker run --rm hello-world > /dev/null 2>&1; then
    log_success "Docker is working correctly!"
else
    log_warn "hello-world test failed. This might be due to network issues."
fi

# ---------- Show Status ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "Docker version: $(docker --version)"
echo "Compose version: $(docker compose version)"
echo ""
echo "Daemon configuration (/etc/docker/daemon.json):"
cat /etc/docker/daemon.json
echo ""
echo "Docker service status:"
systemctl is-active docker && echo "  -> active (running)" || echo "  -> not running"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  docker ps                # List running containers"
echo "  docker compose up -d     # Start services from docker-compose.yml"
echo "  docker system df         # Check Docker disk usage"
echo "  docker system prune -a   # Clean unused data"
echo ""
log_success "All done! Enjoy Docker. 🐳"