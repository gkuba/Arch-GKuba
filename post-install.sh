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

# Cooling packages
COOLING_PACKAGES="coolercontrol coolercontrold"

# AUR package definition
VSCODE_PACKAGE="visual-studio-code-bin"

# GitHub Repo for Wallpapers
REPO_URL="https://github.com/gkuba/Arch-GKuba"

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
    read -r -p "Install cooling manager control tools (CoolerControl)? (y/N): " install_cooling
    if [[ "$install_cooling" =~ ^[Yy]$ ]]; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $COOLING_PACKAGES"
        echo -e "${GREEN}→ Added cooling packages${ENDCOLOR}"
    fi

    echo
    read -r -p "Setup Wallpapers? (Pulls repository and symlinks to ~/Pictures/Wallpapers) (y/N): " setup_wallpapers
    if [[ "$setup_wallpapers" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}→ Added Wallpaper pipeline to sequence${ENDCOLOR}"
    fi

    echo
    echo -e "${YELLOW}Ready to proceed with the following actions:${RESET}"
    echo "   • Synchronize system repositories and core system update"
    echo "   • Target packages: $PACKAGES_TO_INSTALL"
    [[ "$install_vscode" =~ ^[Yy]$ ]] && echo "   • Visual Studio Code (via paru AUR pipeline)"
    [[ "$setup_wallpapers" =~ ^[Yy]$ ]] && echo "   • Clone $REPO_URL and map Wallpapers directory"
    echo

    read -r -p "Press [Enter] to execute installation matrix or type Q to quit: " confirm

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

    # ── Post-install Daemon Hooks ────────────────────────────────────────────
    if [[ "$PACKAGES_TO_INSTALL" == *coolercontrold* ]]; then
        echo
        info "Enabling and starting CoolerControl system daemon..."
        sudo systemctl enable --now coolercontrold
        sudo systemctl status coolercontrold --no-pager || true
    fi

    # ── Wallpaper Pipeline ───────────────────────────────────────────────────
    if [[ "$setup_wallpapers" =~ ^[Yy]$ ]]; then
        echo
        info "Beginning Wallpaper configuration..."

        local repo_dir="$HOME/Arch-GKuba"
        local pictures_dir="$HOME/Pictures"
        local target_link="$pictures_dir/Wallpapers"

        # Safe cloning
        if [[ -d "$repo_dir" ]]; then
            warn "Directory $repo_dir already exists. Pulling latest updates..."
            (cd "$repo_dir" && git pull)
        else
            info "Cloning configuration repo into user home directory..."
            git clone "$REPO_URL" "$repo_dir"
        fi

        # Process the Wallpapers folder specifically
        if [[ -d "$repo_dir/Wallpapers" ]]; then
            # Ensure ~/Pictures target environment exists
            mkdir -p "$pictures_dir"

            # Clean path check for symlink deployment
            if [[ -L "$target_link" ]]; then
                info "Updating existing Wallpapers symlink..."
                rm "$target_link"
            elif [[ -d "$target_link" ]]; then
                warn "A physical directory already exists at $target_link. Backing up to $target_link.bak..."
                mv "$target_link" "${target_link}.bak"
            fi

            ln -s "$repo_dir/Wallpapers" "$target_link"
            success "Wallpapers folder dynamically linked to $target_link!"
        else
            error "Could not locate 'Wallpapers' directory inside the cloned repository."
        fi
    fi

    echo
    success "Post-installation sequence completed successfully!"

    # ── Self Destruct Protocol ────────────────────────────────────────────────
    # Because you are running this script directly via a curl piper, we use a
    # safe check. If it exists on the local storage system, it cleans itself up.
    if [[ -f "$0" ]]; then
        info "Cleaning up installer execution file..."
        rm -- "$0"
    fi
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
