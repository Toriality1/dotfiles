#!/usr/bin/env bash

###############################################################################
# DEBIAN DEVELOPMENT ENVIRONMENT BOOTSTRAP SCRIPT
#
# This script sets up a clean CLI-focused development environment for Debian.
#
# Designed for:
#   - Debian (bare metal, VM, or WSL2)
#   - Non-root user
#   - Re-runnable (mostly idempotent)
#
###############################################################################

set -e

###############################################################################
# COLORS
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

###############################################################################
# PATHS
###############################################################################

CONFIG="$HOME/.config"
DOTFILES_DIR="/tmp/dotfiles"

###############################################################################
# ARGUMENT PARSING
#
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
# INTERACTIVE PROMPT HELPER
#
# Usage: ask_yes_no "Question text" [y|n]
# Returns 0 (yes) or 1 (no)
###############################################################################

ask_yes_no() {
    local question="$1"
    local default="${2:-y}"

    while true; do
        if [[ "$default" == "y" ]]; then
            echo -en "${CYAN}[?] $question [Y/n]: ${NC}"
        else
            echo -en "${CYAN}[?] $question [y/N]: ${NC}"
        fi

        read -r answer
        answer="${answer:-$default}"

        case "$answer" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

###############################################################################
# SECTION HEADER HELPER
###############################################################################

section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

###############################################################################
# CLEANUP HANDLER
###############################################################################

cleanup() {
    rm -rf "$DOTFILES_DIR"
}

trap cleanup EXIT

###############################################################################
# SAFETY CHECKS
###############################################################################

if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root."
fi

if ! sudo -v; then
    error "This script requires sudo access."
fi

###############################################################################
# UP-FRONT PROMPTS
#
# Collect all user choices before any installation begins, so the script can
# run unattended after this point.
###############################################################################

section "Setup Preferences"
echo -e "${BLUE}Answer a few questions before we begin. All installs will then run unattended.${NC}"
echo ""

# --- GitHub ---
ask_yes_no "Log in to GitHub with gh in this script?" \
    && DO_GH_LOGIN=true || DO_GH_LOGIN=false

# --- Desktop GUI apps ---
# Only useful in a full desktop environment (bare metal / VM with GUI).
# Useless in WSL2 (no native GUI) and in headless servers.
echo ""
echo -e "${BLUE}The following are desktop/GUI apps — skip them if you're on WSL2 or a headless server.${NC}"
echo ""

ask_yes_no "Install i3wm? (window manager — skip on WSL2/server)" "n" \
    && DO_I3=true || DO_I3=false

ask_yes_no "Install pavucontrol? (audio mixer — skip on WSL2/server)" "n" \
    && DO_PAVUCONTROL=true || DO_PAVUCONTROL=false

ask_yes_no "Install Alacritty? (GPU terminal — skip on WSL2/server)" "n" \
    && DO_ALACRITTY=true || DO_ALACRITTY=false

ask_yes_no "Install Chromium? (browser — skip on WSL2/server)" "n" \
    && DO_CHROMIUM=true || DO_CHROMIUM=false

ask_yes_no "Install Epiphany? (browser — skip on WSL2/server)" "n" \
    && DO_EPIPHANY=true || DO_EPIPHANY=false

ask_yes_no "Install Spotify ? (music player — skip on WSL2/server)" "n" \
    && DO_SPOTIFY=true || DO_SPOTIFY=false

ask_yes_no "Install VSCodium? (IDE — skip on WSL2/server; WSL2 users use Windows VS Code + WSL extension)" "n" \
    && DO_VSCODE=true || DO_VSCODE=false

ask_yes_no "Install Google Antigravity? (AI IDE — skip on WSL2/server)" "n" \
  && DO_ANTIGRAVITY=true || DO_ANTIGRAVITY=false

ask_yes_no "Install Discord? (desktop app — skip on WSL2/server)" "n" \
    && DO_DISCORD=true || DO_DISCORD=false

ask_yes_no "Install OBS Studio? (screen capture — skip on WSL2/server)" "n" \
    && DO_OBS=true || DO_OBS=false

ask_yes_no "Install QEMU/KVN + Virt Manager? (VM Host — skip on WSL2/server)" "n" \
    && DO_QEMU=true || DO_QEMU=false

# --- Server / environment-specific tools ---
# Docker is great on bare metal and servers. WSL2 users typically use Docker
# Desktop on the Windows side instead.
echo ""
echo -e "${BLUE}The following are server/environment-specific — useful on bare metal/servers, handled differently on WSL2.${NC}"
echo ""

ask_yes_no "Install Docker? (WSL2 users typically use Docker Desktop on Windows instead)" "n" \
    && DO_DOCKER=true || DO_DOCKER=false


echo ""
log "Preferences collected. Starting installation..."

###############################################################################
# SYSTEM UPDATE
###############################################################################

section "System Update"

if [ "$SKIP_UPDATE" != true ]; then
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
else
    info "Skipping system update (--dont-update)."
fi

###############################################################################
# BASE CLI PACKAGES
# Always installed — useful in every environment (WSL, server, desktop).
###############################################################################

section "Base CLI Packages"

log "Installing base CLI development packages..."

sudo apt install -y \
    build-essential \
    curl \
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
    python3-pip \
    ripgrep \
    btop \
    xclip


log "Base packages installed."

###############################################################################
# GIT & GH CLI
# Always installed — version control is needed everywhere.
###############################################################################

section "Git & GitHub CLI"

log "Installing git..."
sudo apt install -y git

if ! command -v gh &>/dev/null; then
    log "Installing GitHub CLI..."

    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh

    log "GitHub CLI installed."
else
    info "GitHub CLI already installed, skipping."
fi

###############################################################################
# GIT GLOBAL CONFIG
# Always applied — these are universal settings.
###############################################################################

log "Configuring git globals..."

git config --global user.name "Pedro Crelier"
git config --global user.email "torialitym@gmail.com"
git config --global init.defaultBranch main

info "Git user:            Pedro Crelier <torialitym@gmail.com>"
info "Git default branch:  main"

###############################################################################
# GITHUB LOGIN
###############################################################################

if [ "$DO_GH_LOGIN" = true ]; then
    log "Logging in to GitHub..."
    gh auth login
else
    warning "Skipping GitHub login. Run 'gh auth login' when ready."
fi

###############################################################################
# DOTFILES
###############################################################################

section "Dotfiles"

log "Cloning dotfiles..."
rm -rf "$DOTFILES_DIR"
git clone https://github.com/Toriality1/dotfiles.git "$DOTFILES_DIR"

###############################################################################
# FONTS
###############################################################################

section "Fonts"

log "Installing JetBrainsMono Nerd Font..."

FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"

if fc-list | grep -q "JetBrainsMono Nerd Font"; then
  info "JetBrainsMono Nerd Font already installed, skipping."
else
  mkdir -p "$FONT_DIR"
  FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  FONT_ARCHIVE="/tmp/JetBrainsMono.tar.gz"
  wget -O "$FONT_ARCHIVE" "$FONT_URL"
  tar xf "$FONT_ARCHIVE" -C "$FONT_DIR"
  rm -f "$FONT_ARCHIVE"

  fc-cache -fv

  log "JetBrainsMono Nerd Font installed."
fi



###############################################################################
# NEOVIM (AppImage install)
# Always installed — a terminal editor is useful in every environment.
###############################################################################

section "Neovim"

if ! nvim --version 2>/dev/null | grep -q "0.11.2"; then
    log "Installing Neovim v0.11.2..."

    NVIM_URL="https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.appimage"

    wget -q -O /tmp/nvim.appimage "$NVIM_URL"
    chmod +x /tmp/nvim.appimage
    sudo mv /tmp/nvim.appimage /usr/local/bin/nvim

    log "Neovim installed."
else
    info "Neovim v0.11.2 already installed, skipping."
fi

log "Applying Neovim config..."
mkdir -p "$CONFIG/nvim"
cp -r "$DOTFILES_DIR/.config/nvim/." "$CONFIG/nvim/"

###############################################################################
# ZSH + OH-MY-ZSH + PLUGINS
# Always installed — shell config is useful in every environment.
###############################################################################

section "Zsh & Oh My Zsh"

log "Applying Zsh config..."
cp "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
mkdir -p "$CONFIG/zsh"
cp -r "$DOTFILES_DIR/.config/zsh/." "$CONFIG/zsh/"

log "Installing Oh My Zsh..."
rm -rf "$HOME/.local/share/.oh-my-zsh"

ZDOTDIR="$CONFIG/zsh" \
ZSH="$HOME/.local/share/.oh-my-zsh" \
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
    --unattended --keep-zshrc

log "Installing Zsh plugins..."

git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || true

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || true

if [[ "$SHELL" != "$(which zsh)" ]]; then
    chsh -s "$(which zsh)"
    warning "Log out and back in for Zsh to become default."
fi

###############################################################################
# TMUX
# Always installed — multiplexer is useful in every environment.
###############################################################################

section "Tmux"

log "Applying tmux config..."
mkdir -p "$CONFIG/tmux"
cp -r "$DOTFILES_DIR/.config/tmux/." "$CONFIG/tmux/"

###############################################################################
# NODE (via FNM)
# Always installed — JS tooling is needed everywhere.
###############################################################################

section "Node.js (via fnm)"

if [ ! -d "$HOME/.local/share/fnm" ]; then
    log "Installing fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"

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
# DOCKER
# Optional — great on bare metal/servers. WSL2 users typically use Docker Desktop.
###############################################################################

if [ "$DO_DOCKER" = true ]; then
    section "Docker"

    if ! command -v docker &>/dev/null; then
        log "Installing Docker..."

        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt update
        sudo apt install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        # Allow running docker without sudo
        sudo usermod -aG docker "$USER"

        log "Docker installed."
    else
        info "Docker already installed, skipping."
    fi
fi

###############################################################################
# I3 WINDOW MANAGER
# Optional — window manager. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_I3" = true ]; then
    section "i3 Window Manager"

    if ! command -v i3 &>/dev/null; then
        log "Installing i3wm and utilities..."

        # Install i3 and useful extras
        sudo apt install -y i3 i3status i3lock dmenu rofi

        # Optional: install compositor for transparency & effects
        sudo apt install -y picom

        # Apply i3 config from dotfiles if present
        if [ -d "$DOTFILES_DIR/.config/i3" ]; then
            mkdir -p "$CONFIG/i3"
            cp -r "$DOTFILES_DIR/.config/i3/." "$CONFIG/i3/"
            log "i3 config applied from dotfiles."
        fi

        # Apply rofi config from dotfiles if present
        if [ -d "$DOTFILES_DIR/.config/rofi" ]; then
            mkdir -p "$CONFIG/rofi"
            cp -r "$DOTFILES_DIR/.config/rofi/." "$CONFIG/rofi/"
            log "rofi config applied from dotfiles."
        fi

        log "i3 Window Manager installed."
    else
        info "i3wm already installed, skipping."
    fi
fi

###############################################################################
# ALACRITTY
# Optional — GPU-accelerated terminal. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_ALACRITTY" = true ]; then
    section "Alacritty"

    log "Installing Alacritty..."
    sudo apt install -y alacritty

    if [ -d "$DOTFILES_DIR/.config/alacritty" ]; then
        mkdir -p "$CONFIG/alacritty"
        cp -r "$DOTFILES_DIR/.config/alacritty/." "$CONFIG/alacritty/"
        log "Alacritty config applied."
    fi

    log "Alacritty installed."
fi

###############################################################################
# QEMU / KVM / VIRT-MANAGER
# Optional — virtualization. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_QEMU" = true ]; then
  section "QEMU/KVM/Virt-Manager"

  if ! command -v virsh &>/dev/null; then
    log "Installing QEMU/KVM/Virt-Manager..."
    sudo apt install -y \
        qemu-system-x86 \
        qemu-utils \
        libvirt-daemon-system \
        libvirt-clients \
        virt-manager \
        virtinst \
        bridge-utils \
        ovmf
    sudo usermod -aG libvirt "$USER"
    sudo usermod -aG kvm "$USER"
    sudo systemctl enable --now libvirtd
    log "QEMU/KVM/Virt-Manager installed."
  else
    info "QEMU/KVM/Virt-Manager already installed, skipping."
  fi
fi

###############################################################################
# CHROMIUM
# Optional — browser. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_CHROMIUM" = true ]; then
    section "Chromium"

    log "Installing Chromium..."
    sudo apt install -y chromium
    log "Chromium installed."
fi

###############################################################################
# EPIPHANY
# Optional — browser. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_EPIPHANY" = true ]; then
    section "Epiphany"

    if ! command -v epiphany-browser &>/dev/null; then
        log "Installing Epiphany..."
        sudo apt install -y epiphany-browser
        log "Epiphany installed."
    else
        info "Epiphany already installed, skipping."
    fi
fi

#############################################################################
# SPOTIFY
# Optional — music player. Useless in WSL2 or headless servers.
#############################################################################

if [ "$DO_SPOTIFY" = true ]; then
    section "Spotify"

    if ! command -v spotify &>/dev/null; then
        log "Installing Spotify..."
        curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
        echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
        sudo apt-get update && sudo apt-get install spotify-client
        log "Spotify installed."
    else
        info "Spotify already installed, skipping."
    fi
fi

###############################################################################
# VS CODIUM
# Optional — GUI editor. WSL2 users should use Windows VS Code + WSL extension.
#            Useless on headless servers.
###############################################################################

if [ "$DO_VSCODE" = true ]; then
    section "VS Codium"

    if ! command -v code &>/dev/null; then
        log "Installing VS Codium..."

        wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
    | gpg --dearmor \
    | sudo dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg
        echo -e 'Types: deb\nURIs: https://download.vscodium.com/debs\nSuites: vscodium\nComponents: main\nArchitectures: amd64 arm64\nSigned-by: /usr/share/keyrings/vscodium-archive-keyring.gpg' \
| sudo tee /etc/apt/sources.list.d/vscodium.sources
        sudo apt update
        sudo apt install -y codium

        log "VS Codium installed."
    else
        info "VS Codium already installed, skipping."
    fi
fi

###############################################################################
# DISCORD
# Optional — desktop chat app. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_DISCORD" = true ]; then
    section "Discord"

    if ! command -v discord &>/dev/null; then
        log "Installing Discord..."

        DISCORD_DEB="/tmp/discord.deb"
        wget -q -O "$DISCORD_DEB" "https://discord.com/api/download?platform=linux&format=deb"
        sudo apt install -y "$DISCORD_DEB"
        rm -f "$DISCORD_DEB"

        log "Discord installed."
    else
        info "Discord already installed, skipping."
    fi
fi

###############################################################################
# OBS STUDIO
# Optional — screen capture/streaming. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_OBS" = true ]; then
    section "OBS Studio"

    if ! command -v obs &>/dev/null; then
        log "Installing OBS Studio..."
        sudo apt install -y obs-studio
        log "OBS Studio installed."
    else
        info "OBS Studio already installed, skipping."
    fi
fi

###############################################################################
# GOOGLE ANTIGRAVITY
# Optional — browser extension helper. Useless in WSL2 or headless servers.
###############################################################################

if [ "$DO_ANTIGRAVITY" = true ]; then
    section "Google Antigravity"

    if ! command -v antigravity &>/dev/null; then
      log "Installing Google Antigravity..."

      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
      sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
      echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
      sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

      sudo apt update
      sudo apt install -y antigravity

      log "Google Antigravity installed."
    else
      info "Google Antigravity already installed, skipping."
    fi
fi

###############################################################################
# FINISHED
###############################################################################

section "Done"

log "Debian CLI environment setup complete."
echo ""
info "Restart your shell:  exec zsh"

if [ "$DO_DOCKER" = true ]; then
    warning "Docker: log out and back in (or run 'newgrp docker') for group membership."
fi

if [ "$DO_QEMU" = true ]; then
    warning "QEMU: log out and back in (or run 'newgrp libvirt') for group membership."
fi
