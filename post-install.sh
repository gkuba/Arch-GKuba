#!/usr/bin/env bash
# =============================================================================
# Arch-based Post-Install Script
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
EXTRA_PACKAGES="discord code ghostty vivaldi coolercontrol coolercontrold spotify-launcher"
EXTRA_AUR_PACKAGES="visual-studio-code-bin"

# ── Help ───────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [FUNCTION...]

Available functions:
  checkUpdates     Update system packages
  installPackages  Install wanted packages
  dnsStubFix       Disable systemd-resolved stub and configure DNS

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

# ── Install paru only if not already installed ────────────────────────────────
install_paru_if_needed() {
    if ! command -v paru >/dev/null 2>&1; then
        info "paru (AUR helper) is not installed. Installing now..."
        sudo pacman -S --noconfirm --needed base-devel git
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru
        makepkg -si --noconfirm
        cd -
        rm -rf /tmp/paru
        success "paru installed successfully"
    else
        info "paru is already installed."
    fi
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
    echo -e "${YELLOW}Packages: ${packages}${ENDCOLOR}"
    echo

    pacman -S --noconfirm $packages
    success "Packages installed successfully"
}

dnsStubFix() {
    echo
    read -r -p "Do you want to disable systemd-resolved stub and configure custom DNS? (y/N): " do_fix < /dev/tty

    if [[ ! "$do_fix" =~ ^[Yy]$ ]]; then
        echo "DNS Stub Fix skipped."
        return 0
    fi

    echo
    read -r -p "Primary nameserver (e.g. 10.13.37.2): " primary_dns < /dev/tty
    read -r -p "Secondary nameserver (leave blank for none): " secondary_dns < /dev/tty
    read -r -p "Search domain (e.g. pixelville.games, leave blank for none): " search_domain < /dev/tty

    if [[ -z "$primary_dns" ]]; then
        primary_dns="1.1.1.1"
    fi

    info "Configuring DNS with primary: $primary_dns"

    sudo systemctl stop systemd-resolved.service systemd-resolved-monitor.socket systemd-resolved-varlink.socket 2>/dev/null || true
    sudo systemctl disable systemd-resolved.service 2>/dev/null || true

    {
        echo "nameserver $primary_dns"
        [[ -n "$secondary_dns" ]] && echo "nameserver $secondary_dns"
        [[ -n "$search_domain" ]] && echo "search $search_domain"
        echo "options edns0"
    } | sudo tee /etc/resolv.conf >/dev/null

    sudo chattr +i /etc/resolv.conf

    success "DNS configured successfully. Stub resolver disabled."
    echo -e "${CYAN}→ resolv.conf is now immutable. Use 'sudo chattr -i /etc/resolv.conf' to edit later.${RESET}"
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

    echo -e "${BLUE}Extra AUR Packages (optional):${ENDCOLOR}"
    echo "  ${EXTRA_AUR_PACKAGES}"
    echo

    read -r -p "Install extra packages (discord, code, ghostty, vivaldi)? (y/N): " install_extra < /dev/tty
    read -r -p "Install extra AUR packages (visual-studio-code-bin)? (y/N): " install_aur_extra < /dev/tty

    PACKAGES_TO_INSTALL="$CORE_PACKAGES"

    if [[ "$install_extra" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $EXTRA_PACKAGES"
    fi

    if [[ "$install_aur_extra" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $EXTRA_AUR_PACKAGES"
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

    # Install paru only if needed for AUR packages
    if [[ "$install_aur_extra" =~ ^[Yy]$ ]]; then
        install_paru_if_needed
        info "Installing AUR package: visual-studio-code-bin"
        paru -S --noconfirm visual-studio-code-bin
        success "visual-studio-code-bin installed"
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
