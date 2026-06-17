#!/usr/bin/env bash
# =============================================================================
# Arch-based Post-Install Script - GKuba Edition
# =============================================================================

set -euo pipefail

# ── Colors (Standardized with \033 for uniform cross-environment rendering) ───
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
ENDCOLOR="\033[0m"
RESET="\033[0m"

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Configuration ──────────────────────────────────────────────────────────────
CORE_PACKAGES="git curl unzip neovim fastfetch fzf"

# Extra packages (installed with pacman)
EXTRA_PACKAGES="discord ghostty obsidian vivaldi spotify-launcher solaar"

# Cooling packages (liquidctl added here)
COOLING_PACKAGES="coolercontrol coolercontrold liquidctl"

# AUR package definitions
VSCODE_PACKAGE="visual-studio-code-bin"
MSI_SENSOR_PACKAGE="nct6687d-dkms-git"

# Remote configuration endpoints
COOLERCONTROL_CONFIG_URL="https://raw.githubusercontent.com/gkuba/DESetupLinux/refs/heads/main/coolercontrol/config.toml"

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

# ── Helper Functions ───────────────────────────────────────────────────────────

checkUpdates() {
    info "Checking for system updates..."
    sudo pacman -Syu --noconfirm
    success "System updated successfully"
}

installPackages() {
    local pkgs="$1"
    if [[ -n "$pkgs" ]]; then
        info "Installing packages: $pkgs"
        sudo pacman -S --needed --noconfirm $pkgs
        success "Packages installed successfully"
    else
        warn "No packages specified for installation"
    fi
}

# ── Interactive Mode ───────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${MAGENTA}===================================================${RESET}"
    echo -e "${CYAN}        Arch Post-Installation Wizard${RESET}"
    echo -e "${MAGENTA}===================================================${RESET}"
    echo

    # Check for paru installation
    if ! command -v paru >/dev/null 2>&1; then
        warn "paru (AUR helper) is not installed."
        read -r -p "Would you like to install paru now? (y/N): " install_paru
        if [[ "$install_paru" =~ ^[Yy]$ ]]; then
            info "Installing paru dependencies..."
            sudo pacman -S --needed --noconfirm base-devel

            info "Cloning and building paru..."
            local tmp_dir=$(mktemp -d)
            git clone https://aur.archlinux.org/paru-bin.git "$tmp_dir"
            (cd "$tmp_dir" && makepkg -si --noconfirm)
            rm -rf "$tmp_dir"
            success "paru installed successfully"
        else
            error "paru is required for AUR packages. Exiting script."
            exit 1
        fi
    fi

    PACKAGES_TO_INSTALL="$CORE_PACKAGES"

    # ── Component Prompts ─────────────────────────────────────────────────────
    echo
    read -r -p "Install extra desktop applications? (Discord, Ghostty, Vivaldi, etc.) (y/N): " install_extra
    if [[ "$install_extra" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $EXTRA_PACKAGES"
        echo -e "${GREEN}→ Added extra packages${ENDCOLOR}"
    fi

    echo
    read -r -p "Install Visual Studio Code from the AUR? (y/N): " install_vscode

    echo
    read -r -p "Install cooling manager control tools (CoolerControl & MSI Nuvoton Driver)? (y/N): " install_cooling
    if [[ "$install_cooling" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $COOLING_PACKAGES"
        echo -e "${GREEN}→ Added cooling packages (including liquidctl)${ENDCOLOR}"
    fi

    echo
    echo -e "${YELLOW}Ready to proceed with the following actions:${RESET}"
    echo "   • Synchronize system repositories and core system update"
    echo "   • Target packages: $PACKAGES_TO_INSTALL"
    [[ "$install_vscode" =~ ^[Yy]$ ]] && echo "   • Visual Studio Code (via paru AUR pipeline)"
    [[ "$install_cooling" =~ ^[Yy]$ ]] && echo "   • MSI Motherboard Fan Driver ($MSI_SENSOR_PACKAGE via paru AUR pipeline)"
    echo

    read -r -p "Press [Enter] to continue with package installation or type Q to quit: " confirm

    if [[ "$confirm" =~ ^[Qq]$ ]]; then
        echo "Setup cancelled by user."
        exit 0
    fi

    checkUpdates
    installPackages "$PACKAGES_TO_INSTALL"

    # Install VS Code with paru cleanly if flagged
    if [[ "$install_vscode" =~ ^[Yy]$ ]]; then
        info "Installing Visual Studio Code from AUR..."
        paru -S --needed --noconfirm "$VSCODE_PACKAGE"
        success "Visual Studio Code installation synced"
    fi

    # Combined Cooling Module Execution Block
    if [[ "$install_cooling" =~ ^[Yy]$ ]]; then
        info "Installing MSI Nuvoton sensor kernel module from AUR..."
        paru -S --needed --noconfirm "$MSI_SENSOR_PACKAGE"
        success "MSI sensor module installation complete"

        echo
        info "Ensuring CoolerControl service is inactive for configuration injection..."
        sudo systemctl stop coolercontrold || true

        info "Fetching custom optimized fan curve profile..."
        local tmp_config=$(mktemp)
        curl -fsSL "$COOLERCONTROL_CONFIG_URL" -o "$tmp_config"

        info "Deploying custom configurations to root directory..."
        sudo mkdir -p /etc/coolercontrol
        sudo mv "$tmp_config" /etc/coolercontrol/config.toml
        success "Custom profile successfully injected"

        echo
        info "Enabling and starting CoolerControl system daemon..."
        sudo systemctl enable --now coolercontrold
        sudo systemctl status coolercontrold --no-pager || true
    fi

    echo
    success "Post-installation sequence completed successfully!"
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
    main
fi
