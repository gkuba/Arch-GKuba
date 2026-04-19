#!/usr/bin/env bash
# =============================================================================
# Arch-based Post-Install Script - GKuba Edition
# =============================================================================

set -euo pipefail

# ── Colors (All defined at the top) ───────────────────────────────────────────
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
ENDCOLOR="\e[0m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Configuration ──────────────────────────────────────────────────────────────
CORE_PACKAGES="git curl unzip neovim fastfetch fzf"

# Extra packages (installed with pacman)
EXTRA_PACKAGES="discord ghostty obsidian vivaldi spotify-launcher solaar"

# AUR packages (installed with paru)
AUR_PACKAGES="visual-studio-code-bin"

# Cooling packages
COOLING_PACKAGES="coolercontrol coolercontrold"

# ── Help ───────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [FUNCTION...]

Available functions:
  checkUpdates     Update system packages
  installPackages  Install wanted packages

If no arguments are given, the script runs interactively.
EOF
    exit 0
}

# ── Check if running as root ───────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    error "This script should NOT be run as root."
    error "Please run it as your normal user. sudo will be used where needed."
    exit 1
fi

# ── Check if running on Arch-based system ──────────────────────────────────────
check_arch_based() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS. This script is for Arch-based systems only."
        exit 1
    fi

    source /etc/os-release

    if [[ "$ID" != "arch" && "$ID_LIKE" != *"arch"* ]]; then
        error "This script is designed for Arch-based distributions only."
        error "Detected: ${PRETTY_NAME:-Unknown}"
        exit 1
    fi

    info "Detected Arch-based system: ${PRETTY_NAME}"
}

# ── Functions ──────────────────────────────────────────────────────────────────

checkUpdates() {
    info "Checking for and installing system updates..."
    sudo pacman -Syu --noconfirm
    success "System updated"
}

installPackages() {
    local packages="$1"
    info "Installing official packages with pacman..."

    sudo pacman -S --noconfirm $packages
    success "Official packages installed successfully"
}

# ── Interactive Mode ───────────────────────────────────────────────────────────
interactive_mode() {
    echo -e "${CYAN}===================================================${ENDCOLOR}"
    echo -e "          ${BLUE}Arch-based Post-Install Script${ENDCOLOR}"
    echo -e "${CYAN}===================================================${ENDCOLOR}"
    echo

    echo -e "${BLUE}System Information:${ENDCOLOR}"
    echo -e "  Hostname:      ${GREEN}$(hostname)${ENDCOLOR}"
    echo -e "  OS:            ${GREEN}$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)${ENDCOLOR}"
    echo

    echo -e "${BLUE}Core Packages:${ENDCOLOR}"
    echo "  ${CORE_PACKAGES}"
    echo

    echo -e "${BLUE}Extra Packages (optional):${ENDCOLOR}"
    echo "  ${EXTRA_PACKAGES}"
    echo

    read -r -p "Install extra packages? (y/N): " install_extra < /dev/tty

    if [[ "$install_extra" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$CORE_PACKAGES $EXTRA_PACKAGES"
        echo -e "${GREEN}→ Will install core + extra packages${ENDCOLOR}"
    else
        PACKAGES_TO_INSTALL="$CORE_PACKAGES"
        echo -e "${YELLOW}→ Will install core packages only${ENDCOLOR}"
    fi

    # VS Code prompt (AUR package)
    echo
    read -r -p "Install Visual Studio Code (visual-studio-code-bin from AUR)? (y/N): " install_vscode < /dev/tty

    # Cooling packages prompt
    echo
    read -r -p "Install cooling packages (coolercontrol + coolercontrold)? (y/N): " install_cooling < /dev/tty
    if [[ "$install_cooling" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $COOLING_PACKAGES"
        echo -e "${GREEN}→ Will also install cooling packages${ENDCOLOR}"
    fi

    echo
    echo -e "${YELLOW}Ready to proceed with the following:${RESET}"
    echo "   • System update"
    echo "   • Install: $PACKAGES_TO_INSTALL"
    [[ "$install_vscode" =~ ^[Yy]$ ]] && echo "   • Visual Studio Code (via paru)"
    echo

    read -r -p "Press [Enter] to continue or type Q to quit: " confirm < /dev/tty

    if [[ "$confirm" =~ ^[Qq]$ ]]; then
        echo "Setup cancelled by user."
        exit 0
    fi

    checkUpdates
    installPackages "$PACKAGES_TO_INSTALL"

    # Install VS Code with paru (AUR only)
    if [[ "$install_vscode" =~ ^[Yy]$ ]]; then
        info "Installing Visual Studio Code from AUR..."
        paru -S --noconfirm "$VSCODE_PACKAGE"
        success "Visual Studio Code installed"
    fi

    # ── Post-install actions ─────────────────────────────────────────────────
    if [[ "$PACKAGES_TO_INSTALL" == *coolercontrold* ]]; then
        echo
        info "Enabling and starting CoolerControl daemon..."
        sudo systemctl enable --now coolercontrold
        sudo systemctl status coolercontrold --no-pager
    fi

    echo
    success "Post-installation completed successfully!"
}

# ── Main Logic ─────────────────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if declare -f "$arg" >/dev/null; then
            "$arg"
        else
            error "No such function: $arg"
            usage
        fi
    done
else
    interactive_mode
fi

exit 0
