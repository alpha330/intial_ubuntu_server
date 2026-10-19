#!/bin/bash

# ======================================================
#  GitHub Repo Clone Script
#  Features:
#  - Install Git & dependencies
#  - Clone repo to /opt
#  - Interactive & guided
#  - Supports both public and private repos
#  - Private repos: token is never echoed and is NOT left in .git/config
#  - Works with: curl ... | sudo bash  (prompts read from /dev/tty)
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

# ---------- Install Git & Dependencies ----------
log_info "Installing Git and dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Check if git is already installed
if ! command -v git > /dev/null 2>&1; then
    apt-get install -y -qq git > /dev/null 2>&1
    log_success "Git installed."
else
    log_success "Git is already installed."
fi

# Install additional useful tools
log_info "Installing additional tools (curl, wget, unzip)..."
apt-get install -y -qq curl wget unzip ca-certificates > /dev/null 2>&1
log_success "Additional tools installed."

# ---------- Get User Information ----------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  GitHub Repository Clone${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

# Get GitHub username
ask -p "Enter your GitHub username: " github_user

# Get repository name
ask -p "Enter repository name (e.g., my-project): " repo_name

if [ -z "$github_user" ] || [ -z "$repo_name" ]; then
    log_error "GitHub username and repository name cannot be empty."
    exit 1
fi

# Get branch (default: main)
ask -p "Enter branch name (default: main): " branch_name
branch_name=${branch_name:-main}

# Ask if repository is private
ask -p "Is the repository private? (y/n): " -n 1
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    is_private=true
    log_info "Private repository selected."
else
    is_private=false
    log_info "Public repository selected."
fi

# ---------- Prepare /opt Directory ----------
TARGET_DIR="/opt/$repo_name"

if [ -d "$TARGET_DIR" ]; then
    log_warn "Directory $TARGET_DIR already exists."
    ask -p "Do you want to remove it and clone fresh? (y/n): " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$TARGET_DIR"
        log_info "Removed existing directory."
    else
        log_error "Aborted. Directory already exists."
        exit 1
    fi
fi

# ---------- Clone Repository ----------
echo ""
log_info "Cloning repository..."

# Construct repo URL
if [ "$is_private" = true ]; then
    # For private repos, use token authentication
    echo ""
    echo -e "${YELLOW}For private repositories, you need a Personal Access Token (PAT).${NC}"
    echo ""
    echo "How to create a token:"
    echo "  1. Go to: https://github.com/settings/tokens"
    echo "  2. Click 'Generate new token (classic)'"
    echo "  3. Give it a name (e.g., VPS Clone)"
    echo "  4. Check 'repo' scope"
    echo "  5. Click 'Generate token' and copy it"
    echo ""
    echo "Tip: a fine-grained token with read-only 'Contents' access to this repo,"
    echo "     or an SSH deploy key, is safer than a classic 'repo' token."
    echo ""
    ask -s -p "Enter your Personal Access Token: " github_token
    echo ""
    if [ -z "$github_token" ]; then
        log_error "Token cannot be empty for a private repository."
        exit 1
    fi
    
    # Use token in URL
    REPO_URL="https://${github_user}:${github_token}@github.com/${github_user}/${repo_name}.git"
    DISPLAY_URL="https://github.com/${github_user}/${repo_name}.git"
else
    # Public repo
    REPO_URL="https://github.com/${github_user}/${repo_name}.git"
    DISPLAY_URL="$REPO_URL"
fi

# Clone the repository
CLEAN_URL="https://github.com/${github_user}/${repo_name}.git"
echo ""
log_info "Cloning from: $DISPLAY_URL"
log_info "Target directory: $TARGET_DIR"
log_info "Branch: $branch_name"

if git clone -b "$branch_name" "$REPO_URL" "$TARGET_DIR" 2>/dev/null; then
    log_success "Repository cloned successfully!"
else
    # Try without specifying branch
    log_warn "Branch '$branch_name' not found. Trying default branch..."
    if git clone "$REPO_URL" "$TARGET_DIR" 2>/dev/null; then
        log_success "Repository cloned successfully (default branch)!"
    else
        log_error "Failed to clone repository."
        log_warn "Please check:"
        echo "  - Repository name and username are correct"
        echo "  - For private repos, token has 'repo' scope"
        echo "  - For private repos, token is valid and not expired"
        exit 1
    fi
fi

# ---------- Post-Clone Setup ----------
cd "$TARGET_DIR"

# ---------- Remove token from .git/config ----------
if [ "$is_private" = true ]; then
    git remote set-url origin "$CLEAN_URL"
    log_success "Token removed from .git/config (remote is now $CLEAN_URL)."

    echo ""
    echo "For future 'git pull' on this private repo you can:"
    echo "  - store the token in a root-only file (/root/.git-credentials-${repo_name}, chmod 600), or"
    echo "  - use an SSH deploy key: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys"
    ask -p "Store the token for this repo in a root-only credentials file? (y/N): " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CRED_FILE="/root/.git-credentials-${repo_name}"
        ( umask 077; printf 'https://%s:%s@github.com\n' "$github_user" "$github_token" > "$CRED_FILE" )
        chmod 600 "$CRED_FILE"
        git config credential.helper "store --file=$CRED_FILE"
        log_success "Token stored in $CRED_FILE (mode 600) for this repo only."
    else
        log_info "Token not stored. You will be asked for credentials on 'git pull'."
    fi
fi
unset github_token REPO_URL

# Show repository info
echo ""
log_success "Repository cloned to: $TARGET_DIR"
echo ""
echo -e "${BOLD}Repository Information:${NC}"
echo "  - Remote URL: $(git remote get-url origin 2>/dev/null | sed 's/:[^@]*@/:***@/')"
echo "  - Current branch: $(git branch --show-current 2>/dev/null)"
echo "  - Latest commit: $(git log -1 --pretty=format:'%h - %s (%an, %ar)' 2>/dev/null)"

# Check for docker-compose.yml
if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
    echo ""
    log_info "Docker Compose file detected."
    ask -p "Do you want to start the project with Docker Compose? (y/n): " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v docker > /dev/null 2>&1; then
            log_info "Starting services..."
            docker compose up -d 2>/dev/null || docker-compose up -d
            log_success "Services started!"
        else
            log_warn "Docker is not installed. Please install Docker first."
        fi
    fi
fi

# Show final message
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  Setup Complete!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo "Project location: $TARGET_DIR"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  cd $TARGET_DIR           # Go to project"
echo "  git pull origin $branch_name    # Pull latest changes"
echo "  git status               # Check status"
echo ""
log_success "All done! 🚀"