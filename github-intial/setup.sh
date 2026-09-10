#!/bin/bash

# ======================================================
#  GitHub Repo Clone Script
#  Features:
#  - Install Git & dependencies
#  - Clone repo to /opt
#  - Interactive & guided
#  - Supports both public and private repos
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
read -p "Enter your GitHub username: " github_user

# Get repository name
read -p "Enter repository name (e.g., my-project): " repo_name

# Get branch (default: main)
read -p "Enter branch name (default: main): " branch_name
branch_name=${branch_name:-main}

# Ask if repository is private
read -p "Is the repository private? (y/n): " -n 1 -r
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
    read -p "Do you want to remove it and clone fresh? (y/n): " -n 1 -r
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
    read -p "Enter your Personal Access Token: " github_token
    
    # Use token in URL
    REPO_URL="https://${github_user}:${github_token}@github.com/${github_user}/${repo_name}.git"
    DISPLAY_URL="https://github.com/${github_user}/${repo_name}.git"
else
    # Public repo
    REPO_URL="https://github.com/${github_user}/${repo_name}.git"
    DISPLAY_URL="$REPO_URL"
fi

# Clone the repository
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
    read -p "Do you want to start the project with Docker Compose? (y/n): " -n 1 -r
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