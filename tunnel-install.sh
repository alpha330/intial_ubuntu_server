#!/bin/bash

# ======================================================
#  SoftEther Client + OpenVPN Installer
#  Features:
#  - Install SoftEther VPN Client
#  - Install OpenVPN Connect (via network-manager)
#  - Interactive & guided
#  - Show config file locations
#  - Based on Ubuntu/Debian
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
  network-manager-openvpn \
  network-manager-openvpn-gnome > /dev/null 2>&1

log_success "Prerequisites installed."

# ---------- Install SoftEther Client ----------
log_info "Installing SoftEther VPN Client..."

# Check if already installed
if [ -f /usr/local/vpnclient/vpnclient ]; then
    log_warn "SoftEther VPN Client is already installed at /usr/local/vpnclient/"
else
    # Download latest SoftEther Client
    SOFTETHER_URL="https://www.softether-download.com/files/softether/v4.43-9799-beta-2024.04.10-tree/Linux/SoftEther_VPN_Client/64bit_-_Intel_x64_or_AMD64/softether-vpnclient-v4.43-9799-beta-2024.04.10-linux-x64-64bit.tar.gz"
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    log_info "Downloading SoftEther VPN Client..."
    if wget -q "$SOFTETHER_URL" -O softether-client.tar.gz; then
        log_success "Downloaded successfully."
    else
        log_error "Failed to download SoftEther Client."
        log_warn "Please check the URL or download manually from:"
        echo "  https://www.softether-download.com/en.aspx?product=softether"
        cd /
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # Extract
    tar xzf softether-client.tar.gz
    cd vpnclient
    
    # Compile (SoftEther requires "make" to accept license)
    log_info "Compiling SoftEther Client (accepting license)..."
    echo "1" | make > /dev/null 2>&1
    
    # Move to /usr/local
    mv /tmp/tmp*/vpnclient /usr/local/vpnclient 2>/dev/null
    cd /
    rm -rf "$TMP_DIR"
    
    if [ -f /usr/local/vpnclient/vpnclient ]; then
        log_success "SoftEther Client installed to /usr/local/vpnclient/"
    else
        log_error "SoftEther Client installation failed."
        exit 1
    fi
fi

# ---------- Install OpenVPN Connect ----------
log_info "Installing OpenVPN (via Network Manager)..."

# Install OpenVPN and Network Manager plugin
apt-get install -y -qq openvpn network-manager-openvpn network-manager-openvpn-gnome > /dev/null 2>&1

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
echo "To configure SoftEther Client:"
echo ""
echo "1. Start the service:"
echo "   sudo systemctl start vpnclient"
echo ""
echo "2. Enter the VPN Client management console:"
echo "   cd /usr/local/vpnclient"
echo "   sudo ./vpncmd"
echo ""
echo "3. In vpncmd, select [1] VPN Client, then [2] to manage account:"
echo "   - AccountCreate: Create a new connection account"
echo "   - AccountConnect: Connect to the VPN"
echo "   - AccountList: List all accounts"
echo ""
echo -e "${YELLOW}Configuration files location:${NC}"
echo "   SoftEther stores configs in: /usr/local/vpnclient/"
echo "   (The exact path depends on how you set it up via vpncmd)"
echo ""

echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  OpenVPN Configuration${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "To connect using OpenVPN:"
echo ""
echo "1. Place your .ovpn configuration file in:"
echo "   /etc/openvpn/conf/"
echo ""
echo "2. Run OpenVPN with your config:"
echo "   sudo openvpn --config /etc/openvpn/conf/your-config.ovpn --daemon"
echo ""
echo "Or use Network Manager (GUI):"
echo "   1. Open Settings -> Network -> VPN"
echo "   2. Click '+' and select 'Import from file...'"
echo "   3. Select your .ovpn file"
echo "   4. Enter your credentials"
echo ""

echo -e "${YELLOW}Where does OpenVPN Connect store profiles?${NC}"
echo "   On Linux with Network Manager, profiles are stored in:"
echo "   /etc/NetworkManager/system-connections/"
echo ""
echo "   The .ovpn files you import are converted and stored there."
echo ""

# ---------- Show Service Status ----------
echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  Service Status${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "SoftEther Client: $(systemctl is-active vpnclient 2>/dev/null || echo 'inactive (run: systemctl start vpnclient)')"
echo "OpenVPN: $(systemctl is-active openvpn 2>/dev/null || echo 'ready (no active connections)')"
echo ""

log_success "All done! 🚀"
