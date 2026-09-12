#!/bin/bash

# ======================================================
#  SoftEther Client + OpenVPN Installer (ARM64 - GitHub)
#  Features:
#  - Downloads SoftEther vpnclient from GitHub Releases
#  - Auto-detects ARM64 architecture
#  - Installs OpenVPN and Network Manager plugin
#  - Compiles SoftEther client (requires make)
#  - Interactive & guided
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

# ---------- Check Root ----------
if [ "$EUID" -ne 0 ]; then
  log_error "Please run as root (use sudo)."
  exit 1
fi

# ---------- Detect OS & Architecture ----------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Cannot detect OS."
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    log_error "This script supports Ubuntu and Debian only."
    exit 1
fi

ARCH=$(dpkg --print-architecture)
log_success "Detected OS: $OS $VER ($ARCH)"

# Check if architecture is ARM64
if [ "$ARCH" != "arm64" ]; then
    log_warn "This script is optimized for ARM64. Detected: $ARCH"
    log_warn "The download URL will use 'linux-arm64-64bit'."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ---------- Install Dependencies ----------
log_info "Installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl \
  wget \
  tar \
  gzip \
  make \
  gcc \
  build-essential \
  libssl-dev \
  libreadline-dev \
  libncurses-dev \
  zlib1g-dev \
  openvpn \
  network-manager-openvpn \
  network-manager-openvpn-gnome > /dev/null 2>&1

log_success "Prerequisites installed."

# ---------- Install SoftEther Client from GitHub ----------
log_info "Installing SoftEther VPN Client (ARM64)..."

# Check if already installed
if [ -f /usr/local/vpnclient/vpnclient ]; then
    log_warn "SoftEther VPN Client is already installed at /usr/local/vpnclient/"
else
    # Use the version from the user's provided link context
    SOFTETHER_VERSION="v4.44-9807-rtm"
    SOFTETHER_DATE="2025.04.16"
    
    # Construct the GitHub download URL for vpnclient (ARM64)
    # Format: https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/{VERSION}/softether-vpnclient-{VERSION}-{DATE}-linux-arm64-64bit.tar.gz
    SOFTETHER_URL="https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/${SOFTETHER_VERSION}/softether-vpnclient-${SOFTETHER_VERSION}-${SOFTETHER_DATE}-linux-arm64-64bit.tar.gz"
    
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    log_info "Downloading from: $SOFTETHER_URL"
    log_info "Please wait... (file size may be ~5MB)"
    
    if wget -q --show-progress "$SOFTETHER_URL" -O softether-client.tar.gz; then
        log_success "Downloaded successfully."
    else
        log_error "Failed to download SoftEther Client from GitHub."
        log_warn "Possible reasons:"
        echo "  1. The URL format has changed. Check the Releases page manually:"
        echo "     https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases"
        echo "  2. Network restrictions (GitHub may be slow/blocked)."
        echo "  3. The exact filename has changed."
        cd /
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # Extract
    log_info "Extracting archive..."
    tar xzf softether-client.tar.gz
    cd vpnclient
    
    # Compile (SoftEther requires "make" to accept license)
    log_info "Compiling SoftEther Client (accepting license automatically)..."
    echo "1" | make > /dev/null 2>&1
    
    if [ ! -f ./vpnclient ]; then
        log_error "Compilation failed. The vpnclient binary was not created."
        cd /
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # Move to /usr/local
    log_info "Installing to /usr/local/vpnclient/..."
    mkdir -p /usr/local/vpnclient
    cp -r ./* /usr/local/vpnclient/ 2>/dev/null || true
    cd /
    rm -rf "$TMP_DIR"
    
    if [ -f /usr/local/vpnclient/vpnclient ]; then
        log_success "SoftEther Client installed to /usr/local/vpnclient/"
    else
        log_error "Installation failed."
        exit 1
    fi
fi

# ---------- Install OpenVPN (already installed via deps) ----------
log_info "Verifying OpenVPN installation..."
if command -v openvpn > /dev/null 2>&1; then
    OPENVPN_VER=$(openvpn --version | head -1)
    log_success "OpenVPN installed: $OPENVPN_VER"
else
    log_error "OpenVPN installation failed."
fi

# ---------- Create SoftEther systemd Service ----------
log_info "Setting up SoftEther systemd service..."

cat > /etc/systemd/system/vpnclient.service << 'EOF'
[Unit]
Description=SoftEther VPN Client
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/vpnclient/vpnclient start
ExecStop=/usr/local/vpnclient/vpnclient stop
WorkingDirectory=/usr/local/vpnclient

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpnclient > /dev/null 2>&1
log_success "SoftEther systemd service created."

# ---------- Show Configuration Instructions ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  SoftEther VPN Client Configuration${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "To configure and start SoftEther Client:"
echo ""
echo "1. Start the service:"
echo "   sudo systemctl start vpnclient"
echo ""
echo "2. Enter the management console:"
echo "   cd /usr/local/vpnclient"
echo "   sudo ./vpncmd"
echo ""
echo "3. In vpncmd, select [1] VPN Client, then press Enter:"
echo "   - AccountCreate: Create a new connection account"
echo "     Example: AccountCreate MyVPN /SERVER:vpn.example.com:443 /HUB:VPN"
echo "   - AccountPasswordSet: Set the password"
echo "     Example: AccountPasswordSet MyVPN /PASSWORD:your_pass /TYPE:standard"
echo "   - AccountConnect: Connect to the VPN"
echo "     Example: AccountConnect MyVPN"
echo "   - AccountStatusGet: Check connection status"
echo ""
echo -e "${YELLOW}Configuration files location:${NC}"
echo "   /usr/local/vpnclient/"
echo ""

echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  OpenVPN Configuration${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "To connect using OpenVPN:"
echo ""
echo "1. Place your .ovpn file in:"
echo "   /etc/openvpn/conf/"
echo ""
echo "2. Connect:"
echo "   sudo openvpn --config /etc/openvpn/conf/your-config.ovpn --daemon"
echo ""
echo "Or use Network Manager GUI:"
echo "   Settings -> Network -> VPN -> '+' -> Import from file..."
echo ""
echo -e "${YELLOW}Network Manager profiles are stored in:${NC}"
echo "   /etc/NetworkManager/system-connections/"
echo ""

echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  Service Status${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "SoftEther Client: $(systemctl is-active vpnclient 2>/dev/null || echo 'inactive (run: systemctl start vpnclient)')"
echo ""

log_success "All done! 🚀"
