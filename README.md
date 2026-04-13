# Arch-Gkuba Post-Install

This is my personal post-install script for fresh Arch Linux and CachyOS installations.

It handles system updates and installs a curated set of essential and extra packages.

---

## Requirements

- Must be run as root (sudo su first)
- Arch-based system (Arch Linux, CachyOS, EndeavourOS, etc.)

---

## Quick Install (Full Setup)

Run the following command as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-Gkuba/main/post-install.sh)
```

---

## Modular Usage

The script supports running specific parts only.

### Available Functions

Function          | Description
------------------|--------------------------------------------------
checkUpdates      | Update the system (pacman -Syu)
installPackages   | Install the core + extra packages

### Examples

```bash
# Run full setup (default)
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-Gkuba/main/post-install.sh)

# Only update the system
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-Gkuba/main/post-install.sh) checkUpdates

# Only install packages
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-Gkuba/main/post-install.sh) installPackages

# Only dnsStubFix
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-Gkuba/main/post-install.sh) dnsStubFix
```
---

## Packages Installed

Core Packages:
- git curl unzip neovim fastfetch fzf

Extra Packages (optional - you will be prompted):
- discord code ghostty vivaldi

---

## My Dotfiles

My full dotfiles (.zshrc, Starship config, Neovim config, etc.) can be found here:

→ https://github.com/gkuba/dotfiles

---

Note:
After running this post-install script, I recommend running my separate setup-dotfiles.sh script to pull in my complete configuration.
