#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Folders
CONFIG="$HOME/.config"
DOTFILES="/tmp/dotfiles"

# if --dont-update is passed as an argument, skip the update step
if [ "$1" == "--dont-update" ]; then
    SKIP_UPDATE=true
else
    SKIP_UPDATE=false
fi

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

cleanup() {
    log "Cleaning up..."
    rm -rf "$DOTFILES"
    exit
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "Don't run this script as root!"
fi

# Check if we have sudo access
if ! sudo -v; then
    error "This script requires sudo access"
fi

log "Starting Linux setup automation..."

# Update and upgrade system
if [ "$SKIP_UPDATE" != true ]; then
    log "Updating and upgrading system packages..."
    sudo apt update && sudo apt upgrade -y
fi

# Install curl becase it's not installed by default on Debian
log "Installing curl..."
sudo apt install -y curl

# Install git
log "Installing git..."
sudo apt install -y git

# Install ripgrep
log "Installing ripgrep..."
sudo apt install -y ripgrep

# Install xdotool
log "Installing xdotool..."
sudo apt install -y xdotool

# Install xclip
log "Installing xclip..."
sudo apt install -y xclip

# Install unzip
log "Installing unzip..."
sudo apt install -y unzip

# Installing imagemagick
log "Installing imagemagick..."
sudo apt install -y imagemagick

# Get my dotfiles!
log "Cloning dotfiles..."
if [ -d "$DOTFILES" ]; then
    rm -rf "$DOTFILES"
fi
git clone "https://github.com/Toriality1/dotfiles.git" "$DOTFILES"

# Install i3wm
log "Installing i3wm..."
sudo apt install -y i3 i3status i3lock dmenu

# Set up i3wm configuration
log "Setting up i3wm configuration..."
if [ -d "$CONFIG/i3" ]; then
    cp -r "$DOTFILES/.config/i3" "$CONFIG"
else
    mkdir -p "$CONFIG/i3"
    cp -r "$DOTFILES/.config/i3" "$CONFIG"
fi
log "i3wm set up successfully"

# Install Neovim from GitHub releases
log "Installing Neovim v0.11.2 from GitHub..."
NVIM_URL="https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.appimage"
cd /tmp
wget -O nvim.appimage "$NVIM_URL"
chmod +x nvim.appimage
if [ -f /usr/bin/nvim ]; then
    sudo rm /usr/bin/nvim
fi
sudo mv nvim.appimage /usr/bin/nvim

# Set up Neovim configuration
log "Setting up Neovim configuration..."
if [ -d "$CONFIG/nvim" ]; then
    cp -r "$DOTFILES/.config/nvim" "$CONFIG"
else
    mkdir -p "$CONFIG/nvim"
    cp -r "$DOTFILES/.config/nvim" "$CONFIG"
fi
log "Neovim v0.11.2 set up successfully"

# Install Alacritty
log "Installing Alacritty..."
sudo apt install -y alacritty

# Set up Alacritty configuration
log "Setting up Alacritty configuration..."
if [ -d "$CONFIG/alacritty" ]; then
    cp -r "$DOTFILES/.config/alacritty" "$CONFIG"
else
    mkdir -p "$CONFIG/alacritty"
    cp -r "$DOTFILES/.config/alacritty" "$CONFIG"
fi
log "Alacritty set up successfully"

# Install zsh
log "Installing zsh..."
sudo apt install -y zsh

# Set up zsh configuration
log "Setting up zsh configuration..."
cp "$DOTFILES/.zshenv" "$HOME/.zshenv"
if [ -d "$CONFIG/zsh" ]; then
    cp -r "$DOTFILES/.config/zsh" "$CONFIG"
else
    mkdir -p "$CONFIG/zsh"
    cp -r "$DOTFILES/.config/zsh" "$CONFIG"
fi
log "zsh set up successfully"

# Install oh-my-zsh
log "Installing oh-my-zsh..."
if [ ! -d "$HOME/.local/share/.oh-my-zsh" ]; then
    ZDOTDIR="$HOME/.config/zsh" ZSH="$HOME/.local/share/.oh-my-zsh" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
else
    rm -rf "$HOME/.local/share/.oh-my-zsh"
    ZDOTDIR="$HOME/.config/zsh" ZSH="$HOME/.local/share/.oh-my-zsh" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
fi
log "oh-my-zsh installed successfully"

# Install oh-my-zsh plugins
log "Installing oh-my-zsh plugins..."
if [ ! -d "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
fi
if [ ! -d "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.local/share/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
fi
log "oh-my-zsh plugins installed successfully"

# Set zsh as default shell
log "Setting zsh as default shell..."
if [ "$SHELL" != "/usr/bin/zsh" ] && [ "$SHELL" != "/bin/zsh" ]; then
    chsh -s $(which zsh)
    warning "Please log out and log back in for shell change to take effect"
else
    log "zsh is already the default shell"
fi

# Install tmux
log "Installing tmux..."
sudo apt install -y tmux

# Set up tmux configuration
log "Setting up tmux configuration..."
if [ -d "$CONFIG/tmux" ]; then
    cp -r "$DOTFILES/.config/tmux" "$CONFIG"
else
    mkdir -p "$CONFIG/tmux"
    cp -r "$DOTFILES/.config/tmux" "$CONFIG"
fi
log "tmux set up successfully"

# Install tpm
log "Installing tpm..."
if [ -d "$CONFIG/tmux/plugins/tpm" ]; then
    rm -rf "$CONFIG/tmux/plugins/tpm"
fi
git clone https://github.com/tmux-plugins/tpm "$CONFIG/tmux/plugins/tpm"
log "tpm installed successfully"

# Install zathura
log "Installing zathura..."
sudo apt install -y zathura
log "zathura installed successfully"

# Install node and npm
log "Installing NodeJS v22.17.0 LTS and pnpm via fnm..."
curl -o- https://fnm.vercel.app/install | bash -s -- --skip-shell
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env | sed 's/rehash/hash -r/g')"
fnm install 22
fnm use 22
corepack enable pnpm
corepack prepare pnpm
echo "Node version: $(node -v)"
echo "pnpm version: $(pnpm -v)"
log "NodeJS and pnpm installed successfully"

# Install python3
log "Installing python3..."
sudo apt install -y python3
log "python3 installed successfully"

# End
log "Setup complete! It's recommended to reboot your system."
cleanup
