#!/bin/bash

# ======================================================
#  SSL Certificate Auto-Installer (Let's Encrypt + Certbot)
#  Features:
#  - Auto-detect & install Certbot
#  - Interactive: Ask for domain, email
#  - Check port 80 availability
#  - Offer to stop service occupying port 80
#  - Ask for validation method (standalone, webroot, nginx, DNS)
#  - Obtain & install SSL certificate
#  - Configure auto-renewal
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

# ---------- Install Certbot (if missing) ----------
echo ""
log_info "Checking Certbot installation..."

if command -v certbot > /dev/null 2>&1; then
    CERTBOT_VER=$(certbot --version 2>&1 | head -1)
    log_success "Certbot already installed: $CERTBOT_VER"
else
    log_warn "Certbot not found. Installing..."
    
    # Install dependencies
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg software-properties-common > /dev/null 2>&1
    
    # Install Certbot via apt (recommended for Ubuntu 22.04+)
    apt-get install -y -qq certbot > /dev/null 2>&1
    
    if command -v certbot > /dev/null 2>&1; then
        CERTBOT_VER=$(certbot --version 2>&1 | head -1)
        log_success "Certbot installed: $CERTBOT_VER"
    else
        log_error "Failed to install Certbot. Please install manually."
        exit 1
    fi
fi

# ---------- Get Domain & Email ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  SSL Certificate Setup${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

read -p "Enter your domain (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    log_error "Domain cannot be empty."
    exit 1
fi

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_warn "Domain format looks unusual: $DOMAIN"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

read -p "Enter your email (for Let's Encrypt notifications): " EMAIL

if [ -z "$EMAIL" ]; then
    log_error "Email cannot be empty."
    exit 1
fi

# ---------- Check Port 80 ----------
echo ""
log_info "Checking port 80 availability..."

# Find process using port 80
PORT_80_PROCESS=""
if command -v ss > /dev/null 2>&1; then
    PORT_80_PROCESS=$(ss -tlnp | grep ':80 ' | head -1)
elif command -v netstat > /dev/null 2>&1; then
    PORT_80_PROCESS=$(netstat -tlnp | grep ':80 ' | head -1)
elif command -v lsof > /dev/null 2>&1; then
    PORT_80_PROCESS=$(lsof -i :80 2>/dev/null | grep LISTEN | head -1)
fi

if [ -n "$PORT_80_PROCESS" ]; then
    log_warn "Port 80 is already in use!"
    echo ""
    echo -e "${YELLOW}Process occupying port 80:${NC}"
    echo "  $PORT_80_PROCESS"
    echo ""
    
    read -p "Do you want to stop this service temporarily? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Extract service name from process
        SERVICE_NAME=""
        
        # Try to identify the service
        if echo "$PORT_80_PROCESS" | grep -q "nginx"; then
            SERVICE_NAME="nginx"
        elif echo "$PORT_80_PROCESS" | grep -q "apache2"; then
            SERVICE_NAME="apache2"
        elif echo "$PORT_80_PROCESS" | grep -q "httpd"; then
            SERVICE_NAME="httpd"
        elif echo "$PORT_80_PROCESS" | grep -q "docker"; then
            log_warn "Docker is using port 80. You may need to stop the container manually."
            read -p "Enter container name/ID to stop (or leave empty): " DOCKER_CONTAINER
            if [ -n "$DOCKER_CONTAINER" ]; then
                docker stop "$DOCKER_CONTAINER" 2>/dev/null
                log_success "Docker container stopped."
            fi
        fi
        
        if [ -n "$SERVICE_NAME" ]; then
            log_info "Stopping $SERVICE_NAME..."
            systemctl stop "$SERVICE_NAME" 2>/dev/null
            sleep 2
            log_success "$SERVICE_NAME stopped."
            echo ""
            log_warn "Remember to restart $SERVICE_NAME after SSL setup!"
        fi
        
        # Re-check port
        sleep 1
        if command -v ss > /dev/null 2>&1; then
            if ss -tlnp | grep -q ':80 '; then
                log_error "Port 80 is still in use. Please stop the service manually."
                exit 1
            fi
        fi
        log_success "Port 80 is now available."
    else
        log_warn "Port 80 is in use. Certbot may fail."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    log_success "Port 80 is available."
fi

# ---------- Ask for Validation Method ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Select Validation Method${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "How would you like to validate domain ownership?"
echo ""
echo "  1) Standalone (Certbot runs a temporary web server on port 80)"
echo "     - Best if: No web server is currently running"
echo "     - Requires: Port 80 free"
echo ""
echo "  2) Webroot (Place files in your existing web server's root)"
echo "     - Best if: You have Nginx/Apache running with a known webroot"
echo "     - Requires: Write access to webroot, port 80 open"
echo ""
echo "  3) Nginx (Certbot automatically configures Nginx)"
echo "     - Best if: Nginx is running and you want automatic SSL setup"
echo "     - Requires: Nginx installed, port 80 open"
echo ""
echo "  4) DNS (Manual TXT record - for wildcard certs or port 80 blocked)"
echo "     - Best if: Port 80 is blocked, or you need wildcard (*.domain.com)"
echo "     - Requires: Access to DNS management"
echo ""

read -p "Enter choice [1-4]: " VALIDATION_METHOD

case $VALIDATION_METHOD in
    1)
        log_info "Selected: Standalone mode"
        CERTBOT_MODE="standalone"
        CERTBOT_ARGS="certonly --standalone"
        ;;
    2)
        log_info "Selected: Webroot mode"
        read -p "Enter webroot path (e.g., /var/www/html): " WEBROOT_PATH
        if [ ! -d "$WEBROOT_PATH" ]; then
            log_error "Webroot path does not exist: $WEBROOT_PATH"
            exit 1
        fi
        CERTBOT_MODE="webroot"
        CERTBOT_ARGS="certonly --webroot -w $WEBROOT_PATH"
        ;;
    3)
        log_info "Selected: Nginx mode"
        if ! command -v nginx > /dev/null 2>&1; then
            log_error "Nginx is not installed. Please install it first or choose another method."
            exit 1
        fi
        CERTBOT_MODE="nginx"
        CERTBOT_ARGS="--nginx"
        ;;
    4)
        log_info "Selected: DNS mode (manual)"
        log_warn "You will need to manually add a TXT record to your DNS."
        read -p "Do you want a wildcard certificate (*.domain.com)? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            WILDCARD=true
        else
            WILDCARD=false
        fi
        CERTBOT_MODE="dns"
        CERTBOT_ARGS="certonly --manual --preferred-challenges dns"
        ;;
    *)
        log_error "Invalid choice. Please run again and select 1-4."
        exit 1
        ;;
esac

# ---------- Obtain Certificate ----------
echo ""
log_info "Obtaining SSL certificate for: $DOMAIN"
log_info "Using method: $CERTBOT_MODE"
echo ""

# Build the certbot command
CERTBOT_CMD="certbot $CERTBOT_ARGS"

# Add domain(s)
if [ "$CERTBOT_MODE" = "dns" ] && [ "$WILDCARD" = true ]; then
    CERTBOT_CMD="$CERTBOT_CMD -d $DOMAIN -d *.$DOMAIN"
else
    CERTBOT_CMD="$CERTBOT_CMD -d $DOMAIN"
fi

# Add email and agreement
CERTBOT_CMD="$CERTBOT_CMD --email $EMAIL --agree-tos --non-interactive"

# For standalone/webroot, add no-eff-email
if [ "$CERTBOT_MODE" != "dns" ] && [ "$CERTBOT_MODE" != "nginx" ]; then
    CERTBOT_CMD="$CERTBOT_CMD --no-eff-email"
fi

# Execute
echo -e "${CYAN}Running: $CERTBOT_CMD${NC}"
echo ""

if eval "$CERTBOT_CMD"; then
    log_success "SSL certificate obtained successfully!"
else
    log_error "Failed to obtain SSL certificate."
    log_warn "Check the log: /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi

# ---------- Show Certificate Info ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  SSL Certificate Installed!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

if [ -d "$CERT_DIR" ]; then
    echo "Certificate files:"
    echo "  - Full chain: $CERT_DIR/fullchain.pem"
    echo "  - Private key: $CERT_DIR/privkey.pem"
    echo "  - Chain: $CERT_DIR/chain.pem"
    echo ""
    
    # Show expiration
    if [ -f "$CERT_DIR/cert.pem" ]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_DIR/cert.pem" 2>/dev/null | cut -d= -f2)
        echo "Expires: $EXPIRY"
    fi
else
    log_warn "Certificate directory not found. Check Certbot output above."
fi

# ---------- Auto-Renewal ----------
echo ""
log_info "Checking auto-renewal configuration..."

if systemctl is-active --quiet certbot.timer 2>/dev/null; then
    log_success "Certbot auto-renewal timer is active."
elif systemctl is-active --quiet snap.certbot.renew.timer 2>/dev/null; then
    log_success "Certbot auto-renewal timer (snap) is active."
else
    log_warn "Auto-renewal timer not found. Setting up cron job..."
    
    # Create cron job for renewal
    cat > /etc/cron.d/certbot-renew << 'EOF'
# Certbot auto-renewal - runs twice daily
0 0,12 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx 2>/dev/null || true"
EOF
    
    log_success "Cron job created: /etc/cron.d/certbot-renew"
fi

# Test renewal
log_info "Testing renewal process (dry-run)..."
if certbot renew --dry-run --quiet 2>/dev/null; then
    log_success "Renewal test passed!"
else
    log_warn "Renewal dry-run had issues. Check manually: certbot renew --dry-run"
fi

# ---------- Post-Setup Instructions ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  Next Steps${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

if [ "$CERTBOT_MODE" = "standalone" ]; then
    echo "Since you used standalone mode:"
    echo "  1. Configure your web server to use the SSL certificate:"
    echo "     ssl_certificate     $CERT_DIR/fullchain.pem;"
    echo "     ssl_certificate_key $CERT_DIR/privkey.pem;"
    echo "  2. Restart your web server"
    echo ""
fi

if [ -n "$SERVICE_NAME" ]; then
    echo "You stopped $SERVICE_NAME earlier. To restart it:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo ""
fi

echo "Certificate location: $CERT_DIR"
echo ""
echo "Useful commands:"
echo "  certbot certificates          # List all certificates"
echo "  certbot renew --dry-run       # Test renewal"
echo "  certbot renew                 # Force renewal"
echo "  certbot delete --cert-name $DOMAIN  # Delete certificate"
echo ""

log_success "SSL setup complete! 🔒"
