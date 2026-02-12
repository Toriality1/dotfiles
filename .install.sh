#!/usr/bin/env bash

###############################################################################
# WSL2 DEVELOPMENT ENVIRONMENT BOOTSTRAP SCRIPT
#
# This script sets up a clean CLI-focused development environment for WSL2.
#
# Designed for:
#   - Debian WSL2
#   - Non-root user
#   - Re-runnable (mostly idempotent)
#
###############################################################################

set -e  # Exit immediately if a command exits with non-zero status

###############################################################################
# COLORS (for readable output)
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# PATHS
###############################################################################

CONFIG="$HOME/.config"
DOTFILES_DIR="/tmp/dotfiles-bootstrap"

###############################################################################
# ARGUMENT PARSING
#
# Only one optional flag:
#   --dont-update   -> Skip apt update/upgrade
###############################################################################

SKIP_UPDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dont-update)
            SKIP_UPDATE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

###############################################################################
# LOGGING HELPERS
###############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

###############################################################################
# CLEANUP HANDLER
#
# This ensures /tmp clone is removed even if the script exits early.
###############################################################################

cleanup() {
    rm -rf "$DOTFILES_DIR"
}

trap cleanup EXIT

###############################################################################
# SAFETY CHECKS
###############################################################################

# Do NOT allow running as root.
if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root."
fi

# Ensure sudo works before proceeding.
if ! sudo -v; then
    error "This script requires sudo access."
fi

log "Starting WSL2 CLI development environment setup..."

###############################################################################
# SYSTEM UPDATE
###############################################################################

if [ "$SKIP_UPDATE" != true ]; then
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
fi

###############################################################################
# BASE CLI PACKAGES
###############################################################################

log "Installing base CLI development packages..."

sudo apt install -y \
    build-essential \
    curl \
    git \
    ripgrep \
    wget \
    unzip \
    fuse \
    ca-certificates \
    gnupg \
    lsb-release \
    tmux \
    zsh \
    python3 \
    python3-venv \
    python3-pip

log "Base packages installed."

###############################################################################
# DOTFILES
#
# We clone into /tmp and then copy contents safely.
# Using '/.' ensures we copy contents and not nest directories.
###############################################################################

log "Cloning dotfiles..."

rm -rf "$DOTFILES_DIR"
git clone https://github.com/Toriality1/dotfiles.git "$DOTFILES_DIR"

###############################################################################
# NEOVIM (AppImage install)
#
# Installing 0.11.2 version directly from GitHub.
# Placing in /usr/local/bin
###############################################################################

if ! nvim --version 2>/dev/null | grep -q "0.11.2"; then
  log "Installing Neovim v0.11.2..."

  NVIM_URL="https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.appimage"

  wget -q -O /tmp/nvim.appimage "$NVIM_URL"
  chmod +x /tmp/nvim.appimage
  sudo mv /tmp/nvim.appimage /usr/local/bin/nvim

  log "Neovim installed."
fi

###############################################################################
# NEOVIM CONFIG
###############################################################################

log "Setting up Neovim configuration..."

mkdir -p "$CONFIG/nvim"
cp -r "$DOTFILES_DIR/.config/nvim/." "$CONFIG/nvim/"

###############################################################################
# ZSH CONFIG
###############################################################################

log "Setting up Zsh..."

cp "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"

mkdir -p "$CONFIG/zsh"
cp -r "$DOTFILES_DIR/.config/zsh/." "$CONFIG/zsh/"

###############################################################################
# OH-MY-ZSH
###############################################################################

log "Installing Oh My Zsh..."

rm -rf "$HOME/.local/share/.oh-my-zsh"

ZDOTDIR="$CONFIG/zsh" \
ZSH="$HOME/.local/share/.oh-my-zsh" \
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
--unattended --keep-zshrc

###############################################################################
# ZSH PLUGINS
###############################################################################

log "Installing Zsh plugins..."

git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || true

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || true

###############################################################################
# SET ZSH AS DEFAULT SHELL
###############################################################################

if [[ "$SHELL" != "$(which zsh)" ]]; then
    chsh -s "$(which zsh)"
    warning "Log out and back in for Zsh to become default."
fi

###############################################################################
# TMUX CONFIG
###############################################################################

log "Setting up tmux..."

mkdir -p "$CONFIG/tmux"
cp -r "$DOTFILES_DIR/.config/tmux/." "$CONFIG/tmux/"

###############################################################################
# NODE (via FNM)
#
# We install FNM without modifying shell automatically.
# Then manually load environment.
###############################################################################

# Install fnm only if not already installed
if [ ! -d "$HOME/.local/share/fnm" ]; then
  log "Installing Node.js LTS via fnm..."

  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

# Ensure fnm is available in THIS script session
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"

# Ensure Node 22 is installed
if ! fnm list | grep -q "v22\."; then
  log "Installing Node 22..."
  fnm install 22
fi

fnm use 22

corepack enable
corepack prepare pnpm@latest --activate

info "Node version: $(node -v)"
info "pnpm version: $(pnpm -v)"

###############################################################################
# FINISHED
###############################################################################

log "WSL2 CLI environment setup complete."
log "It is recommended to restart WSL:"
echo "  wsl --shutdown"

