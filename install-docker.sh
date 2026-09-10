#!/bin/bash

# ======================================================
#  Docker Auto-Install Script (Resilient Mirror Fallback)
#  Features:
#  - Interactive: Asks user for location (Iran/Global)
#  - Auto-detect OS (Ubuntu/Debian)
#  - Tries multiple Iranian mirrors (fallback chain)
#  - Falls back to official Docker repos if mirrors fail
#  - Falls back to Ubuntu/Debian default repos as last resort
#  - Configure Iranian registry mirrors if selected
#  - Idempotent: Safe to run multiple times
# ======================================================

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

# NOTE: We intentionally do NOT use `set -e` here, because we want to
# continue on non-fatal errors (e.g., one mirror failing) and try alternatives.

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
    CODENAME=$VERSION_CODENAME
else
    log_error "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    log_error "This script supports Ubuntu and Debian only. Detected: $OS"
    exit 1
fi

log_success "Detected OS: $OS $VER ($CODENAME)"

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
apt-get update -qq || log_warn "apt-get update had warnings (continuing anyway)"
apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common > /dev/null 2>&1
log_success "Prerequisites installed."

# ---------- Remove Old Docker Versions ----------
log_info "Removing any old Docker versions..."
apt-get remove -y -qq docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose > /dev/null 2>&1 || true
apt-get autoremove -y -qq > /dev/null 2>&1 || true
log_success "Old versions removed."

# ---------- Helper: Fetch Docker GPG Key ----------
# Tries official Docker key, then a list of Iranian mirrors.
fetch_docker_gpg_key() {
    local KEY_PATH="/etc/apt/keyrings/docker.gpg"
    install -m 0755 -d /etc/apt/keyrings

    local key_urls=(
        "https://download.docker.com/linux/${OS}/gpg"
        "https://mirror.iranserver.com/docker-ce/linux/${OS}/gpg"
        "https://mirror.mobinhost.com/docker-ce/linux/${OS}/gpg"
        "https://mirror.kernel.ir/docker-ce/linux/${OS}/gpg"
        "https://mirror.arvancloud.ir/docker-ce/linux/${OS}/gpg"
    )

    for url in "${key_urls[@]}"; do
        log_info "Trying GPG key from: $url"
        if curl -fsSL --max-time 15 "$url" 2>/dev/null | gpg --dearmor -o "$KEY_PATH" 2>/dev/null; then
            if [ -s "$KEY_PATH" ]; then
                chmod a+r "$KEY_PATH"
                log_success "GPG key fetched from: $url"
                return 0
            fi
        fi
        log_warn "Failed to fetch GPG key from: $url"
    done

    return 1
}

# ---------- Helper: Test if an APT mirror is reachable ----------
# Performs a quick HTTP HEAD/GET to the InRelease file.
test_apt_mirror() {
    local base_url="$1"
    local test_url="${base_url}/dists/${CODENAME}/InRelease"
    if curl -fsSL --max-time 15 -o /dev/null "$test_url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ---------- Helper: Write Docker APT Source ----------
write_docker_source() {
    local mirror_base="$1"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${mirror_base} ${CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
}

# ---------- Helper: Attempt Full Docker Install from a Mirror ----------
# Returns 0 on success, 1 on failure.
try_install_docker_from_mirror() {
    local mirror_base="$1"
    local mirror_name="$2"

    log_info "Attempting to install Docker from: ${mirror_name}"
    log_info "Mirror base URL: ${mirror_base}"

    # Test reachability first
    if ! test_apt_mirror "$mirror_base"; then
        log_warn "Mirror ${mirror_name} is not reachable (InRelease check failed)."
        return 1
    fi

    # Write the source
    write_docker_source "$mirror_base"

    # Update APT (quietly, but don't die on warnings)
    if ! apt-get update -qq 2>/dev/null; then
        log_warn "apt-get update failed for ${mirror_name}."
        return 1
    fi

    # Try to install
    if apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1; then
        log_success "Docker installed successfully from: ${mirror_name}"
        return 0
    else
        log_warn "Package installation failed for ${mirror_name}."
        return 1
    fi
}

# ---------- Helper: Attempt Install from Ubuntu/Debian Default Repos ----------
try_install_docker_from_distro() {
    log_info "Falling back to distro default repositories (docker.io)..."

    # Remove any broken docker.list to avoid interference
    rm -f /etc/apt/sources.list.d/docker.list

    if ! apt-get update -qq 2>/dev/null; then
        log_warn "apt-get update failed for distro repos."
        return 1
    fi

    # Try to install distro-provided packages
    if apt-get install -y -qq docker.io docker-compose-v2 > /dev/null 2>&1; then
        log_success "Docker installed from distro default repositories (docker.io)."
        return 0
    fi

    # Some older distros use docker-compose (v1) instead of docker-compose-v2
    if apt-get install -y -qq docker.io docker-compose > /dev/null 2>&1; then
        log_success "Docker installed from distro default repositories (docker.io + docker-compose v1)."
        return 0
    fi

    log_warn "Distro default repository installation failed."
    return 1
}

# ---------- Install Docker ----------
INSTALL_SUCCESS=false
INSTALL_METHOD=""

# 1. Fetch GPG key (try official first, then mirrors)
if ! fetch_docker_gpg_key; then
    log_error "Could not fetch Docker GPG key from any source."
    log_warn "Will try distro default repositories as a last resort."
fi

if [ "$SERVER_LOCATION" = "global" ]; then
    # ---------- Global: Official Docker Repo ----------
    log_info "Installing Docker from official Docker repositories..."

    if try_install_docker_from_mirror "https://download.docker.com/linux/${OS}" "Official Docker"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="Official Docker Repo"
    fi

else
    # ---------- Iran: Try Iranian Mirrors in Order ----------
    log_info "Trying Iranian Docker mirrors (fallback chain)..."

    # Order matters: put the most reliable / currently-working ones first.
    # ArvanCloud is currently known to be flaky (503), so it's near the end.
    IRAN_MIRRORS=(
        "https://mirror.iranserver.com/docker-ce/linux/${OS}|IranServer"
        "https://mirror.mobinhost.com/docker-ce/linux/${OS}|MobinHost"
        "https://mirror.kernel.ir/docker-ce/linux/${OS}|Kernel"
        "https://mirror.shatel.ir/docker-ce/linux/${OS}|Shatel"
        "https://mirror.arvancloud.ir/docker-ce/linux/${OS}|ArvanCloud"
    )

    for entry in "${IRAN_MIRRORS[@]}"; do
        mirror_base="${entry%%|*}"
        mirror_name="${entry##*|}"

        if try_install_docker_from_mirror "$mirror_base" "$mirror_name"; then
            INSTALL_SUCCESS=true
            INSTALL_METHOD="Iranian Mirror (${mirror_name})"
            break
        fi

        log_warn "Mirror ${mirror_name} failed. Trying next mirror..."
        echo ""
    done

    # If all Iranian mirrors failed, try official Docker repo
    if [ "$INSTALL_SUCCESS" = false ]; then
        log_warn "All Iranian mirrors failed."
        log_info "Trying official Docker repositories as fallback..."
        if try_install_docker_from_mirror "https://download.docker.com/linux/${OS}" "Official Docker"; then
            INSTALL_SUCCESS=true
            INSTALL_METHOD="Official Docker Repo (fallback)"
        fi
    fi
fi

# 2. Last resort: distro default repos
if [ "$INSTALL_SUCCESS" = false ]; then
    log_warn "Docker official/mirror installation failed."
    if try_install_docker_from_distro; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="Distro Default Repo (docker.io)"
    fi
fi

# 3. If everything failed, exit with clear error
if [ "$INSTALL_SUCCESS" = false ]; then
    log_error "All Docker installation methods failed!"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Check your internet connection:"
    echo "     curl -I https://download.docker.com"
    echo "  2. Check DNS:"
    echo "     cat /etc/resolv.conf"
    echo "     (try setting nameserver 178.22.122.100)"
    echo "  3. Manually inspect the docker.list file:"
    echo "     cat /etc/apt/sources.list.d/docker.list"
    echo "  4. Try running with Global option and a DNS shecan:"
    echo "     bash <(curl -fsSL <this-script-url>)"
    echo ""
    exit 1
fi

log_success "Docker install completed via: ${INSTALL_METHOD}"

# ---------- Configure Docker Daemon (Mirrors & Log Rotation) ----------
log_info "Configuring Docker daemon..."

# Backup existing daemon.json if it exists
if [ -f /etc/docker/daemon.json ]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%s)
    log_info "Backed up existing daemon.json"
fi

mkdir -p /etc/docker

# Create daemon.json
if [ "$SERVER_LOCATION" = "iran" ]; then
    # Iranian registry mirrors (popular and reliable ones)
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.iranserver.com",
    "https://docker.kernel.ir",
    "https://docker.arvancloud.ir",
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
systemctl restart docker || log_warn "Docker service restart returned non-zero (may still be OK)"
sleep 2

# ---------- Verify Installation ----------
log_info "Verifying installation..."

if command -v docker > /dev/null 2>&1; then
    DOCKER_VER=$(docker --version 2>/dev/null)
    if [ -n "$DOCKER_VER" ]; then
        log_success "Docker installed: $DOCKER_VER"
    else
        log_error "docker command exists but 'docker --version' failed."
        exit 1
    fi
else
    log_error "Docker binary not found in PATH!"
    exit 1
fi

# Check Compose — support both v2 plugin and v1 binary
COMPOSE_OK=false
COMPOSE_VER=""
if docker compose version > /dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version)
    COMPOSE_OK=true
    log_success "Docker Compose (v2 plugin) installed: $COMPOSE_VER"
elif command -v docker-compose > /dev/null 2>&1; then
    COMPOSE_VER=$(docker-compose --version)
    COMPOSE_OK=true
    log_warn "Docker Compose v1 (legacy binary) detected: $COMPOSE_VER"
else
    log_warn "Docker Compose not installed. You can install it later with:"
    echo "  sudo apt install docker-compose-v2"
fi

# Test Docker
log_info "Running hello-world test..."
if docker run --rm hello-world > /dev/null 2>&1; then
    log_success "Docker is working correctly!"
else
    log_warn "hello-world test failed. This might be due to network issues."
    log_warn "Docker itself is installed, but pulling images may need registry mirrors."
fi

# ---------- Show Status ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "Install method:  ${INSTALL_METHOD}"
echo "Docker version:  $(docker --version)"
[ -n "$COMPOSE_VER" ] && echo "Compose version: $COMPOSE_VER"
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