# Arch-GKuba Post-Install

A personal post-install script for Arch-based systems, including CachyOS. It
installs selected package groups and can configure the CoolerControl service.

Run it as your regular user. The script uses `sudo` only for system package,
service, and configuration changes. It does not need to be started from a root
shell.

## Interactive setup

Running without an action starts the wizard:

```bash
./post-install.sh
```

To download and run the current script directly from a Bash-compatible terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-GKuba/main/post-install.sh)
```

The wizard always includes the core packages. It then offers these optional
selections:

- **Extra Desktop Apps:** Discord, Ghostty, Obsidian, Vivaldi,
  Spotify Launcher, and Solaar.
- **CoolerControl and MSI sensor support:** CoolerControl, its daemon,
  `liquidctl`, and `nct6687d-dkms-git` from the AUR. The CoolerControl profile
  is downloaded from the DESetupLinux repository, the daemon is enabled, and
  an existing `/etc/coolercontrol/config.toml` is backed up before replacement.
- **Desktop environment items:** wallpapers and cursor themes from DESetupLinux.
  Choose either or both when prompted; skip this option on headless systems.

Before making changes, the wizard summarizes the selected actions and asks for
confirmation. It then updates the system and installs the selected packages.
After approval, package manager confirmation prompts are skipped. The script
also ensures `paru` is installed through pacman and refreshes the font cache.

The core packages include Zsh and Starship. If Zsh is not already the login
shell, the wizard asks whether to set it as the default and verifies the change.
Starship is installed from pacman when available, with its upstream installer
retained as a fallback. The script does not clone or build paru from an
external repository.

## Run an action directly

Each package action updates the system and installs its named group. The
cooling action also installs the AUR sensor driver and applies the CoolerControl
profile. `installDesktopAssets` prompts you to choose wallpapers, cursors, or
both, then copies them into the matching user directories without removing
unrelated files. This action does not update packages.

```bash
./post-install.sh installCorePackages
./post-install.sh installExtraDesktopApps
./post-install.sh installCooling
./post-install.sh installDesktopAssets
```

Run the script without an action to use the full interactive wizard.

Show usage with:

```bash
./post-install.sh --help
```

The lower-level package and system helpers are internal implementation details
and are not supported command-line actions.

## Core packages

Git, curl, unzip, 7zip, Neovim, Fastfetch, fzf, Fira Code, Zsh, and Starship.

Package lists are kept near the top of `post-install.sh`, grouped by package
manager. The script currently maps the groups to pacman and the MSI sensor
package to the AUR.

## Dotfiles

The separate dotfiles repository and setup script are available at
[github.com/gkuba/dotfiles](https://github.com/gkuba/dotfiles). Local hosts-file
entries are managed by that dotfiles setup, not by this post-install script.
