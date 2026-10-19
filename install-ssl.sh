#!/bin/bash

# ======================================================
#  SSL Certificate Auto-Installer (Let's Encrypt + Certbot)
#  Features:
#  - Auto-detect & install Certbot
#  - Interactive: Ask for domain, email
#  - Ask for validation method (standalone, webroot, nginx, DNS manual, DNS Cloudflare)
#  - Check port 80 only for standalone mode
#  - Offer to stop service occupying port 80 (restarted automatically,
#    even if Certbot fails)
#  - Obtain & install SSL certificate
#  - Configure auto-renewal
#  - Works with: curl ... | sudo bash  (prompts read from /dev/tty)
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

# ---------- Interactive Input (works with curl | bash) ----------
# All prompts read from the terminal (fd 3 -> /dev/tty), not from stdin,
# so the script still works when it is piped into bash.
if ! { exec 3</dev/tty; } 2>/dev/null; then
    log_error "No terminal (TTY) available for interactive prompts."
    log_error "Run this script from an interactive SSH session, e.g.:"
    # shellcheck disable=SC2016
    echo '  sudo bash -c "$(curl -fsSL <script-url>)"'
    exit 1
fi
ask() { read -r -u 3 "$@"; }

# ---------- Check Root ----------
if [ "$EUID" -ne 0 ]; then
  log_error "Please run as root (use sudo)."
  exit 1
fi

# ---------- Detect OS ----------
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
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

log_success "Detected OS: $OS ${VER:-${VERSION_CODENAME:-unknown}}"

# ---------- Version Check (Ubuntu 20.04+, Debian 11+) ----------
# Debian testing/sid has no VERSION_ID: allow it with a warning.
check_os_version() {
    local min=20
    [ "$OS" = "debian" ] && min=11
    local major="${VER%%.*}"
    if [[ ! "$major" =~ ^[0-9]+$ ]]; then
        log_warn "No numeric VERSION_ID (${VERSION_CODENAME:-unknown}, probably testing/sid). Skipping version check."
        return 0
    fi
    if [ "$major" -lt "$min" ]; then
        log_error "$OS $VER is too old. Please use $([ "$OS" = "debian" ] && echo 11 || echo 20.04) or newer."
        exit 1
    fi
}
check_os_version

# ---------- Helper: is a Debian package installed? ----------
pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

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

ask -p "Enter your domain (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    log_error "Domain cannot be empty."
    exit 1
fi

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_warn "Domain format looks unusual: $DOMAIN"
    ask -p "Continue anyway? (y/n): " -n 1
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

ask -p "Enter your email (for Let's Encrypt notifications): " EMAIL

if [ -z "$EMAIL" ]; then
    log_error "Email cannot be empty."
    exit 1
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
echo "     - Requires: Write access to webroot, web server running on port 80"
echo ""
echo "  3) Nginx (Certbot automatically configures Nginx)"
echo "     - Best if: Nginx is running and you want automatic SSL setup"
echo "     - Requires: Nginx installed + python3-certbot-nginx plugin, nginx running on port 80"
echo ""
echo "  4) DNS manual (TXT record - for wildcard certs or port 80 blocked)"
echo "     - Best if: Port 80 is blocked, or you need wildcard (*.domain.com)"
echo "     - Requires: Access to DNS management (runs interactively)"
echo "     - WARNING: manual certificates do NOT auto-renew"
echo ""
echo "  5) DNS via Cloudflare API (wildcard OK, auto-renews)"
echo "     - Best if: Your domain's DNS is hosted on Cloudflare"
echo "     - Requires: Cloudflare API token with Zone:DNS:Edit permission"
echo ""

ask -p "Enter choice [1-5]: " VALIDATION_METHOD

STOPPED_SERVICE=""
DOCKER_CONTAINER=""
NEED_PORT_80=false
WILDCARD=false
CERTBOT_ARGS=()

ask_wildcard() {
    ask -p "Do you want a wildcard certificate (*.domain.com)? (y/n): " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        WILDCARD=true
    fi
}

case $VALIDATION_METHOD in
    1)
        log_info "Selected: Standalone mode"
        CERTBOT_MODE="standalone"
        CERTBOT_ARGS=(certonly --standalone)
        NEED_PORT_80=true
        ;;
    2)
        log_info "Selected: Webroot mode"
        ask -p "Enter webroot path (e.g., /var/www/html): " WEBROOT_PATH
        if [ ! -d "$WEBROOT_PATH" ]; then
            log_error "Webroot path does not exist: $WEBROOT_PATH"
            exit 1
        fi
        CERTBOT_MODE="webroot"
        CERTBOT_ARGS=(certonly --webroot -w "$WEBROOT_PATH")
        log_info "Your web server must keep running and serve $WEBROOT_PATH on port 80."
        ;;
    3)
        log_info "Selected: Nginx mode"
        if ! command -v nginx > /dev/null 2>&1; then
            log_error "Nginx is not installed. Please install it first or choose another method."
            exit 1
        fi
        # Ensure the nginx plugin is installed
        if ! pkg_installed python3-certbot-nginx; then
            log_info "Installing python3-certbot-nginx..."
            apt-get update -qq
            apt-get install -y -qq python3-certbot-nginx > /dev/null 2>&1 || {
                log_error "Failed to install python3-certbot-nginx."
                exit 1
            }
            log_success "python3-certbot-nginx installed."
        else
            log_success "python3-certbot-nginx already present."
        fi
        CERTBOT_MODE="nginx"
        CERTBOT_ARGS=(--nginx)
        log_info "Nginx must keep running on port 80 (it will not be stopped)."
        ;;
    4)
        log_info "Selected: DNS mode (manual / interactive)"
        log_warn "You will need to manually add a TXT record to your DNS."
        log_warn "This mode runs interactively (no --non-interactive)."
        log_warn "Manual DNS certificates do NOT renew automatically."
        log_warn "You must re-run this script (or certbot) before the cert expires in 90 days."
        log_warn "For automatic renewal, use option 5 (Cloudflare) or another certbot DNS plugin."
        ask_wildcard
        CERTBOT_MODE="dns"
        CERTBOT_ARGS=(certonly --manual --preferred-challenges dns)
        ;;
    5)
        log_info "Selected: DNS via Cloudflare API"
        if ! pkg_installed python3-certbot-dns-cloudflare; then
            log_info "Installing python3-certbot-dns-cloudflare..."
            apt-get update -qq
            apt-get install -y -qq python3-certbot-dns-cloudflare > /dev/null 2>&1 || {
                log_error "Failed to install python3-certbot-dns-cloudflare."
                exit 1
            }
            log_success "python3-certbot-dns-cloudflare installed."
        fi
        CF_CREDENTIALS="/root/.secrets/certbot/cloudflare.ini"
        if [ -s "$CF_CREDENTIALS" ]; then
            log_info "Using existing Cloudflare credentials: $CF_CREDENTIALS"
        else
            echo "Create a token at: https://dash.cloudflare.com/profile/api-tokens"
            echo "  (template 'Edit zone DNS', limited to this zone)"
            ask -s -p "Enter your Cloudflare API token: " CF_TOKEN
            echo ""
            if [ -z "$CF_TOKEN" ]; then
                log_error "Cloudflare API token cannot be empty."
                exit 1
            fi
            install -d -m 700 "$(dirname "$CF_CREDENTIALS")"
            ( umask 077; printf 'dns_cloudflare_api_token = %s\n' "$CF_TOKEN" > "$CF_CREDENTIALS" )
            chmod 600 "$CF_CREDENTIALS"
            unset CF_TOKEN
            log_success "Credentials saved to $CF_CREDENTIALS (mode 600)."
        fi
        ask_wildcard
        CERTBOT_MODE="dns-cloudflare"
        CERTBOT_ARGS=(certonly --dns-cloudflare --dns-cloudflare-credentials "$CF_CREDENTIALS")
        ;;
    *)
        log_error "Invalid choice. Please run again and select 1-5."
        exit 1
        ;;
esac

# ---------- Restart anything we stopped (runs on success AND failure) ----------
restart_stopped_services() {
    if [ -n "$STOPPED_SERVICE" ]; then
        log_info "Restarting service that was stopped earlier: $STOPPED_SERVICE"
        if systemctl start "$STOPPED_SERVICE" 2>/dev/null; then
            log_success "$STOPPED_SERVICE restarted."
        else
            log_warn "Failed to restart $STOPPED_SERVICE. Please start it manually: systemctl start $STOPPED_SERVICE"
        fi
        STOPPED_SERVICE_DONE="$STOPPED_SERVICE"
        STOPPED_SERVICE=""
    fi

    if [ -n "$DOCKER_CONTAINER" ]; then
        log_info "Restarting Docker container that was stopped earlier: $DOCKER_CONTAINER"
        if docker start "$DOCKER_CONTAINER" > /dev/null 2>&1; then
            log_success "Docker container $DOCKER_CONTAINER restarted."
        else
            log_warn "Failed to restart container $DOCKER_CONTAINER. Please start it manually: docker start $DOCKER_CONTAINER"
        fi
        DOCKER_CONTAINER_DONE="$DOCKER_CONTAINER"
        DOCKER_CONTAINER=""
    fi
}
trap restart_stopped_services EXIT

# ---------- Check Port 80 (standalone only) ----------
if [ "$NEED_PORT_80" = true ]; then
    echo ""
    log_info "Checking port 80 availability..."

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
        
        ask -p "Do you want to stop this service temporarily? (y/n): " -n 1
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            SERVICE_NAME=""
            
            if echo "$PORT_80_PROCESS" | grep -q "nginx"; then
                SERVICE_NAME="nginx"
            elif echo "$PORT_80_PROCESS" | grep -q "apache2"; then
                SERVICE_NAME="apache2"
            elif echo "$PORT_80_PROCESS" | grep -q "httpd"; then
                SERVICE_NAME="httpd"
            elif echo "$PORT_80_PROCESS" | grep -q "docker"; then
                log_warn "Docker is using port 80. You may need to stop the container manually."
                ask -p "Enter container name/ID to stop (or leave empty): " CONTAINER_INPUT
                if [ -n "$CONTAINER_INPUT" ]; then
                    if docker stop "$CONTAINER_INPUT" > /dev/null 2>&1; then
                        DOCKER_CONTAINER="$CONTAINER_INPUT"
                        log_success "Docker container stopped."
                    else
                        log_warn "Could not stop container: $CONTAINER_INPUT"
                    fi
                fi
            fi
            
            if [ -n "$SERVICE_NAME" ]; then
                log_info "Stopping $SERVICE_NAME..."
                if systemctl stop "$SERVICE_NAME" 2>/dev/null; then
                    STOPPED_SERVICE="$SERVICE_NAME"
                    sleep 2
                    log_success "$SERVICE_NAME stopped."
                else
                    log_warn "Could not stop $SERVICE_NAME."
                fi
            fi
            
            sleep 1
            if command -v ss > /dev/null 2>&1; then
                if ss -tlnp | grep -q ':80 '; then
                    log_error "Port 80 is still in use. Please stop the service manually."
                    exit 1
                fi
            fi
            log_success "Port 80 is now available."

            # Let future renewals stop/start the same service around the challenge
            if [ -n "$STOPPED_SERVICE" ]; then
                CERTBOT_ARGS+=(--pre-hook "systemctl stop $STOPPED_SERVICE" --post-hook "systemctl start $STOPPED_SERVICE")
            elif [ -n "$DOCKER_CONTAINER" ]; then
                CERTBOT_ARGS+=(--pre-hook "docker stop $DOCKER_CONTAINER" --post-hook "docker start $DOCKER_CONTAINER")
            fi
        else
            log_warn "Port 80 is in use. Certbot may fail."
            ask -p "Continue anyway? (y/n): " -n 1
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_success "Port 80 is available."
    fi
fi

# ---------- Obtain Certificate ----------
echo ""
log_info "Obtaining SSL certificate for: $DOMAIN"
log_info "Using method: $CERTBOT_MODE"
echo ""

# Build the certbot command (array: no eval, no glob expansion of *.domain)
CERTBOT_CMD=(certbot "${CERTBOT_ARGS[@]}" --cert-name "$DOMAIN" -d "$DOMAIN")

if [ "$WILDCARD" = true ]; then
    CERTBOT_CMD+=(-d "*.$DOMAIN")
fi

# Add email and agreement
if [ "$CERTBOT_MODE" = "dns" ]; then
    # Manual DNS challenge requires interaction
    CERTBOT_CMD+=(--email "$EMAIL" --agree-tos)
    log_warn "Running interactively for the DNS challenge. Follow the on-screen instructions."
else
    CERTBOT_CMD+=(--email "$EMAIL" --agree-tos --non-interactive --no-eff-email)
fi

# Execute (stdin from the terminal so the manual DNS mode can prompt)
echo -e "${CYAN}Running: ${CERTBOT_CMD[*]}${NC}"
echo ""

if "${CERTBOT_CMD[@]}" <&3; then
    log_success "SSL certificate obtained successfully!"
else
    log_error "Failed to obtain SSL certificate."
    log_warn "Check the log: /var/log/letsencrypt/letsencrypt.log"
    exit 1   # EXIT trap restarts any stopped service/container
fi

# ---------- Restart any services we stopped ----------
restart_stopped_services

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
if [ "$CERTBOT_MODE" = "dns" ]; then
    log_warn "Manual DNS certificate: automatic renewal is NOT possible (no auth hook)."
    log_warn "Expires: ${EXPIRY:-in 90 days}. Re-run this script before then,"
    log_warn "or switch to a DNS plugin (e.g. option 5, python3-certbot-dns-cloudflare)."
    log_info "Skipping renewal dry-run for manual certificate."
else
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

    # Test renewal for this certificate only
    log_info "Testing renewal process (dry-run)..."
    if certbot renew --dry-run --quiet --cert-name "$DOMAIN" 2>/dev/null; then
        log_success "Renewal test passed!"
    else
        log_warn "Renewal dry-run had issues. Check manually: certbot renew --dry-run --cert-name $DOMAIN"
    fi
fi

# ---------- Post-Setup Instructions ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}  Next Steps${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

if [[ "$CERTBOT_MODE" = "standalone" || "$CERTBOT_MODE" = dns* || "$CERTBOT_MODE" = "webroot" ]]; then
    echo "Configure your web server to use the SSL certificate:"
    echo "     ssl_certificate     $CERT_DIR/fullchain.pem;"
    echo "     ssl_certificate_key $CERT_DIR/privkey.pem;"
    echo "  Then reload your web server."
    echo ""
fi

if [ -n "${STOPPED_SERVICE_DONE:-}${DOCKER_CONTAINER_DONE:-}" ]; then
    echo "Renewals will stop/start ${STOPPED_SERVICE_DONE:-$DOCKER_CONTAINER_DONE} automatically (certbot pre/post hooks)."
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
