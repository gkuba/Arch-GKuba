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

# Extra packages
EXTRA_PACKAGES="discord ghostty obsidian vivaldi spotify-launcher solaar"

# Separate prompts
VSCODE_PACKAGE="visual-studio-code-bin"
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
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Please use 'sudo su' first."
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
    pacman -Syu --noconfirm
    success "System updated"
}

installPackages() {
    local packages="$1"
    info "Installing packages..."

    # Sync AUR and official repos first (important for AUR packages)
    info "Syncing package databases..."
    paru -Sy

    echo -e "${YELLOW}Packages: ${packages}${ENDCOLOR}"
    echo

    paru -S --noconfirm $packages
    success "Packages installed successfully"
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

    # VS Code prompt
    echo
    read -r -p "Install Visual Studio Code (visual-studio-code-bin)? (y/N): " install_vscode < /dev/tty
    if [[ "$install_vscode" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $VSCODE_PACKAGE"
        echo -e "${GREEN}→ Will also install Visual Studio Code${ENDCOLOR}"
    fi

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
    echo

    read -r -p "Press [Enter] to continue or type Q to quit: " confirm < /dev/tty

    if [[ "$confirm" =~ ^[Qq]$ ]]; then
        echo "Setup cancelled by user."
        exit 0
    fi

    checkUpdates
    installPackages "$PACKAGES_TO_INSTALL"

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
    # Default: Interactive mode
    interactive_mode
fi

exit 0
