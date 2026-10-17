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

The wizard always includes the core package group, then asks whether to install
the listed Extra Desktop Apps, the CoolerControl/MSI sensor group, and optional
DESetupLinux wallpapers and/or cursor themes. Headless systems can skip the
desktop assets. It shows a summary and asks before applying changes. It updates the system, installs the
selected packages, ensures `paru` is installed through pacman, and refreshes the
font cache. The core group includes Zsh and Starship. If Zsh is not already the
login shell, the wizard asks whether to set it as the default and verifies the
account change after installation. Starship is installed from pacman when
available; its upstream installer is retained as a fallback. Package manager
confirmation prompts are skipped after you approve the wizard plan. The script
does not clone or build paru from an external repository.

The optional groups are:

- **Extra Desktop Apps:** Discord, Ghostty, Obsidian, Vivaldi,
  Spotify Launcher, and Solaar.
- **CoolerControl and MSI sensor support:** CoolerControl, its daemon,
  `liquidctl`, and `nct6687d-dkms-git` from the AUR. The CoolerControl profile
  is downloaded from the DESetupLinux repository, the daemon is enabled, and
  an existing `/etc/coolercontrol/config.toml` is backed up before replacement.

## Run one package group or desktop assets

The package actions update the system and install only their named group; the
cooling action also installs the AUR sensor driver and applies the
CoolerControl profile. The desktop-assets action prompts for wallpapers,
cursors, or both and copies the selected DESetupLinux assets into the user's
asset directories while retaining unrelated files. It does not update packages.

```bash
./post-install.sh installCorePackages
./post-install.sh installExtraDesktopApps
./post-install.sh installCooling
./post-install.sh installDesktopAssets
```

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
